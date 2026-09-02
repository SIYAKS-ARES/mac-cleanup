# Filesystem

`lstat`-based directory walk.

- Symlinks are never followed (broken or live).
- Hidden entries are included.
- Bundled packages (`.app`, `.pkg`, and similar) are not descended.
- Regular files are emitted for the catalog; directories are traversed.

Used by Analysis during Scan. No hashing and no SQLite here.
