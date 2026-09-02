# Packages

Local Swift package **MacCleanupKit** (`swift-tools-version: 6.0`, Swift language mode 6, macOS 14).

The app depends on the **Analysis** product. Other libraries are for tests and for Analysis to orchestrate.

## Products

| Library | Role |
| --- | --- |
| Filesystem | Directory walk |
| Index | GRDB catalog |
| Classification | Extension → category |
| Identity | SHA-256 full and probe |
| Actions | Apply engine |
| Analysis | Session facade |
| Hints | WhatsApp layout signature (no database parse) |

SQLite goes through [GRDB.swift](https://github.com/groue/GRDB.swift) (MIT). The pin is in `Package.resolved` (**7.11.1**). See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

`.gitignore` ships with `# Packages/` **commented out**. Uncommenting that template line would ignore this directory and drop the sources from git.

Each `Sources/<module>/README.md` is documentation only. `Package.swift` excludes those files from the module so SwiftPM does not treat them as unhandled resources.

## Tests

```bash
swift test --package-path Packages
```

From the repository root. Each `*Tests` target is documented in [Tests/README.md](Tests/README.md).
