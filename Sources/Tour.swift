import SwiftUI
import UIKit

/// One walkthrough: a folder of JPEG frames plus a small JSON manifest.
struct Tour: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var created: Date = Date()
    var frameCount: Int
    /// Optional room labels keyed by frame index ("Kitchen" at frame 12).
    var labels: [Int: String] = [:]
    var startFrame: Int = 0
}

@MainActor
final class TourStore: ObservableObject {
    @Published private(set) var tours: [Tour] = []

    private let root: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Tours", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    init() { load() }

    func folder(for tour: Tour) -> URL {
        root.appendingPathComponent(tour.id.uuidString, isDirectory: true)
    }

    func frameURL(_ tour: Tour, _ index: Int) -> URL {
        folder(for: tour).appendingPathComponent(String(format: "f%04d.jpg", index))
    }

    func newTourFolder(id: UUID) -> URL {
        let url = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func add(_ tour: Tour) {
        tours.insert(tour, at: 0)
        save(tour)
    }

    func update(_ tour: Tour) {
        guard let i = tours.firstIndex(where: { $0.id == tour.id }) else { return }
        tours[i] = tour
        save(tour)
    }

    func delete(_ tour: Tour) {
        try? FileManager.default.removeItem(at: folder(for: tour))
        tours.removeAll { $0.id == tour.id }
    }

    private func save(_ tour: Tour) {
        let url = folder(for: tour).appendingPathComponent("tour.json")
        if let data = try? JSONEncoder().encode(tour) { try? data.write(to: url, options: .atomic) }
    }

    private func load() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var found: [Tour] = []
        for d in dirs {
            let json = d.appendingPathComponent("tour.json")
            if let data = try? Data(contentsOf: json),
               let t = try? JSONDecoder().decode(Tour.self, from: data) {
                found.append(t)
            }
        }
        tours = found.sorted { $0.created > $1.created }
    }
}

/// Small in-memory image cache with neighbour prefetch so hops feel instant.
final class FrameCache {
    private let cache = NSCache<NSNumber, UIImage>()
    init() { cache.countLimit = 40 }

    func image(at url: URL, key: Int) -> UIImage? {
        if let hit = cache.object(forKey: NSNumber(value: key)) { return hit }
        guard let img = UIImage(contentsOfFile: url.path) else { return nil }
        // Force decode off the lazy path.
        let decoded = img.preparingForDisplay() ?? img
        cache.setObject(decoded, forKey: NSNumber(value: key))
        return decoded
    }
}
