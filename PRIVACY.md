# Privacy

mac-cleanup is a local macOS app. It does not use the network.

- No telemetry, analytics, crash reporter, or third-party SDK that phones home.
- Entitlements: App Sandbox, user-selected file read/write, app-scoped bookmarks. Incoming and outgoing network connections are off.
- The walk uses `lstat`. File contents are read only when Unique hashing runs (Keep and Discard types). Skip types and Unique-off sessions are not hashed. Symlinks are not followed.
- WhatsApp layout detection looks at names and directory metadata (`ChatStorage.sqlite` present as a regular file, `Message/Media` as a directory). Those databases are **not opened**.

## Data on disk

| What | Where |
| --- | --- |
| Folder bookmarks | App sandbox container |
| Incremental catalog | `~/Library/Containers/net.siyaks.mac-cleanup/Data/Library/Application Support/MacCleanup/catalog.sqlite` (path inside the sandbox) |
| Apply report | Destination folder when writable; otherwise Application Support `MacCleanup/reports/` |

The catalog stores paths, sizes, inodes, and hashes for the folder you selected. The Apply report lists source and destination paths for that run.

**Do not paste `apply-report.json`, `catalog.sqlite`, or screenshots that show your filenames or home path into GitHub issues or pull requests.**

Quitting the app does not delete the catalog. You can remove the sandbox container in Finder if you want a clean slate.

## What we never collect

Maintainers do not receive your files, chats, or hashes unless you attach them yourself. Please don't.
