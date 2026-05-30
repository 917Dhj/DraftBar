# DraftBar Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate and wire a first-version DraftBar app icon plus matching menu bar template icon from the approved design spec.

**Architecture:** Keep icon production deterministic by adding checked-in Swift scripts that generate PNG assets from CoreGraphics drawing commands. Store editable source SVGs under `IconSource/`, generated runtime assets under `Assets.xcassets/`, and keep app code changes limited to status item image lookup plus the drag seed icon.

**Tech Stack:** Swift script with AppKit/CoreGraphics, Xcode asset catalogs, SwiftUI/AppKit, `xcodebuild`.

---

## File Structure

- Create: `Scripts/validate_icon_assets.swift`
  - Validates generated PNG existence, pixel dimensions, app icon JSON filenames, and status icon template metadata.
- Create: `Scripts/generate_icon_assets.swift`
  - Generates editable SVG source files and raster PNG assets for app icon and status bar icon.
- Create: `IconSource/DraftBarAppIcon.svg`
  - Editable vector source for the App icon.
- Create: `IconSource/DraftBarStatusBarIcon.svg`
  - Editable vector source for the template status icon.
- Modify: `Assets.xcassets/AppIcon.appiconset/Contents.json`
  - Adds filenames for all macOS app icon slots.
- Create: `Assets.xcassets/AppIcon.appiconset/*.png`
  - Generated PNGs for all required macOS app icon scales.
- Create: `Assets.xcassets/StatusBarIcon.imageset/Contents.json`
  - Defines a template-rendered macOS imageset.
- Create: `Assets.xcassets/StatusBarIcon.imageset/StatusBarIcon.png`
  - 18x18 template PNG for menu bar 1x.
- Create: `Assets.xcassets/StatusBarIcon.imageset/StatusBarIcon@2x.png`
  - 36x36 template PNG for menu bar 2x.
- Modify: `DraftBarApp.swift`
  - Loads `StatusBarIcon` from the asset catalog, keeps `square.and.pencil` fallback.
- Modify: `ContentView.swift`
  - Uses the same `StatusBarIcon` for the drag seed preview instead of the SF Symbol.

## Task 1: Add Icon Asset Validator

**Files:**
- Create: `Scripts/validate_icon_assets.swift`

- [ ] **Step 1: Create the scripts directory**

Run:

```bash
mkdir -p Scripts
```

Expected: `Scripts/` exists.

- [ ] **Step 2: Add the validation script**

Create `Scripts/validate_icon_assets.swift` with this content:

