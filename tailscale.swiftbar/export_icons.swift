import AppKit
import Foundation

let bundle = Bundle(path: "/Applications/Tailscale.app")!
let outputDir = URL(fileURLWithPath: "/Users/qinyuhang/projects/assppweb-compose/swift-bar-tailscale/tailscale-icons", isDirectory: true)
let fm = FileManager.default
try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

let names = [
    "ExitNodeIcon",
    "HighPriorityIcon",
    "StatusBarIcon",
    "StatusBarIconDefaultRouterOffline",
    "StatusBarIconDefaultRouterOnline",
    "StatusBarIconDimmed",
    "StatusBarIconDot1",
    "StatusBarIconDot2",
    "StatusBarIconDot3",
    "StatusBarIconDot4",
    "StatusBarIconDot5",
    "StatusBarIconDot6",
    "StatusBarIconDot7",
    "StatusBarIconDot8",
    "StatusBarIconDot9",
    "StatusBarIconDot10",
    "StatusBarIconDot11",
    "StatusBarIconDot12",
    "StatusBarIconDot13",
    "StatusBarIconDot14",
    "StatusBarIconDot15",
    "StatusBarIconDot16",
    "StatusBarIconErrorOffline",
    "StatusBarIconErrorOnline"
]

func writePNG(image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to rasterize image"])
    }
    try png.write(to: url)
}

var manifest: [[String: String]] = []

for name in names {
    guard let image = bundle.image(forResource: name) else {
        fputs("missing: \(name)\n", stderr)
        continue
    }

    let fileURL = outputDir.appendingPathComponent("\(name).png")
    do {
        try writePNG(image: image, to: fileURL)
        manifest.append([
            "name": name,
            "file": "\(name).png",
            "size": "\(Int(image.size.width))x\(Int(image.size.height))"
        ])
        print("exported \(name)")
    } catch {
        fputs("failed: \(name) - \(error)\n", stderr)
    }
}

let manifestURL = outputDir.appendingPathComponent("manifest.json")
let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try manifestData.write(to: manifestURL)
print("manifest written")
