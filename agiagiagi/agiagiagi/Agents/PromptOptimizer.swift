//
//  PromptOptimizer.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

struct PromptVersion: Codable, Identifiable {
    let id: UUID
    let agentType: String
    let prompt: String
    let score: Double
    let timestamp: Date

    init(agentType: String, prompt: String, score: Double) {
        self.id = UUID()
        self.agentType = agentType
        self.prompt = prompt
        self.score = score
        self.timestamp = Date()
    }
}

final class PromptOptimizer {
    static let shared = PromptOptimizer()

    private var versions: [PromptVersion] = []
    private let maxVersionsPerAgent = 10

    private static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("prompt_versions.json")
    }

    private init() {
        load()
    }

    func getLatestPrompt(for agentType: String) -> String? {
        versions
            .filter { $0.agentType == agentType }
            .sorted { $0.score > $1.score }
            .first?
            .prompt
    }

    func getBestScore(for agentType: String) -> Double? {
        versions
            .filter { $0.agentType == agentType }
            .map(\.score)
            .max()
    }

    func savePromptResult(agentType: String, prompt: String, score: Double) {
        let version = PromptVersion(agentType: agentType, prompt: prompt, score: score)
        versions.append(version)

        // Prune: keep only top N per agent type
        let grouped = Dictionary(grouping: versions) { $0.agentType }
        versions = grouped.flatMap { (_, group) in
            group.sorted { $0.score > $1.score }.prefix(maxVersionsPerAgent)
        }

        save()
    }

    func allVersions(for agentType: String) -> [PromptVersion] {
        versions
            .filter { $0.agentType == agentType }
            .sorted { $0.score > $1.score }
    }

    /// Summary stats for UI display
    var totalVersions: Int { versions.count }

    var agentTypes: [String] {
        Array(Set(versions.map(\.agentType))).sorted()
    }

    func versionCount(for agentType: String) -> Int {
        versions.filter { $0.agentType == agentType }.count
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(versions)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            print("[PromptOptimizer] Failed to save: \(error)")
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: Self.fileURL)
            versions = try JSONDecoder().decode([PromptVersion].self, from: data)
        } catch {
            versions = []
        }
    }
}
