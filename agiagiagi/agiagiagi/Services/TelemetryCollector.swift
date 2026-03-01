//
//  TelemetryCollector.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

/// Lightweight KPI telemetry for the embodied companion.
/// Logs events to console and maintains session-level counters.
@Observable
final class TelemetryCollector {
    static let shared = TelemetryCollector()

    // Session counters
    private(set) var tasksAttempted: Int = 0
    private(set) var tasksSucceeded: Int = 0
    private(set) var tasksFailed: Int = 0
    private(set) var promptsShown: Int = 0
    private(set) var promptsAccepted: Int = 0
    private(set) var promptsDismissed: Int = 0
    private(set) var whyTaps: Int = 0
    private(set) var highRiskConfirmations: Int = 0
    private(set) var highRiskRejections: Int = 0

    // Hazard tracking
    private(set) var falseHazardFlags: Int = 0   // user overrode a risk warning
    private(set) var missedHazardFlags: Int = 0  // failure after low-risk assessment

    // Timing
    private(set) var sessionStartTime: Date = Date()
    private(set) var firstArtifactTime: Date?

    // Event log (recent)
    private(set) var events: [TelemetryEvent] = []
    private let maxEvents = 200

    private init() {}

    // MARK: - KPI Computed Properties

    /// TaskSuccessVerified
    var taskSuccessRate: Double {
        guard tasksAttempted > 0 else { return 0 }
        return Double(tasksSucceeded) / Double(tasksAttempted)
    }

    /// TimeToFirstUsefulArtifact (seconds)
    var timeToFirstArtifact: TimeInterval? {
        guard let first = firstArtifactTime else { return nil }
        return first.timeIntervalSince(sessionStartTime)
    }

    /// PromptAcceptanceRate
    var promptAcceptanceRate: Double {
        let total = promptsAccepted + promptsDismissed
        guard total > 0 else { return 0 }
        return Double(promptsAccepted) / Double(total)
    }

    /// OverrideRate (inverse of acceptance)
    var overrideRate: Double {
        let total = promptsAccepted + promptsDismissed
        guard total > 0 else { return 0 }
        return Double(promptsDismissed) / Double(total)
    }

    /// FalseHazardRate — fraction of risk warnings that user overrode
    var falseHazardRate: Double {
        let riskTotal = highRiskConfirmations + highRiskRejections + falseHazardFlags
        guard riskTotal > 0 else { return 0 }
        return Double(falseHazardFlags) / Double(riskTotal)
    }

    /// MissedHazardRate — fraction of low-risk assessments that led to failures
    var missedHazardRate: Double {
        guard tasksAttempted > 0 else { return 0 }
        return Double(missedHazardFlags) / Double(tasksAttempted)
    }

    /// TrustCalibrationScore — higher is better calibrated (low false + missed hazard rates)
    var trustCalibrationScore: Double {
        1.0 - (falseHazardRate + missedHazardRate) / 2.0
    }

    // MARK: - Recording

    func recordSessionStart() {
        sessionStartTime = Date()
        firstArtifactTime = nil
        log(.sessionStart)
    }

    func recordPromptShown() {
        promptsShown += 1
        log(.promptShown)
    }

    func recordPromptAccepted(goal: String) {
        promptsAccepted += 1
        tasksAttempted += 1
        log(.promptAccepted, detail: goal)
    }

    func recordPromptDismissed() {
        promptsDismissed += 1
        log(.promptDismissed)
    }

    func recordArtifactGenerated(goal: String) {
        if firstArtifactTime == nil {
            firstArtifactTime = Date()
        }
        log(.artifactGenerated, detail: goal)
    }

    func recordTaskSuccess(goal: String) {
        tasksSucceeded += 1
        log(.taskSuccess, detail: goal)
    }

    func recordTaskFailure(goal: String, reason: String) {
        tasksFailed += 1
        log(.taskFailure, detail: "\(goal): \(reason)")
    }

    /// User tapped "Why?" for transparency
    func recordWhyTap() {
        whyTaps += 1
        log(.whyTap)
    }

    func recordHighRiskConfirmation(stepId: String) {
        highRiskConfirmations += 1
        log(.highRiskConfirmed, detail: stepId)
    }

    func recordHighRiskRejection(stepId: String) {
        highRiskRejections += 1
        log(.highRiskRejected, detail: stepId)
    }

    /// User overrode a risk warning (false hazard)
    func recordFalseHazard(detail: String) {
        falseHazardFlags += 1
        log(.falseHazard, detail: detail)
    }

    /// Failure occurred after a low-risk assessment (missed hazard)
    func recordMissedHazard(goal: String, riskLevel: String) {
        missedHazardFlags += 1
        log(.missedHazard, detail: "\(goal) [assessed=\(riskLevel)]")
    }

    func recordStateTransition(from: String, to: String) {
        log(.stateTransition, detail: "\(from) -> \(to)")
    }

    // MARK: - Internal

    private func log(_ kind: TelemetryEvent.Kind, detail: String = "") {
        let event = TelemetryEvent(kind: kind, detail: detail)
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        print("[Telemetry] \(kind.rawValue)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    func reset() {
        tasksAttempted = 0
        tasksSucceeded = 0
        tasksFailed = 0
        promptsShown = 0
        promptsAccepted = 0
        promptsDismissed = 0
        whyTaps = 0
        highRiskConfirmations = 0
        highRiskRejections = 0
        falseHazardFlags = 0
        missedHazardFlags = 0
        firstArtifactTime = nil
        events = []
        sessionStartTime = Date()
    }
}

struct TelemetryEvent: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let kind: Kind
    let detail: String

    enum Kind: String {
        case sessionStart = "session_start"
        case promptShown = "prompt_shown"
        case promptAccepted = "prompt_accepted"
        case promptDismissed = "prompt_dismissed"
        case artifactGenerated = "artifact_generated"
        case taskSuccess = "task_success"
        case taskFailure = "task_failure"
        case whyTap = "why_tap"
        case highRiskConfirmed = "high_risk_confirmed"
        case highRiskRejected = "high_risk_rejected"
        case falseHazard = "false_hazard"
        case missedHazard = "missed_hazard"
        case stateTransition = "state_transition"
    }
}
