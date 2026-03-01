//
//  AgentLog.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

enum AgentStatus: String, Codable {
    case spawned
    case working
    case done
    case failed
}

struct AgentLog: Identifiable, Codable {
    let id: UUID
    let agentName: String
    let status: AgentStatus
    let message: String
    let timestamp: Date

    init(agentName: String, status: AgentStatus, message: String) {
        self.id = UUID()
        self.agentName = agentName
        self.status = status
        self.message = message
        self.timestamp = Date()
    }
}
