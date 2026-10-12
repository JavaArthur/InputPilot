import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = output.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let p = CGFloat(pixels)
        NSColor(calibratedRed: 0.08, green: 0.47, blue: 0.44, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.08, y: p * 0.08, width: p * 0.84, height: p * 0.84),
                     xRadius: p * 0.19, yRadius: p * 0.19).fill()
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        ("A" as NSString).draw(in: NSRect(x: 0, y: p * 0.27, width: p, height: p * 0.60),
                              withAttributes: [.font: NSFont.systemFont(ofSize: p * 0.52, weight: .semibold),
                                               .foregroundColor: NSColor.white, .paragraphStyle: style])
        NSColor.white.withAlphaComponent(0.85).setStroke()
        let path = NSBezierPath()
        path.lineWidth = max(1, p * 0.035)
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: p * 0.30, y: p * 0.24))
        path.line(to: NSPoint(x: p * 0.70, y: p * 0.24))
        path.line(to: NSPoint(x: p * 0.62, y: p * 0.31))
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
try FileManager.default.removeItem(at: iconset)
