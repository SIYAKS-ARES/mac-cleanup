import Foundation

/// One file identity in a type: `(volume_id, inode)`. Aggregation also collapses duplicate rows
/// for the same identity (prefer a stored fingerprint).
public struct HashUniqueMember: Sendable, Equatable {
    public let volumeID: String
    public let inode: Int64
    public let logicalSize: Int64
    public let fingerprint: Data?

    public init(inode: Int64, logicalSize: Int64, fingerprint: Data?, volumeID: String = "") {
        self.volumeID = volumeID
        self.inode = inode
        self.logicalSize = logicalSize
        self.fingerprint = fingerprint
    }
}

/// Unique keep bytes: singleton sizes count once; multi-inode sizes count once per distinct fingerprint.
/// Duplicate `(volume_id, inode)` rows are collapsed first (prefer a stored fingerprint). Unhashed
/// identities in a multi-inode size each count as their own group (conservative).
public enum HashUniqueAggregation: Sendable {
    public static func bytes<S: Sequence>(_ members: S) -> Int64 where S.Element == HashUniqueMember {
        var byIdentity: [InodeIdentity: HashUniqueMember] = [:]
        for member in members {
            let key = InodeIdentity(volumeID: member.volumeID, inode: member.inode)
            if let existing = byIdentity[key] {
                if existing.fingerprint == nil, member.fingerprint != nil {
                    byIdentity[key] = member
                }
            } else {
                byIdentity[key] = member
            }
        }
        var bySize: [Int64: [HashUniqueMember]] = [:]
        for member in byIdentity.values {
            bySize[member.logicalSize, default: []].append(member)
        }
        var total: Int64 = 0
        for (size, group) in bySize {
            if group.count <= 1 {
                total += size
                continue
            }
            var fingerprints = Set<Data>()
            var unhashed = 0
            for member in group {
                if let fingerprint = member.fingerprint {
                    fingerprints.insert(fingerprint)
                } else {
                    unhashed += 1
                }
            }
            total += size * Int64(fingerprints.count + unhashed)
        }
        return total
    }
}

private struct InodeIdentity: Hashable {
    let volumeID: String
    let inode: Int64
}
