# DraftBar

DraftBar is a single-draft macOS menu bar scratchpad. Its domain centers on preserving a quickly accessible plain-Markdown draft while presenting a lightweight, native editing experience.

## Language

**Draft**:
The single Markdown document that DraftBar keeps available from the menu bar and persists locally between sessions.
_Avoid_: Note collection, document library, workspace

**Live-styled Markdown editor**:
An editor whose source of truth remains plain Markdown while syntax is styled or visually replaced in the same editable surface.
_Avoid_: Rich-text editor, rendered preview

**Editor engine**:
The component responsible for Markdown parsing, live styling, rendering, and Markdown-aware input behavior inside the live-styled Markdown editor.
_Avoid_: App shell, draft store
