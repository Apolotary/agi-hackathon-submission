//
//  ProactivePolicyEngine.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

/// Gates proactive companion prompts based on safety, budget, cooldown, and interrupt cost.
struct ProactivePolicyEngine {
    // Thresholds
    var safetyThreshold: Double = 0.6
    var interruptCostThreshold: Double = 0.5
    var cooldownSeconds: TimeInterval = 15
    var maxPromptsPerMinute: Int = 4

    // Tracking state
    private(set) var promptTimestamps: [Date] = []
    private(set) var lastDismissalTime: Date = .distantPast
    private(set) var dismissalCount: Int = 0
    private(set) var acceptanceCount: Int = 0

    /// Override rate: fraction of proactive prompts dismissed by user
    var overrideRate: Double {
        let total = dismissalCount + acceptanceCount
        guard total > 0 else { return 0 }
        return Double(dismissalCount) / Double(total)
    }

    /// Whether a proactive prompt is currently allowed
    func shouldPrompt(
        safetyConfidence: Double,
        riskLevel: String,
        hasPreConsent: Bool = false
    ) -> Bool {
        // Safety gate
        guard safetyConfidence >= safetyThreshold else { return false }

        // Risk gate: no high-risk proactive prompts without pre-consent
        if riskLevel == "high" && !hasPreConsent { return false }

        // Cooldown after dismissal
        let cooldownElapsed = Date().timeIntervalSince(lastDismissalTime) >= cooldownSeconds
        guard cooldownElapsed else { return false }

        // Budget: max prompts per minute
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        let recentCount = promptTimestamps.filter { $0 > oneMinuteAgo }.count
        guard recentCount < maxPromptsPerMinute else { return false }

        // Auto-throttle: increase cooldown when override rate is high
        if overrideRate > 0.5 {
            let extendedCooldown = cooldownSeconds * 2
            let extendedElapsed = Date().timeIntervalSince(lastDismissalTime) >= extendedCooldown
            guard extendedElapsed else { return false }
        }

        return true
    }

    /// Record that a proactive prompt was shown
    mutating func recordPromptShown() {
        promptTimestamps.append(Date())
        // Trim old timestamps (older than 2 minutes)
        let cutoff = Date().addingTimeInterval(-120)
        promptTimestamps.removeAll { $0 < cutoff }
    }

    /// Record that the user accepted a proactive prompt
    mutating func recordAcceptance() {
        acceptanceCount += 1
    }

    /// Record that the user dismissed/ignored a proactive prompt
    mutating func recordDismissal() {
        dismissalCount += 1
        lastDismissalTime = Date()
    }

    /// Reset tracking (e.g., on new session)
    mutating func reset() {
        promptTimestamps = []
        lastDismissalTime = .distantPast
        dismissalCount = 0
        acceptanceCount = 0
    }
}
