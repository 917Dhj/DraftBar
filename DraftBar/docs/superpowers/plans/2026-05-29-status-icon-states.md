# Status Icon States Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two menu bar icon states: a hidden-state icon with a down chevron and a visible-state icon without the chevron, then switch between them based on whether the floating note panel is visible.

**Architecture:** Keep icon drawing centralized in `Scripts/generate_icon_assets.swift`, and keep validation centralized in `Scripts/validate_icon_assets.swift`. The app loads a hidden-state icon by default, switches to a visible-state icon when the panel is shown or dragged out, and switches back only after the close path actually orders the panel out.

**Tech Stack:** Swift, AppKit `NSStatusItem`, SwiftUI, Xcode asset catalogs, template PNG images.

---

## File Structure

- Modify `Scripts/validate_icon_assets.swift`
  - Validate two status icon assets instead of one.
  - Validate source SVG semantics for hidden and visible states.
  - Validate the app source references the two-state icon API.
- Modify `Scripts/generate_icon_assets.swift`
  - Generate `StatusBarIconHidden.imageset` and `StatusBarIconVisible.imageset`.
  - Generate matching SVG sources in `IconSource/`.
- Delete `DraftBar/Assets.xcassets/StatusBarIcon.imageset/`
  - Replace it with explicit hidden and visible asset names.
- Delete `IconSource/DraftBarStatusBarIcon.svg`
  - Replace it with `DraftBarStatusBarIconHidden.svg` and `DraftBarStatusBarIconVisible.svg`.
- Modify `DraftBar/DraftBarApp.swift`
  - Add a small status icon state enum and helper.
  - Switch icons in show, drag, and close paths.
- Modify `DraftBar/ContentView.swift`
  - Use the hidden-state asset for the drag seed icon.

---

### Task 1: Generate And Validate Two Status Icon Assets

**Files:**
- Modify: `Scripts/validate_icon_assets.swift`
- Modify: `Scripts/generate_icon_assets.swift`
- Delete: `DraftBar/Assets.xcassets/StatusBarIcon.imageset/`
- Delete: `IconSource/DraftBarStatusBarIcon.svg`
- Create: `DraftBar/Assets.xcassets/StatusBarIconHidden.imageset/`
- Create: `DraftBar/Assets.xcassets/StatusBarIconVisible.imageset/`
- Create: `IconSource/DraftBarStatusBarIconHidden.svg`
- Create: `IconSource/DraftBarStatusBarIconVisible.svg`

- [ ] **Step 1: Update the validator to expect two status icon assets**

In `Scripts/validate_icon_assets.swift`, replace the two existing status PNG entries in `expectedPNGs`:

```swift
ExpectedPNG(path: "DraftBar/Assets.xcassets/StatusBarIcon.imageset/StatusBarIcon.png", width: 18, height: 18),
ExpectedPNG(path: "DraftBar/Assets.xcassets/StatusBarIcon.imageset/StatusBarIcon@2x.png", width: 36, height: 36)
```

with:

```swift
ExpectedPNG(path: "DraftBar/Assets.xcassets/StatusBarIconHidden.imageset/StatusBarIconHidden.png", width: 18, height: 18),
ExpectedPNG(path: "DraftBar/Assets.xcassets/StatusBarIconHidden.imageset/StatusBarIconHidden@2x.png", width: 36, height: 36),
ExpectedPNG(path: "DraftBar/Assets.xcassets/StatusBarIconVisible.imageset/StatusBarIconVisible.png", width: 18, height: 18),
ExpectedPNG(path: "DraftBar/Assets.xcassets/StatusBarIconVisible.imageset/StatusBarIconVisible@2x.png", width: 36, height: 36)
```

Replace `validateStatusIconSource(_:)` with this version:

