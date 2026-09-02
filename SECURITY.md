# Security Policy

## Supported Versions

| Version | Supported |
| --- | --- |
| 1.0.x | Yes |

Later 1.x releases replace earlier 1.0.x patches. Pre-1.0 builds are not supported.

## Reporting a Vulnerability

Report vulnerabilities through
[GitHub private vulnerability reporting](https://github.com/SIYAKS-ARES/mac-cleanup/security/advisories/new).

Do **not** open a public issue. There is no email contact for this project.

Please include:

- macOS version and whether you built from source
- Steps to reproduce
- Impact (data exposure, unexpected Trash/move, sandbox escape)

We will acknowledge reports and say whether we accept or decline them. There is no paid bounty.

## Not a Vulnerability

This app never opens WhatsApp `ChatStorage.sqlite`, `Axolotl.sqlite`, or `enc-key.dat`. Asking maintainers to parse those files, or attaching them to a report, is not a security bug.

Apply can send files to Trash when you choose that action. That is intended. Unique + Trash also sends extra copies of Keep types to Trash — the confirm sheet names that split.

Do not attach `apply-report.json`, `catalog.sqlite`, container dumps, or screenshots that show your filenames or home path.