```swift
#!/usr/bin/env swift
import AppKit
import Foundation

struct ExpectedPNG {
    let path: String
    let width: Int
    let height: Int
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let fileManager = FileManager.default

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func requireFile(_ relativePath: String) -> URL {
    let url = root.appendingPathComponent(relativePath)
    guard fileManager.fileExists(atPath: url.path) else {
        fail("Missing file: \(relativePath)")
    }
    return url
}

func dimensions(of url: URL) -> (Int, Int) {
    guard let image = NSImage(contentsOf: url),
          let representation = image.representations.first else {
        fail("Could not read PNG: \(url.path)")
    }
    return (representation.pixelsWide, representation.pixelsHigh)
}

func jsonObject(_ relativePath: String) -> [String: Any] {
    let url = requireFile(relativePath)
    do {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fail("JSON root is not an object: \(relativePath)")
        }
        return object
    } catch {
        fail("Could not parse JSON at \(relativePath): \(error)")
    }
}

let expectedPNGs = [
    ExpectedPNG(path: "Assets.xcassets/AppIcon.appiconset/AppIcon-16x16@1x.png", width: 16, height: 16),
    ExpectedPNG(path: "Assets.xcassets/AppIcon.appiconset/AppIcon-16x16@2x.png", width: 32, height: 32),
    ExpectedPNG(path: "Assets.xcassets/AppIcon.appiconset/AppIcon-32x32@1x.png", width: 32, height: 32),
    ExpectedPNG(path: "Assets.xcassets/AppIcon.appiconset/AppIcon-32x32@2x.png", width: 64, height: 64),
    ExpectedPNG(path: "Assets.xcassets/AppIcon.appiconset/AppIcon-128x128@1x.png", width: 128, height: 128),
    ExpectedPNG(path: "Assets.xcassets/AppIcon.appiconset/AppIcon-128x128@2x.png", width: 256, height: 256),
    ExpectedPNG(path: "Assets.xcassets/AppIcon.appiconset/AppIcon-256x256@1x.png", width: 256, height: 256),
    ExpectedPNG(path: "Assets.xcassets/AppIcon.appiconset/AppIcon-256x256@2x.png", width: 512, height: 512),
    ExpectedPNG(path: "Assets.xcassets/AppIcon.appiconset/AppIcon-512x512@1x.png", width: 512, height: 512),
    ExpectedPNG(path: "Assets.xcassets/AppIcon.appiconset/AppIcon-512x512@2x.png", width: 1024, height: 1024),
    ExpectedPNG(path: "Assets.xcassets/StatusBarIcon.imageset/StatusBarIcon.png", width: 18, height: 18),
    ExpectedPNG(path: "Assets.xcassets/StatusBarIcon.imageset/StatusBarIcon@2x.png", width: 36, height: 36)
]

for expected in expectedPNGs {
    let url = requireFile(expected.path)
    let actual = dimensions(of: url)
    guard actual.0 == expected.width && actual.1 == expected.height else {
        fail("Wrong dimensions for \(expected.path): expected \(expected.width)x\(expected.height), got \(actual.0)x\(actual.1)")
    }
}

let appIconJSON = jsonObject("Assets.xcassets/AppIcon.appiconset/Contents.json")
guard let appImages = appIconJSON["images"] as? [[String: Any]] else {
    fail("AppIcon Contents.json has no images array")
}

let expectedAppFilenames = Set(expectedPNGs.filter { $0.path.contains("AppIcon.appiconset") }.map {
    URL(fileURLWithPath: $0.path).lastPathComponent
})
let actualAppFilenames = Set(appImages.compactMap { $0["filename"] as? String })
guard actualAppFilenames == expectedAppFilenames else {
    fail("AppIcon filenames mismatch. Expected \(expectedAppFilenames.sorted()), got \(actualAppFilenames.sorted())")
}

let statusJSON = jsonObject("Assets.xcassets/StatusBarIcon.imageset/Contents.json")
guard let statusImages = statusJSON["images"] as? [[String: Any]] else {
    fail("StatusBarIcon Contents.json has no images array")
}
let statusFilenames = Set(statusImages.compactMap { $0["filename"] as? String })
guard statusFilenames == ["StatusBarIcon.png", "StatusBarIcon@2x.png"] else {
    fail("StatusBarIcon filenames mismatch: \(statusFilenames.sorted())")
}
let properties = statusJSON["properties"] as? [String: Any]
guard properties?["template-rendering-intent"] as? String == "template" else {
    fail("StatusBarIcon.imageset must set template-rendering-intent to template")
}

_ = requireFile("IconSource/DraftBarAppIcon.svg")
_ = requireFile("IconSource/DraftBarStatusBarIcon.svg")

print("Icon asset validation passed")
```

- [ ] **Step 3: Make the validator executable**

Run:

```bash
chmod +x Scripts/validate_icon_assets.swift
```

Expected: command exits 0.

- [ ] **Step 4: Run the validator and verify it fails before assets exist**

Run:

```bash
Scripts/validate_icon_assets.swift
```

Expected: FAIL with `Missing file: Assets.xcassets/AppIcon.appiconset/AppIcon-16x16@1x.png`.

- [ ] **Step 5: Commit the validator**

Run:

```bash
git add Scripts/validate_icon_assets.swift
git commit -m "test: add icon asset validator"
```

Expected: commit succeeds.

## Task 2: Generate App Icon And Status Icon Assets