```swift
func validateStatusIconSource(_ relativePath: String, requiresChevron: Bool) {
    let svg = textFile(relativePath)
    guard !svg.contains("x=\"2.5\" y=\"1.4\" width=\"13\" height=\"2.8\" rx=\"1.4\" fill=\"#000\"") else {
        fail("Status icon source must not include a menu bar top strip: \(relativePath)")
    }
    guard svg.contains("data-role=\"note-outline\"") else {
        fail("Status icon source must include a hollow note outline: \(relativePath)")
    }
    guard occurrenceCount(of: "data-role=\"note-line\"", in: svg) == 2 else {
        fail("Status icon source must include exactly two note lines: \(relativePath)")
    }
    let chevronCount = occurrenceCount(of: "data-role=\"drag-chevron\"", in: svg)
    if requiresChevron {
        guard chevronCount == 1 else {
            fail("Hidden status icon source must include exactly one down-drag chevron")
        }
        guard svg.contains("d=\"M7.1 14.4 L9 16 L10.9 14.4\"") &&
                svg.contains("stroke-width=\"1.35\"") else {
            fail("Hidden status icon source must use the enlarged down-drag chevron")
        }
    } else {
        guard chevronCount == 0 else {
            fail("Visible status icon source must not include a down-drag chevron")
        }
    }
    guard !svg.contains("x=\"3.7\" y=\"5.2\" width=\"10.9\" height=\"10.4\" rx=\"2.2\" fill=\"#000\"") else {
        fail("Status icon source must not use a solid filled note body: \(relativePath)")
    }
}
```

Replace the single `StatusBarIcon` JSON validation block with:

```swift
func validateStatusContents(_ relativePath: String, catalogName: String, baseName: String) {
    let statusJSON = jsonObject(relativePath)
    guard let statusImages = statusJSON["images"] as? [[String: Any]] else {
        fail("\(catalogName) Contents.json has no images array")
    }
    validateInfo(statusJSON, catalogName: catalogName)
    validateImageEntries(statusImages, expected: [
        ImageEntry(idiom: "mac", size: nil, scale: "1x", filename: "\(baseName).png"),
        ImageEntry(idiom: "mac", size: nil, scale: "2x", filename: "\(baseName)@2x.png")
    ], expectedKeys: ["idiom", "scale", "filename"], catalogName: catalogName)
    let properties = statusJSON["properties"] as? [String: Any]
    guard properties?["template-rendering-intent"] as? String == "template" else {
        fail("\(catalogName).imageset must set template-rendering-intent to template")
    }
}

validateStatusContents(
    "DraftBar/Assets.xcassets/StatusBarIconHidden.imageset/Contents.json",
    catalogName: "StatusBarIconHidden",
    baseName: "StatusBarIconHidden"
)
validateStatusContents(
    "DraftBar/Assets.xcassets/StatusBarIconVisible.imageset/Contents.json",
    catalogName: "StatusBarIconVisible",
    baseName: "StatusBarIconVisible"
)

_ = requireFile("IconSource/DraftBarAppIcon.svg")
validateStatusIconSource("IconSource/DraftBarStatusBarIconHidden.svg", requiresChevron: true)
validateStatusIconSource("IconSource/DraftBarStatusBarIconVisible.svg", requiresChevron: false)
```

- [ ] **Step 2: Run the validator and verify it fails before generation changes**

Run:

```bash
Scripts/validate_icon_assets.swift
```

Expected: exit code `1` with a missing file failure for `StatusBarIconHidden` or `StatusBarIconVisible`.

- [ ] **Step 3: Update the generator to emit hidden and visible assets**

In `Scripts/generate_icon_assets.swift`, replace:

```swift
let statusIconDir = appRoot.appendingPathComponent("Assets.xcassets/StatusBarIcon.imageset", isDirectory: true)
```

with:

```swift
let statusHiddenIconDir = appRoot.appendingPathComponent("Assets.xcassets/StatusBarIconHidden.imageset", isDirectory: true)
let statusVisibleIconDir = appRoot.appendingPathComponent("Assets.xcassets/StatusBarIconVisible.imageset", isDirectory: true)
```

Change `drawStatusIcon` to accept a chevron flag:

