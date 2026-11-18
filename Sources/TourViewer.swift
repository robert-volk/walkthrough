import SwiftUI

struct TourViewer: View {
    @EnvironmentObject var store: TourStore
    @Environment(\.dismiss) private var dismiss

    @State var tour: Tour
    @State private var index: Int
    @State private var showChrome = true
    @State private var walking = false
    @State private var walkTask: Task<Void, Never>?
    @State private var dragAccum: CGFloat = 0
    @State private var forward = true
    @State private var labelDraft = ""
    @State private var showLabelAlert = false
    @State private var zoom: CGFloat = 1

    private let cache = FrameCache()
    private let accent = Color(red: 1.0, green: 0.77, blue: 0.36)
    private let stepDistance: CGFloat = 36

    init(tour: Tour) {
        _tour = State(initialValue: tour)
        _index = State(initialValue: tour.startFrame)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            frameView
            tapZones
            if showChrome { chrome.transition(.opacity) }
        }
        .gesture(dragGesture)
        .statusBarHidden(!showChrome)
        .onAppear { prefetch() }
        .onChange(of: index) { _, _ in prefetch() }
        .onDisappear { stopWalking() }
        .alert("Label this spot", isPresented: $showLabelAlert) {
            TextField("Kitchen, Bedroom…", text: $labelDraft)
            Button("Save") { setLabel(labelDraft) }
            if tour.labels[index] != nil { Button("Remove", role: .destructive) { setLabel("") } }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Frame

    private var frameView: some View {
        GeometryReader { geo in
            if let img = cache.image(at: store.frameURL(tour, index), key: index) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(zoom)
                    .id(index)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: forward ? 0.97 : 1.03)),
                        removal: .opacity))
            }
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.28), value: index)
    }

    /// Left / right thirds of the screen hop back / forward; centre toggles the controls.
    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle()).onTapGesture { hop(-1) }
            Color.clear.contentShape(Rectangle()).onTapGesture {
                withAnimation { showChrome.toggle() }
            }
            Color.clear.contentShape(Rectangle()).onTapGesture { hop(1) }
        }
        .ignoresSafeArea()
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                // Dragging left walks forward, right walks back.
                let delta = -(v.translation.width) - dragAccum
                if abs(delta) >= stepDistance {
                    let steps = Int(delta / stepDistance)
                    hop(steps)
                    dragAccum += CGFloat(steps) * stepDistance
                }
            }
            .onEnded { _ in dragAccum = 0 }
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack {
            HStack(alignment: .top) {
                Button { dismiss() } label: { circleIcon("xmark") }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(tour.name).font(.headline)
                    if let label = tour.labels[index] {
                        Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 16).padding(.top, 8)

            Spacer()

            VStack(spacing: 12) {
                if !tour.labels.isEmpty { roomChips }

                Slider(value: Binding(get: { Double(index) },
                                      set: { jump(to: Int($0.rounded())) }),
                       in: 0...Double(max(tour.frameCount - 1, 1)))
                    .tint(accent)

                HStack(spacing: 28) {
                    Button { hop(-1) } label: { circleIcon("backward.frame.fill") }
                    Button { toggleWalking() } label: {
                        Image(systemName: walking ? "pause.fill" : "figure.walk")
                            .font(.title2.weight(.semibold))
                            .frame(width: 64, height: 64)
                            .background(accent, in: Circle())
                            .foregroundStyle(.black)
                    }
                    Button { hop(1) } label: { circleIcon("forward.frame.fill") }
                    Button {
                        labelDraft = tour.labels[index] ?? ""
                        showLabelAlert = true
                    } label: { circleIcon("tag.fill") }
                }
                Text("Stop \(index + 1) of \(tour.frameCount)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: 560)   // keeps the control panel compact on iPad
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
    }

    private var roomChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(tour.labels.keys.sorted(), id: \.self) { i in
                    Button { jump(to: i) } label: {
                        Text(tour.labels[i] ?? "")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(i == index ? accent : Color.white.opacity(0.15), in: Capsule())
                            .foregroundStyle(i == index ? .black : .white)
                    }
                }
            }
        }
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.body.weight(.semibold))
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
            .foregroundStyle(.white)
    }

    // MARK: - Navigation

    private func hop(_ steps: Int) {
        let target = min(max(index + steps, 0), tour.frameCount - 1)
        guard target != index else {
            if walking && steps > 0 { stopWalking() }   // reached the end
            return
        }
        forward = steps > 0
        index = target
    }

    private func jump(to i: Int) {
        let target = min(max(i, 0), tour.frameCount - 1)
        guard target != index else { return }
        forward = target > index
        index = target
    }

    private func toggleWalking() { walking ? stopWalking() : startWalking() }

    private func startWalking() {
        if index >= tour.frameCount - 1 { index = 0 }
        walking = true
        withAnimation { showChrome = false }
        walkTask = Task { @MainActor in
            while walking && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 850_000_000)
                if Task.isCancelled { break }
                hop(1)
            }
        }
    }

    private func stopWalking() {
        walking = false
        walkTask?.cancel()
        walkTask = nil
    }

    private func prefetch() {
        for d in [-2, -1, 1, 2, 3] {
            let i = index + d
            if i >= 0 && i < tour.frameCount {
                let url = store.frameURL(tour, i)
                DispatchQueue.global(qos: .utility).async { _ = cache.image(at: url, key: i) }
            }
        }
    }

    private func setLabel(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { tour.labels.removeValue(forKey: index) } else { tour.labels[index] = t }
        store.update(tour)
    }
}
