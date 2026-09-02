# App

SwiftUI shell for mac-cleanup. Business logic lives in [Packages](../Packages/README.md). The app target imports **Analysis** only.

## How to run

This is a **macOS** app (`MacCleanup.app`). There is no iPhone/iPad Simulator destination and no SwiftUI `#Preview` — `NSOpenPanel`, sandbox, and bookmarks need a real process.

1. Open **`MacCleanup.xcworkspace`** at the repository root (not `App/MacCleanup.xcodeproj` alone). The workspace links `../Packages`.
2. Scheme **MacCleanup**, destination **My Mac**.
3. Quit any leftover `MacCleanup` process first. A second copy of the app contends for the same sandbox catalog.
4. **Product → Run** (`Cmd+R`).

Signing is **ad-hoc** (`CODE_SIGN_IDENTITY = "-"`). Bundle id: `net.siyaks.mac-cleanup`. Sandbox: user-selected read-write + app-scoped bookmarks; **no network**.

CLI build from the repo root:

```bash
xcodebuild \
  -workspace MacCleanup.xcworkspace \
  -scheme MacCleanup \
  -destination 'platform=macOS' \
  -configuration Debug \
  -derivedDataPath DerivedData \
  CODE_SIGN_IDENTITY=- \
  build

open DerivedData/Build/Products/Debug/MacCleanup.app
```

`DerivedData/` is gitignored. You do not need to copy the app into `/Applications`. Close that `.app` before the next `Cmd+R`.

## First clicks

The app cannot see arbitrary paths until you **Choose Folder…** / **Choose Destination…**. Do not point the source at the live WhatsApp Group Container (`~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared`) unless you intend to scan it — the yellow banner is a warning, not a default.

About **mac-cleanup** (app menu) shows the short credits: no network, ChatStorage closed, sizes in 1024.

## Layout

| Path | Role |
| --- | --- |
| `MacCleanup/Sources/` | SwiftUI, bookmarks, session controller |
| `MacCleanup/Resources/` | AppIcon |
| `MacCleanup.xcodeproj/` | Xcode project (open via the workspace) |
| `MacCleanup/MacCleanup.entitlements` | Sandbox |

Do not add README files under `Sources/` or `Assets.xcassets`.