```swift
func drawStatusIcon(pixels: Int, showsDragChevron: Bool) -> NSBitmapImageRep {
    drawTopLeftBitmap(pixels: pixels, designSize: 18) { context in
        let ink = rgba(0, 0, 0)

        strokeRounded(context, rect: CGRect(x: 3.8, y: 2.3, width: 10.5, height: 10.0), radius: 2.1, color: ink, lineWidth: 1.55)
        fillRounded(context, rect: CGRect(x: 6.0, y: 5.4, width: 4.7, height: 1.0), radius: 0.5, color: ink)
        fillRounded(context, rect: CGRect(x: 6.0, y: 7.7, width: 3.6, height: 1.0), radius: 0.5, color: ink)

        if showsDragChevron {
            context.setStrokeColor(ink)
            context.setLineWidth(1.35)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: CGPoint(x: 7.1, y: 14.4))
            context.addLine(to: CGPoint(x: 9.0, y: 16.0))
            context.addLine(to: CGPoint(x: 10.9, y: 14.4))
            context.strokePath()
        }

        drawRotated(context: context, center: CGPoint(x: 13.2, y: 9.8), degrees: -34) {
            fillRounded(context, rect: CGRect(x: -5.4, y: -1.25, width: 10.8, height: 2.5), radius: 1.25, color: ink)
            let tip = CGMutablePath()
            tip.move(to: CGPoint(x: -7.2, y: 0))
            tip.addLine(to: CGPoint(x: -5.4, y: -1.1))
            tip.addLine(to: CGPoint(x: -5.4, y: 1.1))
            tip.closeSubpath()
            context.addPath(tip)
            context.setFillColor(ink)
            context.fillPath()
        }
    }
}
```

Replace `let statusSVG = """..."""` with:

```swift
let statusHiddenSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18">
  <rect data-role="note-outline" x="3.8" y="2.3" width="10.5" height="10" rx="2.1" fill="none" stroke="#000" stroke-width="1.55"/>
  <rect data-role="note-line" x="6" y="5.4" width="4.7" height="1" rx="0.5" fill="#000"/>
  <rect data-role="note-line" x="6" y="7.7" width="3.6" height="1" rx="0.5" fill="#000"/>
  <path data-role="drag-chevron" d="M7.1 14.4 L9 16 L10.9 14.4" fill="none" stroke="#000" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"/>
  <g transform="translate(13.2 9.8) rotate(-34)">
    <polygon points="-7.2,0 -5.4,-1.1 -5.4,1.1" fill="#000"/>
    <rect x="-5.4" y="-1.25" width="10.8" height="2.5" rx="1.25" fill="#000"/>
  </g>
</svg>
"""

let statusVisibleSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18">
  <rect data-role="note-outline" x="3.8" y="2.9" width="10.5" height="10" rx="2.1" fill="none" stroke="#000" stroke-width="1.55"/>
  <rect data-role="note-line" x="6" y="6" width="4.7" height="1" rx="0.5" fill="#000"/>
  <rect data-role="note-line" x="6" y="8.3" width="3.6" height="1" rx="0.5" fill="#000"/>
  <g transform="translate(13.2 10.4) rotate(-34)">
    <polygon points="-7.2,0 -5.4,-1.1 -5.4,1.1" fill="#000"/>
    <rect x="-5.4" y="-1.25" width="10.8" height="2.5" rx="1.25" fill="#000"/>
  </g>
</svg>
"""
```

Replace status directory creation and status writes with:

```swift
try fileManager.createDirectory(at: statusHiddenIconDir, withIntermediateDirectories: true)
try fileManager.createDirectory(at: statusVisibleIconDir, withIntermediateDirectories: true)
try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)

try appSVG.write(to: sourceDir.appendingPathComponent("DraftBarAppIcon.svg"), atomically: true, encoding: .utf8)
try statusHiddenSVG.write(to: sourceDir.appendingPathComponent("DraftBarStatusBarIconHidden.svg"), atomically: true, encoding: .utf8)
try statusVisibleSVG.write(to: sourceDir.appendingPathComponent("DraftBarStatusBarIconVisible.svg"), atomically: true, encoding: .utf8)

for spec in appIconSpecs {
    try writePNG(drawAppIcon(pixels: spec.pixels), to: appIconDir.appendingPathComponent(spec.filename))
}
try writePNG(drawStatusIcon(pixels: 18, showsDragChevron: true), to: statusHiddenIconDir.appendingPathComponent("StatusBarIconHidden.png"))
try writePNG(drawStatusIcon(pixels: 36, showsDragChevron: true), to: statusHiddenIconDir.appendingPathComponent("StatusBarIconHidden@2x.png"))
try writePNG(drawStatusIcon(pixels: 18, showsDragChevron: false), to: statusVisibleIconDir.appendingPathComponent("StatusBarIconVisible.png"))
try writePNG(drawStatusIcon(pixels: 36, showsDragChevron: false), to: statusVisibleIconDir.appendingPathComponent("StatusBarIconVisible@2x.png"))
```

