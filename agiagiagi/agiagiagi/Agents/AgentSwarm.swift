//
//  AgentSwarm.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation
import SwiftUI

@Observable
final class AgentSwarm {
    var agentLogs: [AgentLog] = []
    var isRunning: Bool = false
    var progress: Double = 0.0
    var currentPhase: String = ""
    var retryCount: Int = 0
    let maxRetries = 1

    // Per-agent status tracking for the visualization
    var detectorStatus: AgentStatus = .spawned
    var translatorStatus: AgentStatus = .spawned
    var wizardStatus: AgentStatus = .spawned
    var evaluatorStatus: AgentStatus = .spawned

    private let knowledgeBase = KnowledgeBase.shared
    private let promptOptimizer = PromptOptimizer.shared

    @MainActor
    func analyze(imageData: Data, goal: String, userProfile: UserProfile, deviceHint: String? = nil) async -> SwarmResult {
        isRunning = true
        progress = 0.0
        agentLogs = []
        retryCount = 0
        currentPhase = "Initializing swarm"
        resetAgentStatuses()

        let logHandler: @Sendable (AgentLog) -> Void = { [unowned self] log in
            Task { @MainActor in
                self.appendLog(log)
            }
        }

        appendLog(AgentLog(agentName: "Swarm", status: .spawned, message: "Agent swarm initialized"))

        return await runSwarmCycle(
            imageData: imageData,
            goal: goal,
            userProfile: userProfile,
            deviceHint: deviceHint,
            logHandler: logHandler
        )
    }

    @MainActor
    private func runSwarmCycle(
        imageData: Data,
        goal: String,
        userProfile: UserProfile,
        deviceHint: String?,
        logHandler: @escaping @Sendable (AgentLog) -> Void
    ) async -> SwarmResult {
        // Step 1: Check KnowledgeBase
        currentPhase = "Checking knowledge base"
        progress = 0.05
        let keywords = extractKeywords(goal: goal, deviceHint: deviceHint)
        let similarEntries = knowledgeBase.findSimilar(
            deviceType: deviceHint ?? "unknown",
            keywords: keywords
        )
        let knowledgeContext: String? = similarEntries.isEmpty ? nil : knowledgeBase.contextSummary(for: similarEntries)

        if retryCount == 0 {
            if !similarEntries.isEmpty {
                appendLog(AgentLog(agentName: "Swarm", status: .working, message: "Found \(similarEntries.count) similar past analyses in knowledge base"))
            } else {
                appendLog(AgentLog(agentName: "Swarm", status: .working, message: "No similar panels in knowledge base, fresh analysis"))
            }
        }

        // Step 2: Spawn PanelDetector and Translator in parallel
        currentPhase = retryCount > 0 ? "Retrying detection (Self-Correction)" : "Detecting elements & translating text"
        progress = 0.15
        detectorStatus = .working
        translatorStatus = .working

        let detector = PanelDetectorAgent(logCallback: logHandler)
        let translator = TranslatorAgent(logCallback: logHandler)

        async let detectorOutput: Result<PanelAnalysis, Error> = {
            do {
                let result = try await detector.analyze(
                    imageData: imageData,
                    userProfile: userProfile,
                    deviceHint: deviceHint,
                    knowledgeContext: knowledgeContext
                )
                return .success(result)
            } catch {
                return .failure(error)
            }
        }()

        async let translatorOutput: Result<TranslationResult, Error> = {
            do {
                let result = try await translator.translate(
                    imageData: imageData,
                    userProfile: userProfile,
                    partialAnalysis: nil
                )
                return .success(result)
            } catch {
                return .failure(error)
            }
        }()

        let (detectorOutcome, translatorOutcome) = await (detectorOutput, translatorOutput)
        var detectorResult: PanelAnalysis?
        var translatorResult: TranslationResult?

        switch detectorOutcome {
        case .success(let result):
            detectorResult = result
            detectorStatus = .done
            progress = 0.35
        case .failure(let error):
            detectorStatus = .failed
            appendLog(AgentLog(agentName: PanelDetectorAgent.agentName, status: .failed, message: "Detection failed: \(error.localizedDescription)"))
        }

        switch translatorOutcome {
        case .success(let result):
            translatorResult = result
            translatorStatus = .done
            progress = 0.40
        case .failure(let error):
            translatorStatus = .failed
            appendLog(AgentLog(agentName: TranslatorAgent.agentName, status: .failed, message: "Translation failed: \(error.localizedDescription)"))
        }

        // Step 3: Merge results
        currentPhase = "Merging agent results"
        progress = 0.45
        if retryCount == 0 {
            appendLog(AgentLog(agentName: "Swarm", status: .working, message: "Merging detection and translation results"))
        }

        let mergedAnalysis = mergeResults(detector: detectorResult, translator: translatorResult)

        // Step 4: Spawn WizardAgent
        currentPhase = retryCount > 0 ? "Retrying wizard (Self-Correction)" : "Building action wizard"
        progress = 0.55
        wizardStatus = .working

        var wizardResult: ActionWizard?
        if let analysis = mergedAnalysis {
            let wizard = WizardAgent(logCallback: logHandler)
            do {
                wizardResult = try await wizard.buildWizard(
                    analysis: analysis,
                    goal: goal,
                    userProfile: userProfile,
                    knowledgeContext: knowledgeContext
                )
                wizardStatus = .done
                progress = 0.70
            } catch {
                wizardStatus = .failed
                appendLog(AgentLog(agentName: WizardAgent.agentName, status: .failed, message: "Wizard failed: \(error.localizedDescription)"))
            }
        }

        // Step 5: Spawn EvaluatorAgent
        currentPhase = "Evaluating quality"
        progress = 0.80
        evaluatorStatus = .working

        let evaluator = EvaluatorAgent(logCallback: logHandler)
        var evaluation: EvaluationResult?
        do {
            evaluation = try await evaluator.evaluate(
                analysis: mergedAnalysis,
                wizard: wizardResult,
                goal: goal
            )
            evaluatorStatus = .done
            progress = 0.90
        } catch {
            evaluatorStatus = .failed
            appendLog(AgentLog(agentName: EvaluatorAgent.agentName, status: .failed, message: "Evaluation failed: \(error.localizedDescription)"))
        }

        // --- SELF-CORRECTION LOGIC ---
        if let eval = evaluation, eval.qualityScore < 0.75, retryCount < maxRetries {
            retryCount += 1
            appendLog(AgentLog(agentName: "Swarm", status: .working, message: "Quality score \(String(format: "%.2f", eval.qualityScore)) is low. Triggering self-correction loop (Retry \(retryCount))."))
            
            // Apply improved prompts immediately for this retry cycle
            for (agentType, improvedPrompt) in eval.improvedPrompts {
                PromptOptimizer.shared.savePromptResult(
                    agentType: agentType,
                    prompt: improvedPrompt,
                    score: eval.qualityScore
                )
            }
            
            resetAgentStatuses()
            return await runSwarmCycle(
                imageData: imageData,
                goal: goal,
                userProfile: userProfile,
                deviceHint: deviceHint,
                logHandler: logHandler
            )
        }

        // Step 6: Save final prompt improvements
        if let eval = evaluation {
            for (agentType, improvedPrompt) in eval.improvedPrompts {
                promptOptimizer.savePromptResult(
                    agentType: agentType,
                    prompt: improvedPrompt,
                    score: eval.qualityScore
                )
            }
        }

        // Step 7: Save to KnowledgeBase
        if let analysis = mergedAnalysis {
            let entry = KnowledgeEntry(
                deviceType: analysis.panel.deviceFamily,
                keywords: keywords,
                panelAnalysis: analysis,
                qualityScore: evaluation?.qualityScore ?? 0.5
            )
            knowledgeBase.addEntry(entry)
        }

        // Complete
        currentPhase = "Complete"
        progress = 1.0
        isRunning = false

        let finalResult = SwarmResult(
            panelAnalysis: mergedAnalysis,
            actionWizard: wizardResult,
            agentLogs: agentLogs,
            qualityScore: evaluation?.qualityScore ?? 0.0,
            promptImprovements: evaluation?.improvements ?? [],
            knowledgeBaseHits: similarEntries.count
        )

        appendLog(AgentLog(agentName: "Swarm", status: .done, message: "Swarm complete. Final Quality: \(String(format: "%.2f", finalResult.qualityScore))"))

        return finalResult
    }

