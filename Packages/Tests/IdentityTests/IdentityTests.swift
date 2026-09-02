import CryptoKit
import Darwin
import Foundation
import Identity
import Testing

struct IdentityTests {
    @Test func fingerprintKindsExist() {
        #expect(FingerprintKind.none.rawValue == "none")
        #expect(FingerprintKind.probe.rawValue == "probe")
        #expect(FingerprintKind.full.rawValue == "full")
    }

    @Test func fingerprintKindIsExhaustive() {
        let kinds: [FingerprintKind] = [.none, .probe, .full]
        let labels = kinds.map { kind -> String in
            switch kind {
            case .none: "none"
            case .probe: "probe"
            case .full: "full"
            }
        }
        #expect(Set(labels).count == kinds.count)
    }

    @Test func sixteenMebibyteCutIsInclusiveFull() {
        #expect(FingerprintPolicy.fullHashMaxLogicalSize == 16 * 1024 * 1024)
        #expect(FingerprintPolicy.probeHeadByteCount == 1 * 1024 * 1024)
        #expect(FingerprintPolicy.probeTailByteCount == 64 * 1024)
        #expect(FingerprintPolicy.kindForMultiMemberGroup(logicalSize: 0) == .full)
        #expect(
            FingerprintPolicy.kindForMultiMemberGroup(
                logicalSize: FingerprintPolicy.fullHashMaxLogicalSize
            ) == .full
        )
        #expect(
            FingerprintPolicy.kindForMultiMemberGroup(
                logicalSize: FingerprintPolicy.fullHashMaxLogicalSize + 1
            ) == .probe
        )
        #expect(
            FingerprintPolicy.requiredKind(
                logicalSize: FingerprintPolicy.fullHashMaxLogicalSize + 1,
                requireFull: true
            ) == .full
        )
        #expect(FingerprintPolicy.existingSatisfies(.probe, required: .probe))
        #expect(FingerprintPolicy.existingSatisfies(.full, required: .probe))
        #expect(FingerprintPolicy.existingSatisfies(.probe, required: .full) == false)
        #expect(FingerprintPolicy.existingSatisfies(.none, required: .full) == false)
    }

    @Test func hashUniqueSplitsSameSizeDifferentFingerprints() {
        let size: Int64 = 112_621
        let bytes = HashUniqueAggregation.bytes([
            HashUniqueMember(inode: 1, logicalSize: size, fingerprint: Data([1])),
            HashUniqueMember(inode: 2, logicalSize: size, fingerprint: Data([2])),
            HashUniqueMember(inode: 3, logicalSize: 10, fingerprint: nil),
        ])
        #expect(bytes == size * 2 + 10)
    }

    @Test func hashUniqueCollapsesSameFingerprint() {
        let size: Int64 = 50
        let fp = Data([9])
        let bytes = HashUniqueAggregation.bytes([
            HashUniqueMember(inode: 1, logicalSize: size, fingerprint: fp),
            HashUniqueMember(inode: 2, logicalSize: size, fingerprint: fp),
        ])
        #expect(bytes == size)
    }

    @Test func hashUniqueKeepsSameInodeOnDifferentVolumes() {
        let size: Int64 = 50
        let fp = Data([9])
        let bytes = HashUniqueAggregation.bytes([
            HashUniqueMember(inode: 1, logicalSize: size, fingerprint: fp, volumeID: "dev:1"),
            HashUniqueMember(inode: 1, logicalSize: size, fingerprint: fp, volumeID: "dev:2"),
        ])
        #expect(bytes == size)
    }

    @Test func hashUniqueCollapsesDuplicateInodes() {
        let size: Int64 = 50
        let fp = Data([9])
        let bytes = HashUniqueAggregation.bytes([
            HashUniqueMember(inode: 1, logicalSize: size, fingerprint: nil),
            HashUniqueMember(inode: 1, logicalSize: size, fingerprint: fp),
            HashUniqueMember(inode: 2, logicalSize: size, fingerprint: fp),
        ])
        #expect(bytes == size)
    }

    @Test func hasherDoesNotFollowSymlinks() throws {
        let root = try IdentityTree.make()
        defer { IdentityTree.remove(root) }
        let target = root.appendingPathComponent("secret.bin")
        let link = root.appendingPathComponent("alias.bin")
        let payload = Data("secret-payload".utf8)
        try payload.write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: ContentHasherError.unreadable) {
            try ContentHasher.hash(file: link, logicalSize: Int64(payload.count), kind: .full)
        }
        let real = try ContentHasher.hash(file: target, logicalSize: Int64(payload.count), kind: .full)
        #expect(real == Data(SHA256.hash(data: payload)))
    }

    @Test func hasherRejectsNegativeAndChangedSize() throws {
        let root = try IdentityTree.make()
        defer { IdentityTree.remove(root) }
        let file = root.appendingPathComponent("a.bin")
        try Data("hello".utf8).write(to: file)
        #expect(throws: ContentHasherError.sizeMismatch) {
            try ContentHasher.hash(file: file, logicalSize: -1, kind: .full)
        }
        #expect(throws: ContentHasherError.sizeMismatch) {
            try ContentHasher.hash(file: file, logicalSize: 99, kind: .full)
        }
    }

    @Test func fullHashMatchesCryptoKitAndDiffersOnContent() throws {
        let root = try IdentityTree.make()
        defer { IdentityTree.remove(root) }
        let a = root.appendingPathComponent("a.bin")
        let b = root.appendingPathComponent("b.bin")
        try Data("hello".utf8).write(to: a)
        try Data("hallo".utf8).write(to: b)
        let ha = try ContentHasher.hash(file: a, logicalSize: 5, kind: .full)
        let hb = try ContentHasher.hash(file: b, logicalSize: 5, kind: .full)
        #expect(ha.count == FingerprintPolicy.digestByteCount)
        #expect(ha != hb)
        #expect(ha == Data(SHA256.hash(data: Data("hello".utf8))))
    }

    @Test func emptyFileFullAndProbeMatchCryptoKitShape() throws {
        let root = try IdentityTree.make()
        defer { IdentityTree.remove(root) }
        let file = root.appendingPathComponent("empty.bin")
        try Data().write(to: file)
        let full = try ContentHasher.hash(file: file, logicalSize: 0, kind: .full)
        #expect(full == Data(SHA256.hash(data: Data())))
        var probeHasher = SHA256()
        probeHasher.update(data: FingerprintPolicy.probeSizePrefix(0))
        let probe = try ContentHasher.hash(file: file, logicalSize: 0, kind: .probe)
        #expect(probe == Data(probeHasher.finalize()))
    }

    /// Plan verify-tiny: hashing multi-MiB files must not allocate per-chunk `Data` (was GB-scale pressure).
    @Test func fullHashTwentyMebibytePairKeepsRSSDeltaUnder256MiB() throws {
        let size: Int64 = 20 * 1024 * 1024
        let root = try IdentityTree.make()
        defer { IdentityTree.remove(root) }
        let a = root.appendingPathComponent("a.bin")
        let b = root.appendingPathComponent("b.bin")
        try IdentityTree.writeSparse(a, logicalSize: size, mutations: [0: 1, size - 1: 2])
        try IdentityTree.writeSparse(b, logicalSize: size, mutations: [0: 1, size - 1: 2])
        let before = IdentityTree.residentByteCount()
        #expect(before > 0, "mach_task_basic_info RSS unavailable")
        // Probe is the Unique-on default above 16 MiB; full is the Move/Trash upgrade path.
        let pa = try ContentHasher.hash(file: a, logicalSize: size, kind: .probe)
        let pb = try ContentHasher.hash(file: b, logicalSize: size, kind: .probe)
        #expect(pa == pb)
        let ha = try ContentHasher.hash(file: a, logicalSize: size, kind: .full)
        let hb = try ContentHasher.hash(file: b, logicalSize: size, kind: .full)
        let after = IdentityTree.residentByteCount()
        #expect(after > 0, "mach_task_basic_info RSS unavailable")
        #expect(ha.count == FingerprintPolicy.digestByteCount)
        #expect(ha == hb)
        #expect(ha != pa)
        // Hasher keeps a 1 MiB slab; old FileHandle path ballooned toward tens of GiB.
        // Cap well under 1 GiB so a multi-hundred-MiB regression still fails.
        let delta = after > before ? after - before : 0
        #expect(delta < 256 * 1024 * 1024)
    }

    @Test func hasherRejectsDirectory() throws {
        let root = try IdentityTree.make()
        defer { IdentityTree.remove(root) }
        #expect(throws: ContentHasherError.unreadable) {
            try ContentHasher.hash(file: root, logicalSize: 0, kind: .full)
        }
    }

    @Test func probeIgnoresMiddleBytesAndSeesTail() throws {
        let size: Int64 = 2 * 1024 * 1024
        let root = try IdentityTree.make()
        defer { IdentityTree.remove(root) }
        let a = root.appendingPathComponent("a.bin")
        let b = root.appendingPathComponent("b.bin")
        let c = root.appendingPathComponent("c.bin")
        try IdentityTree.writeSparse(a, logicalSize: size, mutations: [1_500_000: 1])
        try IdentityTree.writeSparse(b, logicalSize: size, mutations: [1_500_000: 2])
        try IdentityTree.writeSparse(c, logicalSize: size, mutations: [size - 1: 9])
        let pa = try ContentHasher.hash(file: a, logicalSize: size, kind: .probe)
        let pb = try ContentHasher.hash(file: b, logicalSize: size, kind: .probe)
        let pc = try ContentHasher.hash(file: c, logicalSize: size, kind: .probe)
        #expect(pa == pb)
        #expect(pa != pc)
        let fa = try ContentHasher.hash(file: a, logicalSize: size, kind: .full)
        let fb = try ContentHasher.hash(file: b, logicalSize: size, kind: .full)
        #expect(fa != pa)
        #expect(fa != fb)
    }
}

enum IdentityTree {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-cleanup-id-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func writeSparse(_ url: URL, logicalSize: Int64, mutations: [Int64: UInt8]) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(logicalSize))
        for (offset, value) in mutations {
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: Data([value]))
        }
        try handle.close()
    }

    static func residentByteCount() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return 0
        }
        return info.resident_size
    }
}
