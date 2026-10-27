import Foundation

/// One skill: a folder with a SKILL.md (Agent Skills format) and optional supporting files.
public struct BenchSkill: Sendable, Equatable {
    public let name: String
    public let description: String
    public let license: String
    /// The SKILL.md text after its frontmatter.
    public let body: String
    /// The whole SKILL.md file, as published.
    public let rawText: String
    /// Other text files in the skill folder, as paths relative to it.
    public let supportingFiles: [String]
}

/// Finds and reads the skills that ship next to the server. The same files are
/// served to apps as MCP prompts (one per skill) and resources (every file).
public enum BenchSkills {
    public static let environmentKey = "BENCH_SKILLS_DIR"
    public static let bundle = "bench"
    static let textSuffixes: Set<String> = ["md", "txt", "json", "yaml", "yml", "py", "js", "sh", "toml", "csv", "svg"]
    /// License and notice files ship with third-party skills and are served as resources too.
    static let licenseNames: Set<String> = ["LICENSE", "LICENCE", "NOTICE"]

    /// The skills folder, in this order: BENCH_SKILLS_DIR; the Homebrew layout
    /// (<prefix>/bin/bench with <prefix>/share/bench/skills); then a skills/ folder in
    /// the executable's directory or one of its six parents, which is where a source
    /// checkout's build products sit. The executable path is resolved through symlinks.
    public static func directory(env: [String: String], executable: URL?) -> URL? {
        let fm = FileManager.default
        if let explicit = env[environmentKey], !explicit.isEmpty {
            let url = URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath).standardizedFileURL
            return hasSkills(url, fm) ? url : nil
        }
        guard let exeDir = executable?.resolvingSymlinksInPath().deletingLastPathComponent() else {
            return nil
        }
        var candidates = [exeDir.appendingPathComponent("../share/bench/skills").standardizedFileURL]
        var ancestor = exeDir
        for _ in 0..<6 {
            candidates.append(ancestor.appendingPathComponent("skills").standardizedFileURL)
            ancestor = ancestor.deletingLastPathComponent()
        }
        return candidates.first { hasSkills($0, fm) }
    }

    static func hasSkills(_ url: URL, _ fm: FileManager) -> Bool {
        fm.fileExists(atPath: url.appendingPathComponent("getting-started/SKILL.md").path)
    }

    /// Every folder under `root` that has a SKILL.md, sorted by folder name.
    public static func load(from root: URL?) -> [BenchSkill] {
        guard let root else { return [] }
        let fm = FileManager.default
        let folders = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { fm.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return folders.compactMap { folder in
            guard let raw = try? String(contentsOf: folder.appendingPathComponent("SKILL.md"), encoding: .utf8) else {
                return nil
            }
            let (meta, body) = frontmatter(raw)
            return BenchSkill(
                name: meta["name"] ?? folder.lastPathComponent,
                description: meta["description"] ?? "",
                license: meta["license"] ?? "",
                body: body,
                rawText: raw,
                supportingFiles: supportingFiles(in: folder)
            )
        }
    }

    static func supportingFiles(in folder: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [String] = []
        for case let file as URL in walker {
            guard file.lastPathComponent != "SKILL.md",
                  textSuffixes.contains(file.pathExtension.lowercased()) || licenseNames.contains(file.lastPathComponent.uppercased()),
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            out.append(relativePath(of: file, to: folder))
        }
        return out.sorted()
    }

    /// The resource URI for one file: skill://bench/<skill>/<path>.
    public static func uri(skill: String, path: String = "SKILL.md") -> String {
        "skill://\(bundle)/\(skill)/\(path)"
    }

    static func relativePath(of file: URL, to folder: URL) -> String {
        let base = folder.standardizedFileURL.path + "/"
        let full = file.standardizedFileURL.path
        return full.hasPrefix(base) ? String(full.dropFirst(base.count)) : file.lastPathComponent
    }

    /// Top-level scalar keys of a SKILL.md header (folded `>` and literal `|` values
    /// are joined into one line) and the body after it.
    public static func frontmatter(_ text: String) -> ([String: String], String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else { return ([:], text) }
        let rest = normalized.dropFirst(4)
        guard let end = rest.range(of: "\n---") else { return ([:], text) }
        let header = rest[rest.startIndex..<end.lowerBound].split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var afterEnd = rest[end.upperBound...]
        if afterEnd.hasPrefix("\n") { afterEnd = afterEnd.dropFirst() }

        var meta: [String: String] = [:]
        var i = 0
        while i < header.count {
            let line = header[i]
            if let first = line.first, !first.isWhitespace, let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if [">", "|", ">-", "|-", ">+", "|+"].contains(value) {
                    var parts: [String] = []
                    while i + 1 < header.count, header[i + 1].isEmpty || header[i + 1].first?.isWhitespace == true {
                        i += 1
                        let piece = header[i].trimmingCharacters(in: .whitespaces)
                        if !piece.isEmpty { parts.append(piece) }
                    }
                    value = parts.joined(separator: " ")
                }
                if value.count >= 2, (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                meta[key] = value
            }
            i += 1
        }
        var body = String(afterEnd)
        while body.hasPrefix("\n") { body.removeFirst() }
        return (meta, body)
    }

    /// MIME type for a resource, from its extension.
    public static func mimeType(forPath path: String) -> String {
        path.lowercased().hasSuffix(".md") ? "text/markdown" : "text/plain"
    }
}
