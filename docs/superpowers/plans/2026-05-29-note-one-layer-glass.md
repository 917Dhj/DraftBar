# Note One-Layer Glass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change the floating note UI from an outer panel containing an inner editor card into one liquid glass plate with floating close, count, and pin controls.

**Architecture:** Keep the existing AppKit-backed `MarkdownTextView` and markdown styling pipeline unchanged. Flatten only the SwiftUI chrome in `FloatingNoteView`, using the existing outer material as the single visible surface and placing controls in an overlay above the editor.

**Tech Stack:** macOS SwiftUI, AppKit `NSTextView` through `NSViewRepresentable`, Xcode build verification.

---

### Task 1: Flatten Floating Note Chrome

**Files:**
- Modify: `ContentView.swift`

- [ ] **Step 1: Preserve the editor implementation boundary**

Do not edit `MarkdownTextView.makeNSView`, `MarkdownTextView.updateNSView`, or `MarkdownTextView.Coordinator` behavior. These own text input, IME handling, markdown styling, and formula overlays.

- [ ] **Step 2: Replace toolbar-plus-inner-card layout**

In `FloatingNoteView`, change `editorContent` from a `VStack` containing `toolbar` and an inner rounded `ZStack` into one full-size `ZStack`:

```swift
private var editorContent: some View {
    ZStack(alignment: .topLeading) {
        MarkdownTextView(text: $store.text, focusRequestID: focusController.requestID)

        if store.text.isEmpty {
            Text("写点什么...")
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)
                .padding(.top, MarkdownTextView.placeholderTopPadding)
                .padding(.leading, MarkdownTextView.placeholderLeadingPadding)
                .allowsHitTesting(false)
        }

        floatingControls
    }
}
```

- [ ] **Step 3: Add floating controls**

Replace the fixed toolbar with a floating overlay that keeps the same actions:

```swift
private var floatingControls: some View {
    HStack(alignment: .top) {
        Button(action: closeNote) {
            CloseGlassButton()
        }
        .buttonStyle(.plain)
        .help("Close")

        Spacer(minLength: 12)

        HStack(spacing: 10) {
            Text("\(store.text.count) 字")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: togglePin) {
                PinGlassButton(isPinned: windowState.isPinned)
            }
            .buttonStyle(.plain)
            .help(windowState.isPinned ? "Unpin from front" : "Pin on top")
        }
    }
    .padding(.top, 14)
    .padding(.horizontal, 16)
}
```

- [ ] **Step 4: Keep menu access out of the editor surface**

Do not add a SwiftUI context menu around `MarkdownTextView`; the AppKit text view should keep its native text editing context menu. Removing the visible ellipsis button is acceptable because `Open Note File` and `Quit` remain available from the menu bar item menu.

Keep `openNoteFile` and `quitApp` closures on `FloatingNoteView` for now so the constructor surface stays stable during this UI-only change.

- [ ] **Step 5: Add a pin glass button**

Create a small `PinGlassButton` view near `CloseGlassButton` using the current app icon names:

```swift
struct PinGlassButton: View {
    let isPinned: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(isPinned ? 0.34 : 0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.10), radius: 6, y: 2)

            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isPinned ? .primary : .secondary)
        }
        .frame(width: 30, height: 30)
        .contentShape(Circle())
    }
}
```

- [ ] **Step 6: Adjust text inset for floating controls**

Increase `MarkdownTextView.textContainerInset.height` enough to keep first-line text below the floating controls. Keep the horizontal inset close to the current value so existing editing feel stays familiar:

```swift
static let textContainerInset = NSSize(width: 18, height: 58)
static let placeholderTopPadding: CGFloat = 58
static let placeholderLeadingPadding: CGFloat = 24
```

- [ ] **Step 7: Build**

Run from the Xcode project root:

```bash
xcodebuild -scheme DraftBar -configuration Debug build
```

Expected: build succeeds.

- [ ] **Step 8: Visual and typing smoke test**

Launch the app if possible, open the note, and confirm:

- One visible rounded glass boundary.
- No inner editor card border.
- Close button is top-left.
- Word count and pin button are top-right.
- Pin icon uses `pin.fill` or `pin`.
- Typing in the editor still works.