    // MARK: - Private Helpers

    @MainActor
    private func appendLog(_ log: AgentLog) {
        agentLogs.append(log)
    }

    @MainActor
    private func resetAgentStatuses() {
        detectorStatus = .spawned
        translatorStatus = .spawned
        wizardStatus = .spawned
        evaluatorStatus = .spawned
    }

    private func extractKeywords(goal: String, deviceHint: String?) -> [String] {
        var keywords = goal.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { $0.count > 3 }

        if let hint = deviceHint {
            keywords.append(hint.lowercased())
        }

        return keywords
    }

    private func mergeResults(detector: PanelAnalysis?, translator: TranslationResult?) -> PanelAnalysis? {
        guard let base = detector else { return nil }

        guard let trans = translator else { return base }

        // Enhance elements with translator's results
        let enhancedElements = base.elements.map { element -> PanelElement in
            if let translatedText = trans.elementTranslations[element.elementId] {
                // Create enhanced translations array
                var translations = element.translations
                let hasUserLangTranslation = translations.contains { $0.language != "original" }
                if !hasUserLangTranslation && !translatedText.isEmpty {
                    translations.append(Translation(language: "translated", text: translatedText))
                }
                return PanelElement(
                    elementId: element.elementId,
                    kind: element.kind,
                    bbox: element.bbox,
                    label: element.label,
                    translations: translations,
                    confidence: element.confidence,
                    evidence: element.evidence
                )
            }
            return element
        }

        return PanelAnalysis(
            panel: base.panel,
            elements: enhancedElements,
            globalConfidence: base.globalConfidence,
            warnings: base.warnings
        )
    }
}
