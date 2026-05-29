#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

struct AppIconSpec {
    let pointSize: String
    let scale: String
    let pixels: Int
    let filename: String
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let fileManager = FileManager.default
let appRoot = root.appendingPathComponent("MenuBarMemo", isDirectory: true)
let appIconDir = appRoot.appendingPathComponent("Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let statusIconDir = appRoot.appendingPathComponent("Assets.xcassets/StatusBarIcon.imageset", isDirectory: true)
let sourceDir = root.appendingPathComponent("IconSource", isDirectory: true)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard fileManager.fileExists(atPath: root.appendingPathComponent("MenuBarMemo.xcodeproj").path),
      fileManager.fileExists(atPath: appRoot.appendingPathComponent("Assets.xcassets").path) else {
    fail("Run Scripts/generate_icon_assets.swift from the repository root containing MenuBarMemo.xcodeproj and MenuBarMemo/Assets.xcassets.")
}

let appIconSpecs = [
    AppIconSpec(pointSize: "16x16", scale: "1x", pixels: 16, filename: "AppIcon-16x16@1x.png"),
    AppIconSpec(pointSize: "16x16", scale: "2x", pixels: 32, filename: "AppIcon-16x16@2x.png"),
    AppIconSpec(pointSize: "32x32", scale: "1x", pixels: 32, filename: "AppIcon-32x32@1x.png"),
    AppIconSpec(pointSize: "32x32", scale: "2x", pixels: 64, filename: "AppIcon-32x32@2x.png"),
    AppIconSpec(pointSize: "128x128", scale: "1x", pixels: 128, filename: "AppIcon-128x128@1x.png"),
    AppIconSpec(pointSize: "128x128", scale: "2x", pixels: 256, filename: "AppIcon-128x128@2x.png"),
    AppIconSpec(pointSize: "256x256", scale: "1x", pixels: 256, filename: "AppIcon-256x256@1x.png"),
    AppIconSpec(pointSize: "256x256", scale: "2x", pixels: 512, filename: "AppIcon-256x256@2x.png"),
    AppIconSpec(pointSize: "512x512", scale: "1x", pixels: 512, filename: "AppIcon-512x512@1x.png"),
    AppIconSpec(pointSize: "512x512", scale: "2x", pixels: 1024, filename: "AppIcon-512x512@2x.png")
]

func rgba(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha).cgColor
}

func fillRounded(_ context: CGContext, rect: CGRect, radius: CGFloat, color: CGColor) {
    context.setFillColor(color)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}

func strokeRounded(_ context: CGContext, rect: CGRect, radius: CGFloat, color: CGColor, lineWidth: CGFloat) {
    context.setStrokeColor(color)
    context.setLineWidth(lineWidth)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.strokePath()
}

func drawGradient(_ context: CGContext, colors: [CGColor], locations: [CGFloat], start: CGPoint, end: CGPoint) {
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: locations
    ) else {
        fatalError("Could not create gradient")
    }
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
}

func drawTopLeftBitmap(pixels: Int, designSize: CGFloat, draw: (CGContext) -> Void) -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create bitmap at \(pixels)x\(pixels)")
    }

    bitmap.size = NSSize(width: pixels, height: pixels)
    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create graphics context")
    }

    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.current = previousContext }

    let context = graphicsContext.cgContext
    let pixelBounds = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    context.clear(pixelBounds)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: CGFloat(pixels) / designSize, y: -CGFloat(pixels) / designSize)
    draw(context)

    return bitmap
}

func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG for \(url.path)")
    }
    try png.write(to: url)
}

func writeJSON(_ object: [String: Any], to url: URL) throws {
    let jsonOptions: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
    var data = try JSONSerialization.data(withJSONObject: object, options: jsonOptions)
    data.append(Data("\n".utf8))
    try data.write(to: url)
}

func drawRotated(context: CGContext, center: CGPoint, degrees: CGFloat, draw: () -> Void) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: degrees * .pi / 180)
    draw()
    context.restoreGState()
}

