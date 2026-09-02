# Identity

Content identity for Unique.

- SHA-256 **full** stream, or **probe** (size prefix + first 1 MiB + last 64 KiB) when the file is larger than 16 MiB and Move/Trash does not yet require full.
- Open flags include `O_NOFOLLOW`. A probe is **not** content equality.
- Unique-byte aggregation for the type table.

Analysis decides when to run Identity (Keep ∪ Discard types, Unique on).
