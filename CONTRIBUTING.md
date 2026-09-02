# Contributing

Thanks for looking at mac-cleanup. There is no CLA. Conventional commits are not required.

## Setup

1. Clone this repository.
2. Open **`MacCleanup.xcworkspace`** at the repo root — not `App/MacCleanup.xcodeproj` alone. The workspace links the app to the local Swift package.
3. Scheme **MacCleanup**, destination **My Mac**. This is a native macOS app: there is no iOS Simulator target and no SwiftUI Preview.
4. How to run the window: [App/README.md](App/README.md).

## Tests

```bash
swift test --package-path Packages
```

Do not uncomment `# Packages/` in `.gitignore`. That line would ignore this repo's package sources.

If you bump GRDB, keep `Packages/Package.resolved` and
`App/MacCleanup.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
on the same version pin.

CI is `.github/workflows/ci.yml` (package tests, workspace build, gitleaks). Actions are pinned by commit SHA. Do not put secrets or license keys in workflow files. The personal-account gitleaks-action does not need `GITLEAKS_LICENSE`.

## Product rules

- **English** for UI strings and user-facing copy.
- Defaults stay Unique on, Keep = Copy, Discard = None unless the change is about those defaults.
- Probe hashes are not content equality. Do not treat them as such in copy or tests.
- Never `open` WhatsApp `ChatStorage.sqlite`, `Axolotl.sqlite`, or `enc-key.dat`.
- Apply I/O must not call `FileManager.removeItem` on user files (Trash only).

## Do not commit

- A WhatsApp group container copy (`group.net.whatsapp.WhatsApp.shared/`)
- `enc-key.dat`, `apply-report.json`, `catalog.sqlite` (except tiny files under `Fixtures/` allowed by gitignore)
- Screenshots that show your filenames or home path
- Secrets, tokens, or personal email addresses

## Pull requests

See [`.github/PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md). Run package tests. Keep discussion on GitHub — there is no project email.

By contributing you agree your work is licensed under the [MIT License](LICENSE) and that you will follow the [Code of Conduct](CODE_OF_CONDUCT.md).
