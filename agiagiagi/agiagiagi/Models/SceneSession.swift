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
    }
}
