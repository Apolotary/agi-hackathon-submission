//
//  SwarmResult.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

struct SwarmResult {
    var panelAnalysis: PanelAnalysis?
    var actionWizard: ActionWizard?
    var agentLogs: [AgentLog]
    var qualityScore: Double
    var promptImprovements: [String]
    var knowledgeBaseHits: Int
}