func drawMarkdownHash(_ context: CGContext) {
    context.saveGState()
    context.translateBy(x: 318, y: 474)
    context.rotate(by: -7 * .pi / 180)
    let color = rgba(31, 41, 55, 0.22)
    fillRounded(context, rect: CGRect(x: 30, y: 0, width: 24, height: 154), radius: 12, color: color)
    fillRounded(context, rect: CGRect(x: 92, y: 0, width: 24, height: 154), radius: 12, color: color)
    fillRounded(context, rect: CGRect(x: 0, y: 46, width: 146, height: 24), radius: 12, color: color)
    fillRounded(context, rect: CGRect(x: 0, y: 96, width: 146, height: 24), radius: 12, color: color)
    context.restoreGState()
}

func drawAppIcon(pixels: Int) -> NSBitmapImageRep {
    drawTopLeftBitmap(pixels: pixels, designSize: 1024) { context in
        let bounds = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        let outer = CGPath(roundedRect: bounds, cornerWidth: 226, cornerHeight: 226, transform: nil)

        context.saveGState()
        context.addPath(outer)
        context.clip()
        drawGradient(
            context,
            colors: [rgba(230, 237, 246), rgba(250, 252, 252), rgba(221, 239, 229)],
            locations: [0, 0.48, 1],
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 1024, y: 1024)
        )

        context.setFillColor(rgba(255, 255, 255, 0.30))
        context.fillEllipse(in: CGRect(x: 110, y: 76, width: 380, height: 312))
        context.setFillColor(rgba(32, 46, 60, 0.045))
        context.fillEllipse(in: CGRect(x: 518, y: 650, width: 565, height: 420))
        context.restoreGState()

        let menuRect = CGRect(x: 164, y: 166, width: 696, height: 136)
        context.setShadow(offset: CGSize(width: 0, height: 12), blur: 22, color: rgba(15, 23, 42, 0.13))
        fillRounded(context, rect: menuRect, radius: 68, color: rgba(31, 41, 55, 0.92))
        context.setShadow(offset: .zero, blur: 0, color: nil)

        context.setFillColor(rgba(255, 255, 255, 0.72))
        context.fillEllipse(in: CGRect(x: 252, y: 212, width: 34, height: 34))
        context.setFillColor(rgba(255, 255, 255, 0.40))
        context.fillEllipse(in: CGRect(x: 320, y: 212, width: 34, height: 34))

        let noteRect = CGRect(x: 246, y: 386, width: 500, height: 440)
        context.setShadow(offset: CGSize(width: 0, height: 24), blur: 42, color: rgba(15, 23, 42, 0.16))
        fillRounded(context, rect: noteRect, radius: 108, color: rgba(255, 255, 255, 0.92))
        context.setShadow(offset: .zero, blur: 0, color: nil)
        strokeRounded(context, rect: noteRect.insetBy(dx: 3, dy: 3), radius: 105, color: rgba(31, 41, 55, 0.10), lineWidth: 6)

        drawMarkdownHash(context)

        fillRounded(context, rect: CGRect(x: 414, y: 540, width: 220, height: 24), radius: 12, color: rgba(31, 41, 55, 0.19))
        fillRounded(context, rect: CGRect(x: 382, y: 636, width: 206, height: 24), radius: 12, color: rgba(31, 41, 55, 0.15))

        drawRotated(context: context, center: CGPoint(x: 704, y: 612), degrees: -32) {
            let penBody = CGRect(x: -210, y: -34, width: 420, height: 68)
            context.setShadow(offset: CGSize(width: 0, height: 18), blur: 28, color: rgba(15, 23, 42, 0.20))
            fillRounded(context, rect: penBody, radius: 34, color: rgba(38, 50, 65))
            context.setShadow(offset: .zero, blur: 0, color: nil)
            fillRounded(context, rect: CGRect(x: 54, y: -34, width: 156, height: 68), radius: 34, color: rgba(100, 116, 139))

            let tip = CGMutablePath()
            tip.move(to: CGPoint(x: -280, y: 0))
            tip.addLine(to: CGPoint(x: -210, y: -31))
            tip.addLine(to: CGPoint(x: -210, y: 31))
            tip.closeSubpath()
            context.addPath(tip)
            context.setFillColor(rgba(255, 248, 236))
            context.fillPath()

            let point = CGMutablePath()
            point.move(to: CGPoint(x: -280, y: 0))
            point.addLine(to: CGPoint(x: -250, y: -13))
            point.addLine(to: CGPoint(x: -250, y: 13))
            point.closeSubpath()
            context.addPath(point)
            context.setFillColor(rgba(31, 41, 55))
            context.fillPath()
        }

        let stroke = CGPath(
            roundedRect: CGRect(x: 382, y: 698, width: 250, height: 28),
            cornerWidth: 14,
            cornerHeight: 14,
            transform: nil
        )
        context.saveGState()
        context.addPath(stroke)
        context.clip()
        drawGradient(
            context,
            colors: [rgba(59, 130, 246), rgba(79, 159, 122)],
            locations: [0, 1],
            start: CGPoint(x: 382, y: 712),
            end: CGPoint(x: 632, y: 712)
        )
        context.restoreGState()

        strokeRounded(context, rect: bounds.insetBy(dx: 5, dy: 5), radius: 221, color: rgba(255, 255, 255, 0.42), lineWidth: 10)
    }
}

