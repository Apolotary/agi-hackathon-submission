//
//  SceneSession.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

/// Tracks in-scene state so follow-up artifact generations are contextual,
/// not repetitive. Reset when a new photo is captured.
struct SceneSession {
    var currentGoal: String = ""
    // Event IDs are prefixed:
    // goal:<text>, step:<id>
    var actionsAttempted: [String] = []
    var actionsSucceeded: [String] = []
    var rejections: [String] = []
    var artifactsGenerated: Int = 0
    var recentArtifactFormats: [String] = [] // Track which formats were used recently

    mutating func recordArtifactFormat(_ goal: String) {
        let lower = goal.lowercased()
        var format = "other"
        if lower.contains("card") || lower.contains("collect") || lower.contains("mint") { format = "collectible card" }
        else if lower.contains("talk") || lower.contains("dialogue") || lower.contains("interview") || lower.contains("interrogate") { format = "dialogue" }
        else if lower.contains("map") || lower.contains("diagram") || lower.contains("layout") { format = "visual map" }
        else if lower.contains("spec") || lower.contains("identify") || lower.contains("id ") { format = "spec sheet" }
        else if lower.contains("story") || lower.contains("narrate") || lower.contains("lore") || lower.contains("autobiography") { format = "narrative" }
        else if lower.contains("chart") || lower.contains("compare") || lower.contains("rate") || lower.contains("score") { format = "comparison" }
        else if lower.contains("timeline") || lower.contains("history") || lower.contains("evolution") { format = "timeline" }
        else if lower.contains("bestiary") || lower.contains("creature") || lower.contains("log") { format = "bestiary" }
        else if lower.contains("quiz") || lower.contains("trivia") || lower.contains("flashcard") { format = "quiz" }
        else if lower.contains("mood") || lower.contains("vibe") || lower.contains("palette") || lower.contains("aesthetic") { format = "mood palette" }
        else if lower.contains("roast") || lower.contains("review") || lower.contains("critique") { format = "review" }
        else if lower.contains("tier") || lower.contains("rank") { format = "tier list" }
        else if lower.contains("blueprint") || lower.contains("schematic") || lower.contains("internal") { format = "blueprint" }
        else if lower.contains("battle") || lower.contains("versus") || lower.contains("vs") { format = "vs battle" }
        else if lower.contains("simulat") || lower.contains("demo") || lower.contains("physics") { format = "simulation" }
        else if lower.contains("poem") || lower.contains("haiku") || lower.contains("ode") { format = "poem" }
        else if lower.contains("recipe") || lower.contains("ingredient") { format = "recipe" }
        else if lower.contains("guide") || lower.contains("step") || lower.contains("explain") { format = "guide" }
        else if lower.contains("translat") || lower.contains("read text") { format = "translation" }
        else if lower.contains("deep dive") || lower.contains("learn more") { format = "deep dive" }

        if !recentArtifactFormats.contains(format) {
            recentArtifactFormats.append(format)
        }
        // Keep last 10
        if recentArtifactFormats.count > 10 {
            recentArtifactFormats.removeFirst()
        }
    }

    var successCount: Int { completedSteps.count }
    var failureCount: Int {
        let unresolvedGoals = max(0, attemptedGoals.count - completedGoals.count)
        return unresolvedGoals + failedSteps.count
    }

    var attemptedGoals: [String] {
        actionsAttempted
            .filter { $0.hasPrefix("goal:") }
            .map { String($0.dropFirst(5)) }
    }

    var completedGoals: [String] {
        actionsSucceeded
            .filter { $0.hasPrefix("goal:") }
            .map { String($0.dropFirst(5)) }
    }

    var completedSteps: [String] {
        actionsSucceeded
            .filter { $0.hasPrefix("step:") }
            .map { String($0.dropFirst(5)) }
    }

    var failedSteps: [String] {
        rejections
            .filter { $0.hasPrefix("step:") }
            .map { String($0.dropFirst(5)) }
    }

    mutating func recordAttempt(_ action: String) {
        if !actionsAttempted.contains(action) {
            actionsAttempted.append(action)
        }
    }

    mutating func recordSuccess(_ action: String) {
        if !actionsSucceeded.contains(action) {
            actionsSucceeded.append(action)
        }
    }

    mutating func recordRejection(_ action: String) {
        if !rejections.contains(action) {
            rejections.append(action)
        }
    }

    mutating func recordGoalAttempt(_ goal: String) {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordAttempt("goal:\(trimmed)")
    }

    mutating func recordGoalSuccess(_ goal: String) {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordAttempt("goal:\(trimmed)")
        recordSuccess("goal:\(trimmed)")
    }

    mutating func recordStepSuccess(_ stepId: String) {
        let trimmed = stepId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordAttempt("step:\(trimmed)")
        recordSuccess("step:\(trimmed)")
    }

    mutating func recordStepFailure(_ stepId: String) {
        let trimmed = stepId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordAttempt("step:\(trimmed)")
        recordRejection("step:\(trimmed)")
    }

    mutating func reset() {
        currentGoal = ""
        actionsAttempted = []
        actionsSucceeded = []
        rejections = []
        artifactsGenerated = 0
        // Don't reset recentArtifactFormats — variety should persist across scenes
    }
}
