# Note One-Layer Glass UI Design

## Goal

Flatten the note panel so it reads as one liquid glass plate instead of an outer window containing a separate editor card. Keep the current text input behavior intact.

## Approved Visual Direction

- Use one rounded outer panel with subtle material, border, and shadow.
- Remove the inner rounded editor background and the fixed toolbar strip.
- Let the text editor occupy the same visual surface as the panel.
- Place the close control as a floating circular button at the top-left.
- Place the word count and pin control as floating top-right controls.
- Keep the pin symbol behavior aligned with the current app: `pin.fill` when pinned, `pin` when unpinned.

## Scope

In scope:

- Update `FloatingNoteView` layout and visual styling.
- Preserve `MarkdownTextView` as the underlying `NSTextView` wrapper.
- Adjust editor insets/padding only as needed to avoid overlap with floating controls.
- Keep save state, pin behavior, close behavior, drag behavior, and text editing behavior.

Out of scope:

- Replacing `NSTextView`.
- Changing markdown styling, formula overlays, code block behavior, IME handling, persistence, or panel window management.
- Adding new app features.

## Implementation Shape

The implementation should stay surgical:

1. Convert `editorContent` from toolbar-plus-inner-card to a single full-panel editor surface.
2. Add a floating overlay for top controls.
3. Keep `noteBackground` as the only visible panel background.
4. Remove the inner material/stroke wrapper around `MarkdownTextView`.
5. Increase top content inset/padding enough that initial text and placeholder do not sit under the floating controls.

## Verification

- Build the app.
- Confirm the note visually has one primary rounded glass boundary.
- Confirm the close button is top-left and the word count plus pin button are top-right.
- Confirm the pin button still uses the pin icon.
- Smoke test typing in the editor, including Chinese text composition if the app can be run locally.
