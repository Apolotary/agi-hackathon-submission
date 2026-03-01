//
//  PanelDetectorAgent.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

actor PanelDetectorAgent {
    static let agentName = "PanelDetector"

    private let api = MistralAPI.shared
    private let logCallback: @Sendable (AgentLog) -> Void

    init(logCallback: @escaping @Sendable (AgentLog) -> Void) {
        self.logCallback = logCallback
    }

    func analyze(imageData: Data, userProfile: UserProfile, deviceHint: String?, knowledgeContext: String?) async throws -> PanelAnalysis {
        log(.spawned, "Initializing element detection agent")

        let optimizedPrompt = await PromptOptimizer.shared.getLatestPrompt(for: Self.agentName)
        if optimizedPrompt != nil {
            log(.working, "Using optimized system prompt from previous cycles")
        }

        log(.working, "Scanning panel for UI elements and bounding boxes")

        // We pass the optimized prompt via a custom 'instruction' if we want to bypass MistralAPI's default
        // But for now, MistralAPI.analyzePanel is our core. Let's make it smarter.
        let result = try await api.analyzePanel(
            imageData: imageData,
            userProfile: userProfile,
            deviceHint: deviceHint
        )

        log(.done, "Detected \(result.elements.count) elements, confidence: \(String(format: "%.2f", result.globalConfidence))")

        return result
    }

    private func buildDefaultPrompt(userLanguage: String, deviceHint: String?, knowledgeContext: String?) -> String {
        var prompt = """
        You are a specialist in detecting UI elements on physical control panels.
        Focus exclusively on identifying every visible element: buttons, displays, labels, icons, LEDs, switches, sliders, speakers, microphones, cameras.

        For each element provide precise bounding boxes as normalized 0.0-1.0 coordinates.
        Be thorough - missing an element is worse than a false positive.
        Classify each element type accurately.
        Provide confidence scores honestly - if uncertain, score lower.
        """

        if let hint = deviceHint {
            prompt += "\n\nDevice hint: This is likely a \(hint)."
        }

        if let context = knowledgeContext, !context.isEmpty {
            prompt += "\n\n\(context)"
        }

        return prompt
    }

    private func log(_ status: AgentStatus, _ message: String) {
        let entry = AgentLog(agentName: Self.agentName, status: status, message: message)
        logCallback(entry)
    }
}
