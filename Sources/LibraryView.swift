import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Copies the picked video into the temp dir so AVFoundation can read it.
struct PickedVideo: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedVideo(url: dest)
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var store: TourStore
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingVideo: URL?
    @State private var showOptions = false
    @State private var interval: Double = 1.5
    @State private var tourName = ""
    @State private var isWorking = false
    @State private var progress: Double = 0
    @State private var errorText: String?
    @State private var openTour: Tour?

    private let accent = Color(red: 1.0, green: 0.77, blue: 0.36)

    var body: some View {
        NavigationStack {
            Group {
                if store.tours.isEmpty { emptyState } else { list }
            }
            .background(Color(red: 0.06, green: 0.08, blue: 0.11).ignoresSafeArea())
            .navigationTitle("WalkTour")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $pickerItem, matching: .videos) {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .disabled(isWorking)
                }
            }
            .fullScreenCover(item: $openTour) { tour in
                TourViewer(tour: tour).environmentObject(store)
            }
            .sheet(isPresented: $showOptions) { optionsSheet }
            .overlay { if isWorking { workingOverlay } }
            .alert("Couldn't build tour", isPresented: Binding(get: { errorText != nil },
                                                               set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorText ?? "") }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await loadPicked(item) }
            }
        }
        .tint(accent)
    }

    // MARK: - Pieces

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.walk.motion").font(.system(size: 56)).foregroundStyle(accent)
            Text("Turn a walk-through video into a tour")
                .font(.title3.weight(.semibold))
            Text("Pick a video you filmed while slowly walking through a space. WalkTour cuts it into stops you can hop between.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            PhotosPicker(selection: $pickerItem, matching: .videos) {
                Label("Choose video", systemImage: "video.badge.plus")
                    .font(.headline).padding(.horizontal, 22).padding(.vertical, 12)
                    .background(accent, in: Capsule()).foregroundStyle(.black)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(store.tours) { tour in
                Button { openTour = tour } label: {
                    HStack(spacing: 14) {
                        thumb(tour)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tour.name).font(.headline)
                            Text("\(tour.frameCount) stops · \(tour.created.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) { store.delete(tour) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 720)               // readable column on iPad
        .frame(maxWidth: .infinity)
    }

    private func thumb(_ tour: Tour) -> some View {
        let url = store.frameURL(tour, tour.startFrame)
        return Group {
            if let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(width: 84, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var optionsSheet: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("e.g. 12 Maple St", text: $tourName) }
                Section {
                    VStack(alignment: .leading) {
                        Text("A stop every \(interval, specifier: "%.1f") s")
                        Slider(value: $interval, in: 0.5...4, step: 0.5)
                    }
                } header: { Text("Spacing") } footer: {
                    Text("Smaller = smoother walking, more photos. 1–2 s suits a slow walk.")
                }
            }
            .navigationTitle("New tour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancelPending() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Build") { showOptions = false; Task { await build() } }
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }

    private var workingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: progress).frame(width: 200)
                Text("Cutting stops… \(Int(progress * 100))%").font(.subheadline)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Actions

    private func loadPicked(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        isWorking = true; progress = 0
        do {
            guard let video = try await item.loadTransferable(type: PickedVideo.self) else {
                isWorking = false; errorText = "The video couldn't be loaded."; return
            }
            isWorking = false
            pendingVideo = video.url
            tourName = "Tour \(store.tours.count + 1)"
            showOptions = true
        } catch {
            isWorking = false
            errorText = error.localizedDescription
        }
    }

    private func cancelPending() {
        if let u = pendingVideo { try? FileManager.default.removeItem(at: u) }
        pendingVideo = nil
        showOptions = false
    }

    private func build() async {
        guard let video = pendingVideo else { return }
        let id = UUID()
        let folder = store.newTourFolder(id: id)
        isWorking = true; progress = 0
        do {
            let count = try await FrameExtractor.extract(from: video, to: folder, interval: interval) { p in
                Task { @MainActor in progress = p }
            }
            let name = tourName.trimmingCharacters(in: .whitespaces)
            let tour = Tour(id: id, name: name.isEmpty ? "Untitled tour" : name, frameCount: count)
            store.add(tour)
            isWorking = false
            try? FileManager.default.removeItem(at: video)
            pendingVideo = nil
            openTour = tour
        } catch {
            isWorking = false
            try? FileManager.default.removeItem(at: folder)
            errorText = error.localizedDescription
            pendingVideo = nil
        }
    }
}