Add this helper before writing status JSON:

```swift
func statusContents(baseName: String) -> [String: Any] {
    [
        "images": [
            [
                "idiom": "mac",
                "scale": "1x",
                "filename": "\(baseName).png"
            ],
            [
                "idiom": "mac",
                "scale": "2x",
                "filename": "\(baseName)@2x.png"
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
}
```

Replace the existing `statusContents` write with:

```swift
try writeJSON(statusContents(baseName: "StatusBarIconHidden"), to: statusHiddenIconDir.appendingPathComponent("Contents.json"))
try writeJSON(statusContents(baseName: "StatusBarIconVisible"), to: statusVisibleIconDir.appendingPathComponent("Contents.json"))
```

- [ ] **Step 4: Remove the old single-state status icon files**

Run:

```bash
git rm -r DraftBar/Assets.xcassets/StatusBarIcon.imageset
git rm IconSource/DraftBarStatusBarIcon.svg
```

Expected: Git stages the old single-state asset and SVG for deletion.

- [ ] **Step 5: Generate the new icon assets**

Run:

```bash
Scripts/generate_icon_assets.swift
```

Expected:

```text
Generated DraftBar icon assets
```

- [ ] **Step 6: Verify asset validation passes**

Run:

```bash
Scripts/validate_icon_assets.swift
```

Expected:

```text
Icon asset validation passed
```

- [ ] **Step 7: Commit asset changes**

Run:

```bash
git add Scripts/generate_icon_assets.swift Scripts/validate_icon_assets.swift IconSource DraftBar/Assets.xcassets
git commit -m "design: add status icon state assets"
```

Expected: commit succeeds with only icon asset and icon script changes.

---

### Task 2: Wire The App To Switch Status Icons

**Files:**
- Modify: `Scripts/validate_icon_assets.swift`
- Modify: `DraftBar/DraftBarApp.swift`
- Modify: `DraftBar/ContentView.swift`

- [ ] **Step 1: Add app wiring checks to the validator**

In `Scripts/validate_icon_assets.swift`, add this function after `validateStatusIconSource`:

```swift
func validateStatusIconAppWiring() {
    let appSource = textFile("DraftBar/DraftBarApp.swift")
    guard appSource.contains("private enum StatusItemIconState") else {
        fail("AppDelegate must define StatusItemIconState")
    }
    guard appSource.contains("StatusBarIconHidden") &&
            appSource.contains("StatusBarIconVisible") else {
        fail("AppDelegate must reference hidden and visible status icon assets")
    }
    guard appSource.contains("updateStatusItemIcon(.hidden)") &&
            appSource.contains("updateStatusItemIcon(.visible)") else {
        fail("AppDelegate must switch status item icons for hidden and visible states")
    }
    guard appSource.contains("panel.orderOut(nil)") &&
            appSource.contains("self.updateStatusItemIcon(.hidden)") else {
        fail("closeFloatingNote must switch back to the hidden icon after the panel orders out")
    }

    let contentSource = textFile("DraftBar/ContentView.swift")
    guard contentSource.contains("Image(\"StatusBarIconHidden\")") else {
        fail("Drag seed icon must use StatusBarIconHidden")
    }
}
```

Call it near the end of the file before printing success:

```swift
validateStatusIconAppWiring()
```

- [ ] **Step 2: Run the validator and verify it fails before app wiring**

Run:

```bash
Scripts/validate_icon_assets.swift
```

Expected: exit code `1` with:

```text
AppDelegate must define StatusItemIconState
```

- [ ] **Step 3: Add status icon state loading to `DraftBarApp.swift`**

In `DraftBar/DraftBarApp.swift`, add this enum above `final class AppDelegate`:

```swift
private enum StatusItemIconState {
    case hidden
    case visible

    var assetName: String {
        switch self {
        case .hidden:
            "StatusBarIconHidden"
        case .visible:
            "StatusBarIconVisible"
        }
    }
}
```

