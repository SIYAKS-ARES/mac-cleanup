import Actions
import Foundation
import Identity
import Index

enum ApplyPlanner: Sendable {
    static func plan(
        catalog: Catalog,
        rootID: Int64,
        rows: [TypeTableDisplayRow],
        uniqueEnabled: Bool,
        keepAction: KeepAction,
        discardAction: DiscardAction,
        destinationLayout: DestinationLayout = .default
    ) throws -> ApplyPlan {
        let needsFull = SessionActions.identityRequiresFull(keep: keepAction, discard: discardAction)
        var keeps: [ApplyKeepWork] = []
        var trash: [ApplyTrashWork] = []
        var skippedNeedsFull: [String] = []

        for row in rows {
            switch row.decision {
            case .skip:
                continue
            case .discard:
                let identities = try identities(catalog: catalog, rootID: rootID, ext: row.ext)
                for identity in identities {
                    if discardAction == .trash {
                        trash.append(
                            ApplyTrashWork(
                                groupID: identity.groupID,
                                sourceRelativePath: identity.relativePath,
                                logicalSize: identity.logicalSize
                            )
                        )
                    }
                }
            case .keep:
                let identities = try identities(catalog: catalog, rootID: rootID, ext: row.ext)
                if uniqueEnabled, hasMultiIdentitySize(identities) {
                    if try catalog.hashUniqueBytes(rootID: rootID, ext: row.ext) == nil {
                        throw ApplySessionError.identityIncomplete
                    }
                }
                let planned = partitionKeep(
                    identities: identities,
                    uniqueEnabled: uniqueEnabled,
                    needsFull: needsFull,
                    discardAction: discardAction
                )
                keeps.append(contentsOf: planned.keeps)
                if discardAction == .trash {
                    trash.append(contentsOf: planned.duplicates)
                }
                skippedNeedsFull.append(contentsOf: planned.skippedNeedsFull)
            }
        }

        return ApplyPlan(
            keepAction: keepAction,
            discardAction: discardAction,
            uniqueEnabled: uniqueEnabled,
            keeps: keeps.sorted { $0.sourceRelativePath < $1.sourceRelativePath },
            trash: trash.sorted { $0.sourceRelativePath < $1.sourceRelativePath },
            skippedNeedsFull: skippedNeedsFull.sorted(),
            destinationLayout: destinationLayout
        )
    }

    private struct IdentityMember {
        let groupID: String
        let relativePath: String
        let logicalSize: Int64
        let fingerprint: Data?
        let fingerprintKind: FingerprintKind
        let volumeID: String
        let inode: Int64
    }

    private static func identities(catalog: Catalog, rootID: Int64, ext: String) throws -> [IdentityMember] {
        let files = try catalog.presentFiles(rootID: rootID, ext: ext)
        var byKey: [String: FileSnapshot] = [:]
        for file in files {
            let key = "\(file.volumeID)\u{1e}\(file.inode)"
            if let existing = byKey[key] {
                if file.relativePath < existing.relativePath {
                    byKey[key] = file
                }
            } else {
                byKey[key] = file
            }
        }
        return byKey.values.map { file in
            IdentityMember(
                groupID: "inode:\(file.volumeID):\(file.inode)",
                relativePath: file.relativePath,
                logicalSize: file.logicalSize,
                fingerprint: file.fingerprint,
                fingerprintKind: file.fingerprintKind,
                volumeID: file.volumeID,
                inode: file.inode
            )
        }
        .sorted { $0.relativePath < $1.relativePath }
    }

    private static func hasMultiIdentitySize(_ identities: [IdentityMember]) -> Bool {
        var counts: [Int64: Int] = [:]
        for identity in identities {
            counts[identity.logicalSize, default: 0] += 1
        }
        return counts.values.contains { $0 > 1 }
    }

    private struct Partition {
        var keeps: [ApplyKeepWork] = []
        var duplicates: [ApplyTrashWork] = []
        var skippedNeedsFull: [String] = []
    }

    private static func partitionKeep(
        identities: [IdentityMember],
        uniqueEnabled: Bool,
        needsFull: Bool,
        discardAction: DiscardAction
    ) -> Partition {
        var result = Partition()
        var bySize: [Int64: [IdentityMember]] = [:]
        for identity in identities {
            bySize[identity.logicalSize, default: []].append(identity)
        }
        for (size, group) in bySize {
            if uniqueEnabled == false || group.count == 1 {
                for member in group {
                    result.keeps.append(keepWork(member, groupID: member.groupID))
                }
                continue
            }
            if needsFull, size > FingerprintPolicy.fullHashMaxLogicalSize,
               group.contains(where: { $0.fingerprintKind != .full })
            {
                result.skippedNeedsFull.append(contentsOf: group.map(\.relativePath))
                continue
            }
            var byFingerprint: [Data: [IdentityMember]] = [:]
            var unhashed: [IdentityMember] = []
            for member in group {
                if let fingerprint = member.fingerprint {
                    byFingerprint[fingerprint, default: []].append(member)
                } else {
                    unhashed.append(member)
                }
            }
            for (fingerprint, members) in byFingerprint {
                let sorted = members.sorted { $0.relativePath < $1.relativePath }
                let representative = sorted[0]
                let groupID = "fp:\(fingerprint.map { String(format: "%02x", $0) }.joined())"
                result.keeps.append(keepWork(representative, groupID: groupID))
                if discardAction == .trash {
                    for extra in sorted.dropFirst() {
                        result.duplicates.append(
                            ApplyTrashWork(
                                groupID: groupID,
                                sourceRelativePath: extra.relativePath,
                                logicalSize: extra.logicalSize
                            )
                        )
                    }
                }
            }
            for member in unhashed {
                result.keeps.append(keepWork(member, groupID: member.groupID))
            }
        }
        return result
    }

    private static func keepWork(_ member: IdentityMember, groupID: String) -> ApplyKeepWork {
        ApplyKeepWork(
            groupID: groupID,
            sourceRelativePath: member.relativePath,
            logicalSize: member.logicalSize,
            fingerprintKind: member.fingerprintKind.rawValue
        )
    }
}
