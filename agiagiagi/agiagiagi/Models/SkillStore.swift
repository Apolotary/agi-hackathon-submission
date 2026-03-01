//
//  SkillStore.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation
import SwiftUI

struct SavedSkill: Codable, Identifiable {
    let id: UUID
    let goal: String              // chip text / user prompt that created it
    let html: String              // the full validated HTML artifact
    let sceneDescription: String  // what was on camera when saved
    let timestamp: Date
    var useCount: Int             // how many times recalled

    init(goal: String, html: String, sceneDescription: String) {
        self.id = UUID()
        self.goal = goal
        self.html = html
        self.sceneDescription = sceneDescription
        self.timestamp = Date()
        self.useCount = 0
    }
}

@Observable
final class SkillStore {
    static let shared = SkillStore()

    var skills: [SavedSkill] = []

    private static let maxSkills = 30

    private static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("saved_skills.json")
    }

    private init() {
        load()
    }

    func save(_ skill: SavedSkill) {
        // Don't save duplicates (same goal text)
        if let idx = skills.firstIndex(where: { $0.goal.lowercased() == skill.goal.lowercased() }) {
            skills[idx] = skill // overwrite with newer version
        } else {
            skills.insert(skill, at: 0)
        }
        if skills.count > Self.maxSkills {
            skills = Array(skills.prefix(Self.maxSkills))
        }
        persist()
    }

    func recordUse(_ skillId: UUID) {
        if let idx = skills.firstIndex(where: { $0.id == skillId }) {
            skills[idx].useCount += 1
            persist()
        }
    }

    func remove(at offsets: IndexSet) {
        skills.remove(atOffsets: offsets)
        persist()
    }

    func removeById(_ id: UUID) {
        skills.removeAll { $0.id == id }
        persist()
    }

    func clearAll() {
        skills.removeAll()
        persist()
    }

    /// Returns up to `limit` saved skills that are contextually relevant to the current scene.
    /// Matches by keyword overlap between scene description and the skill's goal/sceneDescription.
    func relevantSkills(for sceneDescription: String, limit: Int = 2) -> [SavedSkill] {
        guard !skills.isEmpty else { return [] }

        let sceneWords = Set(
            sceneDescription.lowercased()
                .components(separatedBy: .alphanumerics.inverted)
                .filter { $0.count > 2 }
        )

        // Score each skill by keyword overlap + recency + use count
        let scored: [(SavedSkill, Double)] = skills.map { skill in
            let goalWords = Set(
                skill.goal.lowercased()
                    .components(separatedBy: .alphanumerics.inverted)
                    .filter { $0.count > 2 }
            )
            let skillSceneWords = Set(
                skill.sceneDescription.lowercased()
                    .components(separatedBy: .alphanumerics.inverted)
                    .filter { $0.count > 2 }
            )

            let goalOverlap = Double(sceneWords.intersection(goalWords).count)
            let sceneOverlap = Double(sceneWords.intersection(skillSceneWords).count)
            let recency = max(0, 1.0 - skill.timestamp.timeIntervalSinceNow / -86400.0) // decay over 24h
            let popularity = min(Double(skill.useCount) * 0.2, 1.0)

            let score = goalOverlap * 2.0 + sceneOverlap + recency * 0.5 + popularity
            return (skill, score)
        }

        // Sort by score descending, take top `limit`
        let sorted = scored.sorted { $0.1 > $1.1 }
        return Array(sorted.prefix(limit).map(\.0))
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(skills)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            print("[SkillStore] Failed to save: \(error)")
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: Self.fileURL)
            skills = try JSONDecoder().decode([SavedSkill].self, from: data)
        } catch {
            skills = []
        }
    }
}
