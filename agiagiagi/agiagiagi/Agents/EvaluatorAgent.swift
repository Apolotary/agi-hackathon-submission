//
//  EvaluatorAgent.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

struct EvaluationResult {
    let qualityScore: Double
    let issues: [String]
    let improvements: [String]
    let improvedPrompts: [String: String]  // agentType -> improvedPrompt
}

actor EvaluatorAgent {
    static let agentName = "Evaluator"

    private let api = MistralAPI.shared
    private let logCallback: @Sendable (AgentLog) -> Void

    init(logCallback: @escaping @Sendable (AgentLog) -> Void) {
        self.logCallback = logCallback
    }

    func evaluate(analysis: PanelAnalysis?, wizard: ActionWizard?, goal: String) async throws -> EvaluationResult {
        log(.spawned, "Initializing quality evaluation agent")

        var issues: [String] = []
        var improvements: [String] = []
        var score: Double = 1.0

        // --- Evaluate PanelAnalysis ---
        if let analysis = analysis {
            log(.working, "Evaluating panel analysis quality")

            // Check global confidence
            if analysis.globalConfidence < 0.65 {
                issues.append("Low global confidence: \(String(format: "%.2f", analysis.globalConfidence))")
                score -= 0.2
                improvements.append("Improve element detection prompt to be more specific about the device type")
            }

            // Check for empty elements
            if analysis.elements.isEmpty {
                issues.append("No elements detected")
                score -= 0.3
                improvements.append("Detection prompt should emphasize finding ALL visible elements")
            }

            // Check bounding box validity
            for element in analysis.elements {
                let bbox = element.bbox
                if bbox.x < 0 || bbox.y < 0 || bbox.width <= 0 || bbox.height <= 0 ||
                   bbox.x + bbox.width > 1.1 || bbox.y + bbox.height > 1.1 {
                    issues.append("Invalid bbox for \(element.elementId): out of bounds")
                    score -= 0.05
                }
            }

            // Check for excessive overlap
            let bboxes = analysis.elements.map { ($0.elementId, $0.bbox) }
            for i in 0..<bboxes.count {
                for j in (i+1)..<bboxes.count {
                    let overlap = computeOverlap(bboxes[i].1, bboxes[j].1)
                    if overlap > 0.8 {
                        issues.append("High overlap between \(bboxes[i].0) and \(bboxes[j].0): \(String(format: "%.0f%%", overlap * 100))")
                        score -= 0.05
                    }
                }
            }

            // Check element confidence distribution
            let lowConfidenceCount = analysis.elements.filter { $0.confidence < 0.6 }.count
            if lowConfidenceCount > analysis.elements.count / 2 {
                issues.append("\(lowConfidenceCount)/\(analysis.elements.count) elements have low confidence")
                score -= 0.1
                improvements.append("Many low-confidence detections suggest the image may be unclear or the prompt needs refinement")
            }
        } else {
            issues.append("No panel analysis available")
            score -= 0.5
        }

        // --- Evaluate ActionWizard ---
        if let wizard = wizard {
            log(.working, "Evaluating action wizard quality")

            // Check steps exist
            if wizard.steps.isEmpty {
                issues.append("No action steps generated")
                score -= 0.3
                improvements.append("Wizard prompt should always produce at least one step or a clear fallback")
            }

            // Check step ordering
            var prevStep = 0
            for step in wizard.steps {
                let stepNum = Int(step.stepId.replacingOccurrences(of: "step_", with: "")) ?? 0
                if stepNum <= prevStep && stepNum != 0 {
                    issues.append("Step ordering issue at \(step.stepId)")
                    score -= 0.05
                }
                prevStep = stepNum
            }

            // Check element references against analysis
            if let analysis = analysis {
                let validIds = Set(analysis.elements.map(\.elementId))
                for step in wizard.steps {
                    if let targetId = step.targetElementId, !targetId.isEmpty {
                        if !validIds.contains(targetId) {
                            issues.append("Step \(step.stepId) references unknown element: \(targetId)")
                            score -= 0.1
                            improvements.append("Wizard should only reference element IDs that exist in the analysis")
                        }
                    }
                }
            }

            // Check step confidence
            let lowConfSteps = wizard.steps.filter { $0.confidence < 0.6 }
            if !lowConfSteps.isEmpty {
                issues.append("\(lowConfSteps.count) steps have low confidence")
                score -= 0.05 * Double(lowConfSteps.count)
            }

            // Check fallbacks exist for low confidence
            if wizard.steps.contains(where: { $0.confidence < 0.6 }) && wizard.fallbacks.isEmpty {
                issues.append("Low confidence steps without fallbacks")
                score -= 0.1
                improvements.append("Add fallback suggestions when step confidence is below 0.60")
            }
        } else {
            issues.append("No action wizard available")
            score -= 0.3
        }

        // Clamp score
        score = max(0.0, min(1.0, score))

        // Generate improved prompts if quality is low
        var improvedPrompts: [String: String] = [:]
        if score < 0.7 {
            log(.working, "Quality below threshold, generating improved prompts")

            if analysis != nil && analysis!.elements.count < 3 {
                improvedPrompts[PanelDetectorAgent.agentName] = """
                You are an expert panel element detector. Be EXTREMELY thorough.
                Look for ALL elements including small buttons, LEDs, labels, icons.
                Even partially visible elements should be detected.
                Provide tight bounding boxes. Ensure no elements are missed.
                Previous issues: \(issues.joined(separator: "; "))
                """
            }

            if wizard != nil && (wizard!.steps.isEmpty || wizard!.steps.contains(where: { $0.confidence < 0.6 })) {
                improvedPrompts[WizardAgent.agentName] = """
                You are an expert action wizard. Generate clear, actionable steps.
                ALWAYS reference specific element IDs from the analysis.
                If uncertain about any step, provide a fallback.
                Previous issues: \(issues.joined(separator: "; "))
                """
            }
        }

        let issuesSummary = issues.isEmpty ? "no issues found" : "\(issues.count) issues"
        log(.done, "Quality score: \(String(format: "%.2f", score)), \(issuesSummary)")

        return EvaluationResult(
            qualityScore: score,
            issues: issues,
            improvements: improvements,
            improvedPrompts: improvedPrompts
        )
    }

    private func computeOverlap(_ a: BBox, _ b: BBox) -> Double {
        let x1 = max(a.x, b.x)
        let y1 = max(a.y, b.y)
        let x2 = min(a.x + a.width, b.x + b.width)
        let y2 = min(a.y + a.height, b.y + b.height)

        let intersectionArea = max(0, x2 - x1) * max(0, y2 - y1)
        let aArea = a.width * a.height
        let bArea = b.width * b.height
        let unionArea = aArea + bArea - intersectionArea

        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    private func log(_ status: AgentStatus, _ message: String) {
        let entry = AgentLog(agentName: Self.agentName, status: status, message: message)
        logCallback(entry)
    }
}
