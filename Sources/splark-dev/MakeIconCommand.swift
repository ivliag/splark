import AppKit
import SplarkKit

/// Renders the app icon at every size macOS asks for and packs them into an .icns (spec §12).
func makeIconCommand() throws {
    guard args.count >= 2 else { fail("usage: splark-dev make-icon OUT.icns") }
    let out = URL(fileURLWithPath: args[1])
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Splark-\(UUID().uuidString).iconset")
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: iconset) }
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            guard let png = NSBitmapImageRep(cgImage: AppIconArt.cgImage(size: points * scale)).representation(using: .png, properties: [:]) else {
                fail("couldn't encode \(name)")
            }
            try png.write(to: iconset.appendingPathComponent(name))
        }
    }
    try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    _ = try ProcessRunner(timeout: 30).run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", out.path])
    guard FileManager.default.fileExists(atPath: out.path) else { fail("iconutil didn't write \(out.path)") }
    print(out.path)
}