Inside `AppDelegate`, add this helper near `configureStatusItem()`:

```swift
private func updateStatusItemIcon(_ state: StatusItemIconState) {
    guard let button = statusItem?.button else { return }
    let image = NSImage(named: state.assetName)
        ?? NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "DraftBar")
    image?.isTemplate = true
    button.image = image
}
```

In `configureStatusItem()`, replace:

```swift
let image = NSImage(named: "StatusBarIcon")
    ?? NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "DraftBar")
image?.isTemplate = true
button.image = image
```

with:

```swift
updateStatusItemIcon(.hidden)
```

- [ ] **Step 4: Switch to the visible icon when the panel is shown**

In `showFloatingNote(animatedFromStatusItem:)`, add this immediately after the `if animatedFromStatusItem... else ...` block and before `NSApp.activate(ignoringOtherApps: true)`:

```swift
updateStatusItemIcon(.visible)
```

In `showFloatingNoteForDrag(at:)`, add this immediately after the `if !wasVisible... else ...` block and before `applyPinnedLevel(to: panel)`:

```swift
updateStatusItemIcon(.visible)
```

- [ ] **Step 5: Switch back to the hidden icon only after closing**

In `closeFloatingNote()`, replace the no-target-frame branch:

```swift
guard let targetFrame = statusButtonScreenFrame()?.insetBy(dx: -6, dy: -6) else {
    panel.orderOut(nil)
    return
}
```

with:

```swift
guard let targetFrame = statusButtonScreenFrame()?.insetBy(dx: -6, dy: -6) else {
    panel.orderOut(nil)
    updateStatusItemIcon(.hidden)
    return
}
```

Replace the completion handler body:

```swift
guard let panel else { return }
panel.orderOut(nil)
panel.alphaValue = 1
panel.setFrame(restoreFrame, display: false)
self?.isClosingPanel = false
```

with:

```swift
guard let self, let panel else { return }
panel.orderOut(nil)
panel.alphaValue = 1
panel.setFrame(restoreFrame, display: false)
self.isClosingPanel = false
self.updateStatusItemIcon(.hidden)
```

- [ ] **Step 6: Update the drag seed icon asset name**

In `DraftBar/ContentView.swift`, replace:

```swift
Image("StatusBarIcon")
```

with:

```swift
Image("StatusBarIconHidden")
```

- [ ] **Step 7: Verify the app wiring validator passes**

Run:

```bash
Scripts/validate_icon_assets.swift
```

Expected:

```text
Icon asset validation passed
```

- [ ] **Step 8: Commit app wiring**

Run:

```bash
git add Scripts/validate_icon_assets.swift DraftBar/DraftBarApp.swift DraftBar/ContentView.swift
git commit -m "feat: switch status icon by note visibility"
```

Expected: commit succeeds with only app wiring and validator changes.

---

### Task 3: Build And Final Verification

**Files:**
- Read: `git status`
- Build: `DraftBar.xcodeproj`

- [ ] **Step 1: Verify the validator still passes after both commits**

Run:

```bash
Scripts/validate_icon_assets.swift
```

Expected:

```text
Icon asset validation passed
```

- [ ] **Step 2: Verify the macOS app builds**

Run:

```bash
xcodebuild -project DraftBar.xcodeproj -scheme DraftBar -destination platform=macOS -derivedDataPath /private/tmp/DraftBarStatusIconStatesDerivedData -clonedSourcePackagesDirPath /private/tmp/DraftBarBaselineSourcePackages build
```

Expected: command exits `0` and prints:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 3: Inspect the final diff against the pre-plan base**

Run:

```bash
git status --short
git log --oneline -3
```

Expected:

- no uncommitted tracked files from this implementation remain;
- the latest commits are `feat: switch status icon by note visibility` and `design: add status icon state assets`;
- any existing `.superpowers` runtime files remain uncommitted unless the user explicitly asks to handle them.

- [ ] **Step 4: Report completion**

Final report should include:

- the two new asset names;
- the exact validator command and result;
- the exact build command and result;
- a note that clicking the menu bar icon while the note is already visible focuses the existing editor instead of hiding it.
