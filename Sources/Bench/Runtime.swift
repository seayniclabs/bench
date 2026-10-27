import BenchCore
import Foundation
import MCP

/// The path of the running binary, as the kernel reports it. Bundle.main is not used:
/// for a command-line binary it does not reliably point at the executable.
func benchExecutableURL() -> URL? {
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)
    var buffer = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buffer, &size) == 0 else { return nil }
    return URL(fileURLWithPath: String(cString: buffer))
}

/// The skills this process serves. Loaded once, on first use.
enum ServerSkills {
    static let all: [BenchSkill] = BenchSkills.load(
        from: BenchSkills.directory(env: ProcessInfo.processInfo.environment, executable: benchExecutableURL())
    )

    /// Prompt text: the SKILL.md body, plus the list of its supporting files as resources.
    static func promptText(_ skill: BenchSkill) -> String {
        guard !skill.supportingFiles.isEmpty else { return skill.body }
        let links = skill.supportingFiles.map { "- \(BenchSkills.uri(skill: skill.name, path: $0))" }
        return skill.body + "\n\n---\nSupporting files for this skill (MCP resources):\n" + links.joined(separator: "\n")
    }

    /// Every served file, keyed by its skill:// URI.
    static let resourceIndex: [String: (text: String, mimeType: String)] = {
        var index: [String: (text: String, mimeType: String)] = [:]
        for skill in all {
            index[BenchSkills.uri(skill: skill.name)] = (skill.rawText, "text/markdown")
            let folder = BenchSkills.directory(env: ProcessInfo.processInfo.environment, executable: benchExecutableURL())?
                .appendingPathComponent(skill.name)
            for path in skill.supportingFiles {
                guard let folder, let text = try? String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8) else {
                    continue
                }
                index[BenchSkills.uri(skill: skill.name, path: path)] = (text, BenchSkills.mimeType(forPath: path))
            }
        }
        return index
    }()
}

/// Prompts/list, prompts/get, resources/list and resources/read, all from the skills folder.
func registerSkillHandlers(on server: Server) async {
    await server.withMethodHandler(ListPrompts.self) { _ in
        .init(prompts: ServerSkills.all.map { Prompt(name: $0.name, description: $0.description) })
    }

    await server.withMethodHandler(GetPrompt.self) { params in
        guard let skill = ServerSkills.all.first(where: { $0.name == params.name }) else {
            throw MCPError.invalidParams("Unknown prompt '\(params.name)'. Call prompts/list for the skill names.")
        }
        return .init(
            description: skill.description,
            messages: [.user(.text(text: ServerSkills.promptText(skill)))]
        )
    }

    await server.withMethodHandler(ListResources.self) { _ in
        .init(resources: ServerSkills.resourceIndex.keys.sorted().map { uri in
            let entry = ServerSkills.resourceIndex[uri]
            return Resource(name: String(uri.dropFirst("skill://bench/".count)), uri: uri, mimeType: entry?.mimeType)
        })
    }

    await server.withMethodHandler(ReadResource.self) { params in
        guard let entry = ServerSkills.resourceIndex[params.uri] else {
            throw MCPError.invalidParams("Unknown resource '\(params.uri)'. Call resources/list for the URIs.")
        }
        return .init(contents: [.text(entry.text, uri: params.uri, mimeType: entry.mimeType)])
    }
}