func drawStatusIcon(pixels: Int) -> NSBitmapImageRep {
    drawTopLeftBitmap(pixels: pixels, designSize: 18) { context in
        let ink = rgba(0, 0, 0)

        fillRounded(context, rect: CGRect(x: 2.5, y: 1.4, width: 13.0, height: 2.8), radius: 1.4, color: ink)
        fillRounded(context, rect: CGRect(x: 3.7, y: 5.2, width: 10.9, height: 10.4), radius: 2.2, color: ink)

        drawRotated(context: context, center: CGPoint(x: 13.0, y: 12.0), degrees: -34) {
            fillRounded(context, rect: CGRect(x: -6.4, y: -1.3, width: 12.8, height: 2.6), radius: 1.3, color: ink)
            let tip = CGMutablePath()
            tip.move(to: CGPoint(x: -8.5, y: 0))
            tip.addLine(to: CGPoint(x: -6.4, y: -1.2))
            tip.addLine(to: CGPoint(x: -6.4, y: 1.2))
            tip.closeSubpath()
            context.addPath(tip)
            context.setFillColor(ink)
            context.fillPath()
        }
    }
}

let appSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#e6edf6"/>
      <stop offset="0.48" stop-color="#fafcfc"/>
      <stop offset="1" stop-color="#ddefe5"/>
    </linearGradient>
    <linearGradient id="ink" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#3b82f6"/>
      <stop offset="1" stop-color="#4f9f7a"/>
    </linearGradient>
    <filter id="softShadow" x="-20%" y="-20%" width="140%" height="150%">
      <feDropShadow dx="0" dy="24" stdDeviation="22" flood-color="#0f172a" flood-opacity="0.16"/>
    </filter>
  </defs>
  <rect width="1024" height="1024" rx="226" fill="url(#bg)"/>
  <ellipse cx="300" cy="232" rx="190" ry="156" fill="#fff" opacity="0.30"/>
  <ellipse cx="800" cy="860" rx="282" ry="210" fill="#202e3c" opacity="0.045"/>
  <rect x="164" y="166" width="696" height="136" rx="68" fill="#1f2937" opacity="0.92"/>
  <circle cx="269" cy="229" r="17" fill="#fff" opacity="0.72"/>
  <circle cx="337" cy="229" r="17" fill="#fff" opacity="0.40"/>
  <rect x="246" y="386" width="500" height="440" rx="108" fill="#fff" opacity="0.92" filter="url(#softShadow)"/>
  <rect x="249" y="389" width="494" height="434" rx="105" fill="none" stroke="#1f2937" stroke-opacity="0.10" stroke-width="6"/>
  <g transform="translate(318 474) rotate(-7)" fill="#1f2937" opacity="0.22">
    <rect x="30" y="0" width="24" height="154" rx="12"/>
    <rect x="92" y="0" width="24" height="154" rx="12"/>
    <rect x="0" y="46" width="146" height="24" rx="12"/>
    <rect x="0" y="96" width="146" height="24" rx="12"/>
  </g>
  <rect x="414" y="540" width="220" height="24" rx="12" fill="#1f2937" opacity="0.19"/>
  <rect x="382" y="636" width="206" height="24" rx="12" fill="#1f2937" opacity="0.15"/>
  <rect x="382" y="698" width="250" height="28" rx="14" fill="url(#ink)"/>
  <g transform="translate(704 612) rotate(-32)">
    <polygon points="-280,0 -210,-31 -210,31" fill="#fff8ec"/>
    <polygon points="-280,0 -250,-13 -250,13" fill="#1f2937"/>
    <rect x="-210" y="-34" width="420" height="68" rx="34" fill="#263241"/>
    <rect x="54" y="-34" width="156" height="68" rx="34" fill="#64748b"/>
  </g>
  <rect x="5" y="5" width="1014" height="1014" rx="221" fill="none" stroke="#fff" stroke-opacity="0.42" stroke-width="10"/>
