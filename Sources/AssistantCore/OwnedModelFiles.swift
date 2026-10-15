import Foundation

public enum OwnedModelFiles {
    public static func validate(_ targets: [URL], root: URL) throws -> [URL] {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let prefix = root.path + (root.path.hasSuffix("/") ? "" : "/")
        let checked = try targets.map { input -> URL in
            let target = input.standardizedFileURL
            let resolved = target.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(prefix), resolved != root,
                  (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw AssistantError.invalidTool("Model cleanup rejected a location outside its owned storage.") }
            let relative = String(resolved.path.dropFirst(prefix.count))
            let components = relative.split(separator: "/")
            guard components.count >= 2, ["packages", "imports", "text-runtime", "records"].contains(String(components[0])) else { throw AssistantError.invalidTool("Only model packages and their derived files can be removed here.") }
            return target
        }
        return Array(Set(checked))
    }
    public static func size(_ targets: [URL], root: URL) throws -> Int64 {
        var bytes: Int64 = 0
        for target in try validate(targets, root: root) {
            guard FileManager.default.fileExists(atPath: target.path) else { continue }
            if let values = try? target.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]), values.isDirectory != true { bytes += Int64(values.fileSize ?? 0); continue }
            let enumerator = FileManager.default.enumerator(at: target, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            while let child = enumerator?.nextObject() as? URL {
                let values = try child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                if values.isRegularFile == true, values.isSymbolicLink != true { bytes += Int64(values.fileSize ?? 0) }
            }
        }
        return bytes
    }
    @discardableResult public static func remove(_ targets: [URL], root: URL) throws -> Int64 {
        let checked = try validate(targets, root: root), bytes = try size(checked, root: root)
        for path in checked where FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
        return bytes
    }
}
