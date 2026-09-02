# Actions

Apply engine: destination policy, copy, move, Trash, report.

- Destination layouts: **Folders** (source relative paths, default), **Files** (flatten basenames), **Type** (one folder per type-table extension; unsafe names → `none`).
- Collision: `name (2).ext` via `lstat`.
- Disk budget before writes. Keep writes run first; Trash last.
- Copy uses Darwin `copyfile` with `NOFOLLOW`. User files are not removed with `removeItem` — Trash only.

Depends on Classification for the extension parser. No GRDB here; Analysis plans, this package executes.
