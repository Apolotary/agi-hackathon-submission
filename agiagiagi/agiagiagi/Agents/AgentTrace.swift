//
//  AgentTrace.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

struct TraceEvent: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let agent: String      // e.g. "Vision", "Artifact", "TTS"
    let model: String      // e.g. "mistral-small-latest"
    let action: String     // e.g. "companionObserve", "generateArtifact"
    let status: TraceStatus
    let durationMs: Int?   // nil if still running
    let detail: String     // short detail like "scene: messy desk"

    enum TraceStatus: String {
        case started = "started"
        case completed = "completed"
        case failed = "failed"
    }
}

@Observable
final class AgentTraceCollector {
    static let shared = AgentTraceCollector()

    var events: [TraceEvent] = []
    var isVisible = false
    var showJSON = false
    var lastObservationJSON: String?
    var lastArtifactJSON: String?

    // API call stats
    var totalAPICalls = 0
    var sessionStartTime = Date()

    private let maxEvents = 30

    private init() {}

    func log(agent: String, model: String, action: String, status: TraceEvent.TraceStatus, durationMs: Int? = nil, detail: String = "") {
        let event = TraceEvent(
            agent: agent,
            model: model,
            action: action,
            status: status,
            durationMs: durationMs,
            detail: detail
        )
        Task { @MainActor in
            self.events.append(event)
            if status == .completed || status == .started {
                self.totalAPICalls += 1
            }
            if self.events.count > self.maxEvents {
                self.events.removeFirst(self.events.count - self.maxEvents)
            }
        }
    }

    func clear() {
        events.removeAll()
    }
}
