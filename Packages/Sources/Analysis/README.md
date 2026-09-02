# Analysis

App facade: walk → ingest → first paint → Identity → apply plan and confirm copy.

- `AnalysisSession` / `AnalysisWorkspace` are what the SwiftUI target uses.
- **SessionPolicy** sets Unique on, Keep = Copy, Discard = None, and which extensions default to Keep vs Skip.
- Confirm and overlay copy (`ApplyConfirmCopy`, `ApplyOverlayCopy`) name Unique extras vs Discard when Trash is involved.

Display strings (About credits, busy catalog, byte labels) live here so the app stays a thin shell.