**Files:**
- Create: `Scripts/generate_icon_assets.swift`
- Create: `IconSource/DraftBarAppIcon.svg`
- Create: `IconSource/DraftBarStatusBarIcon.svg`
- Modify: `Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `Assets.xcassets/AppIcon.appiconset/*.png`
- Create: `Assets.xcassets/StatusBarIcon.imageset/Contents.json`
- Create: `Assets.xcassets/StatusBarIcon.imageset/StatusBarIcon.png`
- Create: `Assets.xcassets/StatusBarIcon.imageset/StatusBarIcon@2x.png`

- [ ] **Step 1: Add the deterministic generator script**

Create `Scripts/generate_icon_assets.swift` with this content:

```swift
#!/usr/bin/env swift
import AppKit
import Foundation

struct AppIconSpec {
    let pointSize: String
    let scale: String
    let pixels: Int
    let filename: String
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let fileManager = FileManager.default
let appIconDir = root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let statusIconDir = root.appendingPathComponent("Assets.xcassets/StatusBarIcon.imageset", isDirectory: true)
let sourceDir = root.appendingPathComponent("IconSource", isDirectory: true)

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
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: locations
    )!
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
}

func drawTopLeftImage(pixels: Int, draw: (CGContext) -> Void) -> NSImage {
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        fatalError("Missing graphics context")
    }
    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: CGFloat(pixels) / 1024, y: -CGFloat(pixels) / 1024)
    draw(context)
    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG for \(url.path)")
    }
    try png.write(to: url)
}

func drawRotated(context: CGContext, center: CGPoint, degrees: CGFloat, draw: () -> Void) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: degrees * .pi / 180)
    draw()
    context.restoreGState()
}

func drawAppIcon(pixels: Int) -> NSImage {
    drawTopLeftImage(pixels: pixels) { context in
        let bounds = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        let outer = CGPath(roundedRect: bounds, cornerWidth: 226, cornerHeight: 226, transform: nil)

        context.saveGState()
        context.addPath(outer)
        context.clip()
        drawGradient(
            context,
            colors: [rgba(231, 238, 246), rgba(251, 252, 253), rgba(220, 238, 229)],
            locations: [0, 0.48, 1],
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 1024, y: 1024)
        )

        context.setFillColor(rgba(255, 255, 255, 0.32))
        context.fillEllipse(in: CGRect(x: 115, y: 72, width: 360, height: 300))
        context.setFillColor(rgba(38, 50, 65, 0.05))
        context.fillEllipse(in: CGRect(x: 520, y: 670, width: 560, height: 430))
        context.restoreGState()

        let menuRect = CGRect(x: 164, y: 166, width: 696, height: 136)
        context.setShadow(offset: CGSize(width: 0, height: 12), blur: 20, color: rgba(15, 23, 42, 0.12))
        fillRounded(context, rect: menuRect, radius: 68, color: rgba(31, 41, 55, 0.91))
        context.setShadow(offset: .zero, blur: 0, color: nil)

        context.setFillColor(rgba(255, 255, 255, 0.72))
        context.fillEllipse(in: CGRect(x: 252, y: 212, width: 34, height: 34))
        context.setFillColor(rgba(255, 255, 255, 0.40))
        context.fillEllipse(in: CGRect(x: 320, y: 212, width: 34, height: 34))

        let noteRect = CGRect(x: 246, y: 386, width: 500, height: 440)
        context.setShadow(offset: CGSize(width: 0, height: 24), blur: 40, color: rgba(15, 23, 42, 0.16))
        fillRounded(context, rect: noteRect, radius: 108, color: rgba(255, 255, 255, 0.90))
        context.setShadow(offset: .zero, blur: 0, color: nil)
        strokeRounded(context, rect: noteRect.insetBy(dx: 2, dy: 2), radius: 106, color: rgba(31, 41, 55, 0.10), lineWidth: 6)

        let paragraphColor = rgba(31, 41, 55, 0.20)
        fillRounded(context, rect: CGRect(x: 368, y: 540, width: 258, height: 24), radius: 12, color: paragraphColor)
        fillRounded(context, rect: CGRect(x: 368, y: 636, width: 206, height: 24), radius: 12, color: rgba(31, 41, 55, 0.16))

        let hash = NSString(string: "#")
        hash.draw(
            at: CGPoint(x: 330, y: 470),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 150, weight: .black),
                .foregroundColor: NSColor(calibratedRed: 31 / 255, green: 41 / 255, blue: 55 / 255, alpha: 0.24)
            ]
        )

        drawRotated(context: context, center: CGPoint(x: 704, y: 612), degrees: -32) {
            let penBody = CGRect(x: -210, y: -34, width: 420, height: 68)
            context.setShadow(offset: CGSize(width: 0, height: 18), blur: 28, color: rgba(15, 23, 42, 0.20))
            fillRounded(context, rect: penBody, radius: 34, color: rgba(38, 50, 65, 1))
            context.setShadow(offset: .zero, blur: 0, color: nil)
            fillRounded(context, rect: CGRect(x: 54, y: -34, width: 156, height: 68), radius: 34, color: rgba(100, 116, 139, 1))

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

        let stroke = CGPath(roundedRect: CGRect(x: 378, y: 698, width: 250, height: 28), cornerWidth: 14, cornerHeight: 14, transform: nil)
        context.saveGState()
        context.addPath(stroke)
        context.clip()
        drawGradient(
            context,
            colors: [rgba(59, 130, 246), rgba(79, 159, 122)],
            locations: [0, 1],
            start: CGPoint(x: 378, y: 720),
            end: CGPoint(x: 630, y: 672)
        )
        context.restoreGState()

        strokeRounded(context, rect: bounds.insetBy(dx: 5, dy: 5), radius: 221, color: rgba(255, 255, 255, 0.40), lineWidth: 10)
    }
}

func drawStatusIcon(pixels: Int) -> NSImage {
    drawTopLeftImage(pixels: pixels) { context in
        context.scaleBy(x: 1024 / 18, y: 1024 / 18)
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
      <stop offset="0" stop-color="#e7eef6"/>
      <stop offset="0.48" stop-color="#fbfcfd"/>
      <stop offset="1" stop-color="#dceee5"/>
    </linearGradient>
    <linearGradient id="ink" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#3b82f6"/>
      <stop offset="1" stop-color="#4f9f7a"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" rx="226" fill="url(#bg)"/>
  <rect x="164" y="166" width="696" height="136" rx="68" fill="#1f2937" opacity="0.91"/>
  <circle cx="269" cy="229" r="17" fill="#fff" opacity="0.72"/>
  <circle cx="337" cy="229" r="17" fill="#fff" opacity="0.40"/>
  <rect x="246" y="386" width="500" height="440" rx="108" fill="#fff" opacity="0.90"/>
  <rect x="368" y="540" width="258" height="24" rx="12" fill="#1f2937" opacity="0.20"/>
  <rect x="368" y="636" width="206" height="24" rx="12" fill="#1f2937" opacity="0.16"/>
  <text x="330" y="610" font-size="150" font-family="SF Mono, Menlo, monospace" font-weight="900" fill="#1f2937" opacity="0.24">#</text>
  <rect x="378" y="698" width="250" height="28" rx="14" fill="url(#ink)" transform="rotate(-12 503 712)"/>
  <g transform="translate(704 612) rotate(-32)">
    <polygon points="-280,0 -210,-31 -210,31" fill="#fff8ec"/>
    <polygon points="-280,0 -250,-13 -250,13" fill="#1f2937"/>
    <rect x="-210" y="-34" width="420" height="68" rx="34" fill="#263241"/>
    <rect x="54" y="-34" width="156" height="68" rx="34" fill="#64748b"/>
  </g>
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

try appSVG.write(to: sourceDir.appendingPathComponent("DraftBarAppIcon.svg"), atomically: true, encoding: .utf8)
try statusSVG.write(to: sourceDir.appendingPathComponent("DraftBarStatusBarIcon.svg"), atomically: true, encoding: .utf8)

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

let jsonOptions: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
try JSONSerialization.data(withJSONObject: appIconContents, options: jsonOptions)
    .write(to: appIconDir.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: statusContents, options: jsonOptions)
    .write(to: statusIconDir.appendingPathComponent("Contents.json"))

print("Generated DraftBar icon assets")
```

- [ ] **Step 2: Make the generator executable**

Run:

```bash
chmod +x Scripts/generate_icon_assets.swift
```

Expected: command exits 0.

- [ ] **Step 3: Run the generator**

Run:

```bash
Scripts/generate_icon_assets.swift
```

Expected: prints `Generated DraftBar icon assets`.

- [ ] **Step 4: Run the validator and verify it passes**

Run:

```bash
Scripts/validate_icon_assets.swift
```

Expected: prints `Icon asset validation passed`.

- [ ] **Step 5: Inspect generated file list**

Run:

```bash
find IconSource Assets.xcassets/AppIcon.appiconset Assets.xcassets/StatusBarIcon.imageset -maxdepth 1 -type f | sort
```

Expected: output includes `IconSource/DraftBarAppIcon.svg`, `IconSource/DraftBarStatusBarIcon.svg`, ten `AppIcon-*.png` files, both status PNGs, and both `Contents.json` files.

- [ ] **Step 6: Commit generated assets and scripts**

Run:

```bash
git add Scripts/generate_icon_assets.swift IconSource Assets.xcassets/AppIcon.appiconset Assets.xcassets/StatusBarIcon.imageset
git commit -m "design: generate DraftBar icon assets"
```

Expected: commit succeeds.

## Task 3: Wire Custom Status Icon In App Code

**Files:**
- Modify: `DraftBarApp.swift`
- Modify: `ContentView.swift`

- [ ] **Step 1: Replace the status item image lookup**

In `DraftBarApp.swift`, replace the image setup inside `configureStatusItem()` with:

```swift
        let image = NSImage(named: "StatusBarIcon")
            ?? NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "DraftBar")
        image?.isTemplate = true
        button.image = image
```

Expected: the rest of `configureStatusItem()` stays unchanged.

- [ ] **Step 2: Replace the drag seed icon call site**

In `ContentView.swift`, replace this block inside `FloatingNoteView.body`:

```swift
            Image(systemName: "square.and.pencil")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .opacity(dragSeedOpacity)
                .allowsHitTesting(false)
```

with:

```swift
            dragSeedIcon
                .opacity(dragSeedOpacity)
                .allowsHitTesting(false)
```

- [ ] **Step 3: Add the drag seed icon view**

In `ContentView.swift`, add this computed property inside `FloatingNoteView`, near `noteBackground`:

```swift
    private var dragSeedIcon: some View {
        Image("StatusBarIcon")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 16, height: 16)
            .foregroundStyle(.secondary)
    }
```

Expected: `FloatingNoteView` still compiles, and the drag seed uses the same icon family as the menu bar item.

- [ ] **Step 4: Build the macOS app**

Run:

```bash
xcodebuild -project ../DraftBar.xcodeproj -scheme DraftBar -destination 'platform=macOS' -derivedDataPath /private/tmp/DraftBarDerivedData -clonedSourcePackagesDirPath /private/tmp/DraftBarSourcePackages build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run validator after code changes**

Run:

```bash
Scripts/validate_icon_assets.swift
```

Expected: prints `Icon asset validation passed`.

- [ ] **Step 6: Commit code wiring**

Run:

```bash
git add DraftBarApp.swift ContentView.swift
git commit -m "feat: use custom menu bar icon"
```

Expected: commit succeeds.

## Task 4: Final Visual And Build Verification

**Files:**
- No new files.

- [ ] **Step 1: Confirm the working tree only contains intentional changes**

Run:

```bash
git status --short
```

Expected: no tracked-file changes. `.superpowers/` may remain untracked from the brainstorming visual companion and must not be committed.

- [ ] **Step 2: Confirm AppIcon JSON references all generated PNGs**

Run:

```bash
plutil -lint Assets.xcassets/AppIcon.appiconset/Contents.json Assets.xcassets/StatusBarIcon.imageset/Contents.json
```

Expected: both files print `OK`.

- [ ] **Step 3: Confirm generated PNG dimensions**

Run:

```bash
Scripts/validate_icon_assets.swift
```

Expected: prints `Icon asset validation passed`.

- [ ] **Step 4: Build once more from a clean derived-data path**

Run:

```bash
xcodebuild -project ../DraftBar.xcodeproj -scheme DraftBar -destination 'platform=macOS' -derivedDataPath /private/tmp/DraftBarIconFinalBuild -clonedSourcePackagesDirPath /private/tmp/DraftBarIconSourcePackages build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual visual check**

Open these generated images from Finder or Preview:

```text
Assets.xcassets/AppIcon.appiconset/AppIcon-512x512@2x.png
Assets.xcassets/AppIcon.appiconset/AppIcon-32x32@1x.png
Assets.xcassets/StatusBarIcon.imageset/StatusBarIcon.png
Assets.xcassets/StatusBarIcon.imageset/StatusBarIcon@2x.png
```

Expected:

- 1024px app icon shows menu bar, note sheet, pen, and subtle `#`.
- 32px app icon reads as a writing or memo tool.
- 18px and 36px status icons read as note plus pen.
- Status icons are solid black shapes on transparent background, with no `#`, gradient, or shadow.

- [ ] **Step 6: Record final result**

Run:

```bash
git log --oneline -3
```

Expected: top commits include `feat: use custom menu bar icon`, `design: generate DraftBar icon assets`, and `test: add icon asset validator`.
