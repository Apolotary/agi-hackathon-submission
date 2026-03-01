//
//  WizardAgent.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

actor WizardAgent {
    static let agentName = "Wizard"

    private let api = MistralAPI.shared
    private let logCallback: @Sendable (AgentLog) -> Void

    init(logCallback: @escaping @Sendable (AgentLog) -> Void) {
        self.logCallback = logCallback
    }

    func buildWizard(analysis: PanelAnalysis, goal: String, userProfile: UserProfile, knowledgeContext: String?) async throws -> ActionWizard {
        log(.spawned, "Initializing action wizard for goal: \(goal)")

        let optimizedPrompt = await PromptOptimizer.shared.getLatestPrompt(for: Self.agentName)
        if optimizedPrompt != nil {
            log(.working, "Using optimized wizard instructions from evaluator")
        }

        let riskTier = classifyRisk(goal: goal)
        log(.working, "Generating \(riskTier)-risk action steps referencing \(analysis.elements.count) elements")

        let wizard = try await api.buildWizard(
            analysis: analysis,
            goal: goal,
            riskTier: riskTier,
            userProfile: userProfile
        )

        log(.done, "Generated \(wizard.steps.count) steps, risk tier: \(wizard.riskTier)")

        return wizard
    }

    private func classifyRisk(goal: String) -> String {
        let lower = goal.lowercased()
        if lower.contains("unlock") || lower.contains("open door") || lower.contains("security") {
            return "high"
        } else if lower.contains("call") || lower.contains("talk") || lower.contains("communicate") || lower.contains("front desk") {
            return "medium"
        } else {
            return "low"
        }
    }

    private func log(_ status: AgentStatus, _ message: String) {
        let entry = AgentLog(agentName: Self.agentName, status: status, message: message)
        logCallback(entry)
    }
}
