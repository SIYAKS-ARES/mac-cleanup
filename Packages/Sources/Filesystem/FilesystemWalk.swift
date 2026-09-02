/// Directory walk contract. v1 is a full enumerator; FSEvents plugs in later.
public enum FilesystemWalk: Sendable {
    public static let followsSymlinks = false
    public static let descendsApplicationPackages = false
}