</svg>
"""

let statusSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18">
  <rect x="2.5" y="1.4" width="13" height="2.8" rx="1.4" fill="#000"/>
  <rect x="3.7" y="5.2" width="10.9" height="10.4" rx="2.2" fill="#000"/>
  <g transform="translate(13 12) rotate(-34)">
    <polygon points="-8.5,0 -6.4,-1.2 -6.4,1.2" fill="#000"/>
    <rect x="-6.4" y="-1.3" width="12.8" height="2.6" rx="1.3" fill="#000"/>
  </g>
</svg>
"""

try fileManager.createDirectory(at: appIconDir, withIntermediateDirectories: true)
try fileManager.createDirectory(at: statusIconDir, withIntermediateDirectories: true)
try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)

try appSVG.write(to: sourceDir.appendingPathComponent("MenuBarMemoAppIcon.svg"), atomically: true, encoding: .utf8)
try statusSVG.write(to: sourceDir.appendingPathComponent("MenuBarMemoStatusBarIcon.svg"), atomically: true, encoding: .utf8)

for spec in appIconSpecs {
    try writePNG(drawAppIcon(pixels: spec.pixels), to: appIconDir.appendingPathComponent(spec.filename))
}
try writePNG(drawStatusIcon(pixels: 18), to: statusIconDir.appendingPathComponent("StatusBarIcon.png"))
try writePNG(drawStatusIcon(pixels: 36), to: statusIconDir.appendingPathComponent("StatusBarIcon@2x.png"))

let appIconContents: [String: Any] = [
    "images": appIconSpecs.map {
        [
            "idiom": "mac",
            "size": $0.pointSize,
            "scale": $0.scale,
            "filename": $0.filename
        ]
    },
    "info": [
        "author": "xcode",
        "version": 1
    ]
]

let statusContents: [String: Any] = [
    "images": [
        [
            "idiom": "mac",
            "scale": "1x",
            "filename": "StatusBarIcon.png"
        ],
        [
            "idiom": "mac",
            "scale": "2x",
            "filename": "StatusBarIcon@2x.png"
        ]
    ],
    "info": [
        "author": "xcode",
        "version": 1
    ],
    "properties": [
        "template-rendering-intent": "template"
    ]
]

try writeJSON(appIconContents, to: appIconDir.appendingPathComponent("Contents.json"))
try writeJSON(statusContents, to: statusIconDir.appendingPathComponent("Contents.json"))

print("Generated MenuBarMemo icon assets")
