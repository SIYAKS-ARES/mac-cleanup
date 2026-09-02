import Foundation

/// `name.ext` → `name (2).ext` when the destination path already exists.
public enum CollisionNamer: Sendable {
    public static func uniqueURL(in directory: URL, preferredName: String, fileExists: (URL) -> Bool) -> URL {
        let ns = preferredName as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        var n = 1
        while true {
            let name: String
            if n == 1 {
                name = preferredName
            } else if ext.isEmpty {
                name = "\(stem) (\(n))"
            } else {
                name = "\(stem) (\(n)).\(ext)"
            }
            let url = directory.appendingPathComponent(name)
            if fileExists(url) == false {
                return url
            }
            n += 1
        }
    }
}
