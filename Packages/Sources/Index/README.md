# Index

GRDB (SQLite) catalog for one selected root.

- Stores paths, `logical_size` (the size used in the type table and disk budget), inodes, fingerprints.
- Reconcile + type-table SQL; views should not hold tens of thousands of paths.
- `busyTimeout` is 10 seconds; ingest writes in batches of 1000.
- This is **not** WhatsApp ChatStorage. The app catalog lives in Application Support (see [PRIVACY.md](../../../PRIVACY.md)).
