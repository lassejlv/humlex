import Foundation

struct HumlexSkill: Identifiable, Hashable {
    let name: String
    let summary: String
    let content: String
    let sourcePath: String

    var id: String { "\(normalizedName)::\(sourcePath)" }
    var normalizedName: String { Self.normalize(name) }

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

struct HumlexSkillActivation {
    let activeSkills: [HumlexSkill]
    let missingSkillNames: [String]
    let systemPromptBlock: String?

    static let empty = HumlexSkillActivation(
        activeSkills: [],
        missingSkillNames: [],
        systemPromptBlock: nil
    )
}

enum HumlexSkillCatalog {
    private static let maxCharsPerSkill = 12_000
    private static let maxCharsTotal = 50_000

    static func activate(from userText: String, workingDirectory: String?) -> HumlexSkillActivation
    {
        let requestedSkillNames = requestedSkillNames(in: userText)
        guard !requestedSkillNames.isEmpty else { return .empty }

        let skills = loadSkills(workingDirectory: workingDirectory)
        guard !skills.isEmpty else {
            return HumlexSkillActivation(
                activeSkills: [],
                missingSkillNames: requestedSkillNames,
                systemPromptBlock: nil
            )
        }

        let (resolved, missing) = resolve(
            requestedSkillNames: requestedSkillNames,
            against: skills
        )
        let prompt = makeSystemPromptBlock(for: resolved)
        return HumlexSkillActivation(
            activeSkills: resolved,
            missingSkillNames: missing,
            systemPromptBlock: prompt
        )
    }

    static func availableSkills(workingDirectory: String?) -> [HumlexSkill] {
        loadSkills(workingDirectory: workingDirectory)
    }

    static func searchRoots(workingDirectory: String?) -> [String] {
        candidateRoots(workingDirectory: workingDirectory)
    }

    private static func requestedSkillNames(in text: String) -> [String] {
        let pattern = #"\$([A-Za-z0-9][A-Za-z0-9._-]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        )

        var requested: [String] = []
        var seen = Set<String>()
        for match in matches where match.numberOfRanges > 1 {
            let token = nsText.substring(with: match.range(at: 1))
            let normalized = HumlexSkill.normalize(token)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            requested.append(normalized)
        }
        return requested
    }

    private static func resolve(
        requestedSkillNames: [String],
        against availableSkills: [HumlexSkill]
    ) -> (resolved: [HumlexSkill], missing: [String]) {
        let byName = Dictionary(
            uniqueKeysWithValues: availableSkills.map { ($0.normalizedName, $0) })

        var resolved: [HumlexSkill] = []
        var resolvedIDs = Set<String>()
        var missing: [String] = []

        for requested in requestedSkillNames {
            if let exact = byName[requested] {
                if !resolvedIDs.contains(exact.id) {
                    resolved.append(exact)
                    resolvedIDs.insert(exact.id)
                }
                continue
            }

            if let fuzzy = availableSkills.first(where: {
                $0.normalizedName.contains(requested) || requested.contains($0.normalizedName)
            }) {
                if !resolvedIDs.contains(fuzzy.id) {
                    resolved.append(fuzzy)
                    resolvedIDs.insert(fuzzy.id)
                }
                continue
            }

            missing.append(requested)
        }

        return (resolved, missing)
    }

    private static func loadSkills(workingDirectory: String?) -> [HumlexSkill] {
        let fileManager = FileManager.default
        let dedupedRoots = candidateRoots(workingDirectory: workingDirectory)
        var skillByName: [String: HumlexSkill] = [:]

        for rootPath in dedupedRoots {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: rootPath, isDirectory: &isDirectory),
                isDirectory.boolValue
            else {
                continue
            }

            let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            guard
                let enumerator = fileManager.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
            else { continue }

            for case let fileURL as URL in enumerator {
                guard fileURL.lastPathComponent == "SKILL.md" else { continue }
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    continue
                }
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let name = extractSkillName(from: trimmed, fallbackURL: fileURL)
                let normalized = HumlexSkill.normalize(name)
                guard !normalized.isEmpty else { continue }

                if skillByName[normalized] != nil {
                    continue
                }

                let summary = extractSummary(from: trimmed)
                skillByName[normalized] = HumlexSkill(
                    name: name,
                    summary: summary,
                    content: trimmed,
                    sourcePath: fileURL.path
                )
            }
        }

        return skillByName.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func candidateRoots(workingDirectory: String?) -> [String] {
        let fileManager = FileManager.default
        var roots: [String] = []

        if let workingDirectory, !workingDirectory.isEmpty {
            roots.append((workingDirectory as NSString).appendingPathComponent(".humlex/skills"))
            roots.append((workingDirectory as NSString).appendingPathComponent(".skills"))
            roots.append((workingDirectory as NSString).appendingPathComponent("skills"))
        }

        let home = NSHomeDirectory()
        roots.append((home as NSString).appendingPathComponent(".humlex/skills"))
        roots.append((home as NSString).appendingPathComponent(".skills"))
        roots.append((home as NSString).appendingPathComponent(".codex/skills"))
        roots.append((home as NSString).appendingPathComponent(".agents/skills"))

        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
        {
            roots.append(
                appSupport
                    .appendingPathComponent("Humlex", isDirectory: true)
                    .appendingPathComponent("skills", isDirectory: true)
                    .path
            )
        }

        var dedupedRoots: [String] = []
        var seenRoots = Set<String>()
        for root in roots where seenRoots.insert(root).inserted {
            dedupedRoots.append(root)
        }
        return dedupedRoots
    }

    private static func extractSkillName(from content: String, fallbackURL: URL) -> String {
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return fallbackURL.deletingLastPathComponent().lastPathComponent
    }

    private static func extractSummary(from content: String) -> String {
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("#") { continue }
            return String(trimmed.prefix(140))
        }
        return ""
    }

    private static func makeSystemPromptBlock(for skills: [HumlexSkill]) -> String? {
        guard !skills.isEmpty else { return nil }

        var sections: [String] = [
            """
            Apply these Humlex skills requested by the user via $skill syntax.
            Follow them as task-specific instructions unless they conflict with higher-priority safety requirements.
            """
        ]

        var usedChars = 0
        var omittedCount = 0

        for skill in skills {
            let clippedContent = String(skill.content.prefix(maxCharsPerSkill))
            let available = maxCharsTotal - usedChars
            guard available > 0 else {
                omittedCount += 1
                continue
            }

            let finalContent: String
            if clippedContent.count > available {
                finalContent = String(clippedContent.prefix(available))
                omittedCount += 1
            } else {
                finalContent = clippedContent
            }

            usedChars += finalContent.count

            sections.append(
                """
                [Skill: \(skill.name)]
                Source: \(abbreviatePath(skill.sourcePath))
                \(finalContent)
                """
            )
        }

        if omittedCount > 0 {
            sections.append("Additional skill content omitted for prompt size limits.")
        }

        return sections.joined(separator: "\n\n")
    }

    private static func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
