import Foundation
import UIKit
import ImageIO

enum SpyderWallpaperPhotoStore {
    private static func directory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = base.appendingPathComponent("SpyderWallpapers", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    static func importPhoto(_ data: Data) throws -> String {
        guard data.count <= 25 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary),
              let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let id = UUID().uuidString
        let url = try directory().appendingPathComponent(id + ".jpg")
        try jpeg.write(to: url, options: [.atomic, .completeFileProtection])
        return id
    }
    static func load(_ id: String) -> UIImage? {
        guard UUID(uuidString: id) != nil, let folder = try? directory() else { return nil }
        return UIImage(contentsOfFile: folder.appendingPathComponent(id + ".jpg").path)
    }
}
