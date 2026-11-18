import AVFoundation
import UIKit

enum FrameExtractor {
    enum ExtractError: LocalizedError {
        case noVideo, noFrames
        var errorDescription: String? {
            switch self {
            case .noVideo: return "That video couldn't be read."
            case .noFrames: return "No frames could be pulled from the video."
            }
        }
    }

    /// Pulls a frame every `interval` seconds, scales to `maxEdge`, writes JPEGs.
    /// Returns the number of frames written. `progress` is called with 0...1.
    static func extract(from videoURL: URL,
                        to folder: URL,
                        interval: Double,
                        maxEdge: CGFloat = 1600,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> Int {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw ExtractError.noVideo }

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true   // respect portrait/landscape rotation
        gen.maximumSize = CGSize(width: maxEdge, height: maxEdge)
        gen.requestedTimeToleranceBefore = CMTime(seconds: interval / 2, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: interval / 2, preferredTimescale: 600)

        var times: [CMTime] = []
        var t = 0.0
        while t < duration {
            times.append(CMTime(seconds: t, preferredTimescale: 600))
            t += interval
        }
        if times.isEmpty { throw ExtractError.noFrames }

        var written = 0
        var lastSignature: UInt64? = nil
        let total = Double(times.count)
        var done = 0.0

        for await result in gen.images(for: times) {
            done += 1
            progress(done / total)
            guard case .success(_, let cg, _) = result else { continue }
            let img = UIImage(cgImage: cg)
            // Skip near-duplicate frames (camera paused).
            let sig = signature(of: cg)
            if let last = lastSignature, hamming(last, sig) <= 2 { continue }
            lastSignature = sig
            guard let data = img.jpegData(compressionQuality: 0.82) else { continue }
            let url = folder.appendingPathComponent(String(format: "f%04d.jpg", written))
            try data.write(to: url, options: .atomic)
            written += 1
        }
        if written == 0 { throw ExtractError.noFrames }
        return written
    }

    // MARK: - 8x8 average-hash for duplicate detection

    private static func signature(of cg: CGImage) -> UInt64 {
        let size = 8
        var pixels = [UInt8](repeating: 0, count: size * size)
        guard let ctx = CGContext(data: &pixels, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
        let avg = pixels.reduce(0) { $0 + Int($1) } / pixels.count
        var bits: UInt64 = 0
        for (i, p) in pixels.enumerated() where Int(p) >= avg { bits |= (1 << UInt64(i)) }
        return bits
    }

    private static func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }
}
