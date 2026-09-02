import GRDB

enum TypeTableQuery {
    static func aggregates(rootID: Int64, db: Database) throws -> [TypeTableAggregate] {
        let counts = try Row.fetchAll(
            db,
            sql: """
                SELECT ext, COUNT(*) AS n
                FROM files
                WHERE root_id = ? AND status = ?
                GROUP BY ext
                """,
            arguments: [rootID, FileRowStatus.present.rawValue]
        )

        let logical = try Row.fetchAll(
            db,
            sql: """
                SELECT ext, COALESCE(SUM(inode_size), 0) AS logical_bytes
                FROM (
                    SELECT ext, MIN(logical_size) AS inode_size
                    FROM files
                    WHERE root_id = ? AND status = ?
                    GROUP BY ext, volume_id, inode
                )
                GROUP BY ext
                """,
            arguments: [rootID, FileRowStatus.present.rawValue]
        )

        let sizeClass = try Row.fetchAll(
            db,
            sql: """
                SELECT ext, COALESCE(SUM(s), 0) AS size_class_bytes
                FROM (
                    SELECT ext, logical_size AS s
                    FROM files
                    WHERE root_id = ? AND status = ?
                    GROUP BY ext, logical_size
                )
                GROUP BY ext
                """,
            arguments: [rootID, FileRowStatus.present.rawValue]
        )

        var logicalByExt: [String: Int64] = [:]
        for row in logical {
            logicalByExt[row["ext"]] = row["logical_bytes"]
        }
        var sizeClassByExt: [String: Int64] = [:]
        for row in sizeClass {
            sizeClassByExt[row["ext"]] = row["size_class_bytes"]
        }

        return counts.map { row in
            let ext: String = row["ext"]
            let n: Int = row["n"]
            return TypeTableAggregate(
                ext: ext,
                n: n,
                logicalBytes: logicalByExt[ext] ?? 0,
                sizeClassBytes: sizeClassByExt[ext] ?? 0
            )
        }
        .sorted { $0.ext < $1.ext }
    }
}
