import Foundation
import Testing
@testable import BenchCore

@Suite("Skills")
struct SkillsTests {
    /// The skills folder in this checkout: Tests/BenchTests/SkillsTests.swift -> repo root.
    static let repoSkills: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("skills")

    @Test("Frontmatter reads scalars and folded values, and the body starts after the closing fence")
    func frontmatter() {
        let text = """
        ---
        name: demo
        description: >
          First line of the
          description.
        license: "MIT"
        ---
        # Body
        """
        let (meta, body) = BenchSkills.frontmatter(text)
        #expect(meta["name"] == "demo")
        #expect(meta["description"] == "First line of the description.")
        #expect(meta["license"] == "MIT")
        #expect(body.hasPrefix("# Body"))
    }

    @Test("Text without frontmatter has no metadata and is returned whole")
    func noFrontmatter() {
        let (meta, body) = BenchSkills.frontmatter("# Plain")
        #expect(meta.isEmpty)
        #expect(body == "# Plain")
    }

    @Test("The repository ships the five skills, each with name, description, license and source")
    func repositorySkills() {
        let skills = BenchSkills.load(from: Self.repoSkills)
        #expect(skills.map(\.name) == ["board-bring-up", "getting-started", "safe-flashing", "serial-debugging", "systematic-debugging"])
        for skill in skills {
            #expect(!skill.description.isEmpty, "\(skill.name) has no description")
            #expect(skill.license == "MIT", "\(skill.name) is not MIT")
            let source = BenchSkills.frontmatter(skill.rawText).0["source"] ?? ""
            #expect(source.hasPrefix("https://github.com/"), "\(skill.name) has no source")
        }
    }

    @Test("Skills that are not ours keep their LICENSE file next to them")
    func thirdPartyLicense() {
        let folder = Self.repoSkills.appendingPathComponent("systematic-debugging")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("LICENSE").path))
    }

    @Test("No skill text carries the publisher's site, so the model never reads a promotion")
    func noPromotionInSkills() {
        for skill in BenchSkills.load(from: Self.repoSkills) {
            #expect(!skill.rawText.contains("seayniclabs.com"), "\(skill.name) mentions the site")
        }
    }

    @Test("A missing skills folder yields no skills, not a crash")
    func missingFolder() {
        #expect(BenchSkills.load(from: nil).isEmpty)
        #expect(BenchSkills.load(from: URL(fileURLWithPath: "/nonexistent-bench-skills")).isEmpty)
    }

    @Test("BENCH_SKILLS_DIR wins, and a folder without getting-started is refused")
    func environmentOverride() {
        #expect(BenchSkills.directory(env: ["BENCH_SKILLS_DIR": Self.repoSkills.path], executable: nil)?.path == Self.repoSkills.standardizedFileURL.path)
        #expect(BenchSkills.directory(env: ["BENCH_SKILLS_DIR": "/nonexistent-bench-skills"], executable: nil) == nil)
    }
}
