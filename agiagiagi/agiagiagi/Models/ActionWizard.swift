//
//  ActionWizard.swift
//  agiagiagi
//
//  Created by Bektur Ryskeldiev on 2026/02/28.
//

import Foundation

struct WizardStep: Codable, Identifiable {
    let stepId: String
    let instruction: String
    let targetElementId: String?
    let targetBbox: BBox?
    let requiresConfirmation: Bool
    let riskTags: [String]
    let confidence: Double

    var id: String { stepId }

    private enum DecodingKeys: String, CodingKey {
        case stepId = "step_id"
        case stepNumber
        case instruction
        case targetElementId = "target_element_id"
        case elementId
        case targetBbox = "target_bbox"
        case requiresConfirmation = "requires_confirmation"
        case riskTags = "risk_tags"
        case confidence
    }

    private enum EncodingKeys: String, CodingKey {
        case stepId = "step_id"
        case instruction
        case targetElementId = "target_element_id"
        case targetBbox = "target_bbox"
        case requiresConfirmation = "requires_confirmation"
        case riskTags = "risk_tags"
        case confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DecodingKeys.self)
        stepId = (try? container.decode(String.self, forKey: .stepId))
            ?? (try? container.decode(Int.self, forKey: .stepNumber).description)
            ?? UUID().uuidString
        instruction = (try? container.decode(String.self, forKey: .instruction)) ?? ""
        targetElementId = (try? container.decode(String.self, forKey: .targetElementId))
            ?? (try? container.decode(String.self, forKey: .elementId))
        targetBbox = try? container.decode(BBox.self, forKey: .targetBbox)
        requiresConfirmation = (try? container.decode(Bool.self, forKey: .requiresConfirmation)) ?? false
        riskTags = (try? container.decode([String].self, forKey: .riskTags)) ?? []
        confidence = (try? container.decode(Double.self, forKey: .confidence)) ?? 0.5
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)
        try container.encode(stepId, forKey: .stepId)
        try container.encode(instruction, forKey: .instruction)
        try container.encodeIfPresent(targetElementId, forKey: .targetElementId)
        try container.encodeIfPresent(targetBbox, forKey: .targetBbox)
        try container.encode(requiresConfirmation, forKey: .requiresConfirmation)
        try container.encode(riskTags, forKey: .riskTags)
        try container.encode(confidence, forKey: .confidence)
    }
}

struct WizardFallback: Codable {
    let reason: String
    let suggestion: String
}

struct ActionWizard: Codable {
    let goal: String
    let riskTier: String
    let requiresConfirmation: Bool
    let steps: [WizardStep]
    let fallbacks: [WizardFallback]

    private enum DecodingKeys: String, CodingKey {
        case goal
        case riskTier = "risk_tier"
        case riskTierCamel = "riskTier"
        case requiresConfirmation = "requires_confirmation"
        case requiresConfirmationCamel = "requiresConfirmation"
        case steps
        case fallbacks
    }

    private enum EncodingKeys: String, CodingKey {
        case goal
        case riskTier = "risk_tier"
        case requiresConfirmation = "requires_confirmation"
        case steps
        case fallbacks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DecodingKeys.self)
        goal = (try? container.decode(String.self, forKey: .goal)) ?? ""
        riskTier = (try? container.decode(String.self, forKey: .riskTier))
            ?? (try? container.decode(String.self, forKey: .riskTierCamel))
            ?? "low"
        requiresConfirmation = (try? container.decode(Bool.self, forKey: .requiresConfirmation))
            ?? (try? container.decode(Bool.self, forKey: .requiresConfirmationCamel))
            ?? false
        steps = (try? container.decode([WizardStep].self, forKey: .steps)) ?? []
        fallbacks = (try? container.decode([WizardFallback].self, forKey: .fallbacks)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)
        try container.encode(goal, forKey: .goal)
        try container.encode(riskTier, forKey: .riskTier)
        try container.encode(requiresConfirmation, forKey: .requiresConfirmation)
        try container.encode(steps, forKey: .steps)
        try container.encode(fallbacks, forKey: .fallbacks)
    }
}
