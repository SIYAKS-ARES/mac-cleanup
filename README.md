# mac-cleanup

[![Release](https://img.shields.io/github/v/release/SIYAKS-ARES/mac-cleanup)](https://github.com/SIYAKS-ARES/mac-cleanup/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black.svg)](#requirements)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138.svg)](#requirements)
[![CI](https://github.com/SIYAKS-ARES/mac-cleanup/actions/workflows/ci.yml/badge.svg)](https://github.com/SIYAKS-ARES/mac-cleanup/actions/workflows/ci.yml)

Native macOS **storage intelligence**: scan a folder you choose, see every file type, decide Keep / Discard / Skip and Unique, then copy, move, or Trash with a confirm sheet.

**Latest release:** [v1.0.0](https://github.com/SIYAKS-ARES/mac-cleanup/releases/latest) — [CHANGELOG](CHANGELOG.md)

## What this is

A local, sandboxed Mac app for one user-selected folder. It builds a type table (counts and sizes), optional Unique hashing, then Apply (copy or move Keep files; optional Trash for Discard). WhatsApp is only a **layout hint**, not the product.

## What this is not

Not a WhatsApp extractor. It does not read chats, contacts, or message databases. A WhatsApp **shared-container layout** can be detected from file names (`ChatStorage.sqlite` + `Message/Media`) so the app can warn you; those databases stay closed.

Not affiliated with Meta or Apple.

## Privacy

Local only: no network, no telemetry. Details: [PRIVACY.md](PRIVACY.md).

## Safety defaults

- Unique **on**
- Keep action **Copy**
- Discard action **None** (nothing goes to Trash unless you change it)
- Destination layout **Folders** (preserve source relative paths)

**Unique + Trash is honest:** extra copies of Keep types still go to Trash when Unique is on and Discard is Trash. The confirm sheet splits Unique extras vs Discard types. Defaults stay Copy + no Trash so that path is opt-in.

There is **no permanent delete** (`removeItem` is not used on user files) and **no undo**. Trash recovery is Finder's.

Probe hashes are **not** content equality. Large multi-member groups need a full SHA-256 before Move or Trash.

Sizes use **1024** (KiB, MiB, GiB), not 1000.

## FAQ

**Is this a WhatsApp extractor?** No.

**Does it read chats?** No. ChatStorage, Axolotl, and enc-key are never opened.

**Does it permanently delete files?** No. Discard can send files to Trash when you choose that. Unique extras of Keep types can go to Trash too — confirm says so.

## Requirements

- macOS 14 or later
- Xcode with Swift 6 (open the workspace; see [App/README.md](App/README.md))

## Quick start

```bash
git clone https://github.com/SIYAKS-ARES/mac-cleanup.git
cd mac-cleanup
open MacCleanup.xcworkspace
```

Scheme **MacCleanup**, destination **My Mac**, then Run. Do not open `App/MacCleanup.xcodeproj` alone. Step-by-step: [App/README.md](App/README.md).

Package tests (no window):

```bash
swift test --package-path Packages
```

## Issues

Do **not** attach or paste `apply-report.json`, `catalog.sqlite`, a container dump, ChatStorage / enc-key, or screenshots that show your filenames or home path. Use the issue forms.

## Repository

```
App/                 SwiftUI app (see App/README.md)
Packages/            MacCleanupKit (see Packages/README.md)
Fixtures/            Empty on purpose
.github/             CI, issue forms, Dependabot
MacCleanup.xcworkspace
LICENSE
CHANGELOG.md
PRIVACY.md
THIRD_PARTY_NOTICES.md
CONTRIBUTING.md
SECURITY.md
CODE_OF_CONDUCT.md
```

## License and community

- [LICENSE](LICENSE) (MIT, copyright SIYAKS-ARES)
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (GRDB.swift)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [SECURITY.md](SECURITY.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- [PRIVACY.md](PRIVACY.md)

Contact is **GitHub only**: Issues and [Security Advisories](https://github.com/SIYAKS-ARES/mac-cleanup/security/advisories). No email.
