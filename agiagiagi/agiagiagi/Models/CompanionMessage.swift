//
//  CompanionMessage.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

// MARK: - Companion Mode

enum CompanionMode: String, CaseIterable {
    case literary
    case practical
    case accessibility

    var displayName: String {
        switch self {
        case .literary: return "Literary"
        case .practical: return "Practical"
        case .accessibility: return "Accessibility"
        }
    }

    var icon: String {
        switch self {
        case .literary: return "book.fill"
        case .practical: return "wrench.and.screwdriver.fill"
        case .accessibility: return "accessibility"
        }
    }

    var next: CompanionMode {
        switch self {
        case .literary: return .practical
        case .practical: return .accessibility
        case .accessibility: return .literary
        }
    }
}

// MARK: - Disco Elysium Skill Check Types

enum CheckDifficulty: String, CaseIterable {
    case trivial, easy, medium, challenging, heroic, legendary

    var displayName: String {
        rawValue.capitalized
    }

    var targetNumber: Int {
        switch self {
        case .trivial: return 6
        case .easy: return 8
        case .medium: return 10
        case .challenging: return 12
        case .heroic: return 14
        case .legendary: return 16
        }
    }
}

struct InnerVoiceLabel {
    let stat: CompanionStat
    let difficulty: CheckDifficulty
}

struct SkillCheck {
    let stat: CompanionStat
    let difficulty: CheckDifficulty
    let chance: Int // 0-100

    func rollResult() -> Bool {
        Int.random(in: 0..<100) < chance
    }

    func modifierBreakdown(statLevel: Int) -> [(String, Int)] {
        let base = statLevel
        let intuition = Int.random(in: 0...2)
        let complexity = -Int.random(in: 0...3)
        let target = difficulty.targetNumber
        return [
            ("Base", base),
            ("Intuition", intuition),
            ("Complexity", complexity),
            ("Target", target)
        ]
    }
}

// MARK: - Companion Message

struct CompanionMessage: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let role: Role
    let content: String
    let chips: [String]
    let qualityConfidence: Double   // output_quality_confidence
    let safetyConfidence: Double    // action_safety_confidence
    let riskLevel: String
    let sceneDescription: String
    let innerVoice: InnerVoiceLabel?
    let chipChecks: [String: SkillCheck]

    enum Role {
        case companion
        case user
        case system
    }

    static func companion(
        content: String,
        chips: [String] = [],
        qualityConfidence: Double = 0.5,
        safetyConfidence: Double = 0.8,
        riskLevel: String = "low",
        sceneDescription: String = "",
        innerVoice: InnerVoiceLabel? = nil,
        chipChecks: [String: SkillCheck] = [:]
    ) -> CompanionMessage {
        CompanionMessage(
            role: .companion,
            content: content,
            chips: chips,
            qualityConfidence: qualityConfidence,
            safetyConfidence: safetyConfidence,
            riskLevel: riskLevel,
            sceneDescription: sceneDescription,
            innerVoice: innerVoice,
            chipChecks: chipChecks
        )
    }

    static func user(_ content: String) -> CompanionMessage {
        CompanionMessage(
            role: .user,
            content: content,
            chips: [],
            qualityConfidence: 0,
            safetyConfidence: 1,
            riskLevel: "low",
            sceneDescription: "",
            innerVoice: nil,
            chipChecks: [:]
        )
    }

    /// Content with stat/skill bracket tags stripped out (e.g. "[INLAND EMPIRE]", "[VISUAL CALCULUS – Medium: 4]")
    var cleanedContent: String {
        // Strip patterns like [STAT_NAME], [STAT_NAME – Difficulty: N], [STAT_NAME: ...] etc.
        let pattern = "\\[(?:INLAND EMPIRE|ENCYCLOPEDIA|EMPATHY|VISUAL CALCULUS|ELECTROCHEMISTRY|RHETORIC|SHIVERS|CONCEPTUALIZATION)[^\\]]*\\]:?\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return content
        }
        return regex.stringByReplacingMatches(
            in: content,
            range: NSRange(content.startIndex..., in: content),
            withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func system(_ content: String) -> CompanionMessage {
        CompanionMessage(
            role: .system,
            content: content,
            chips: [],
            qualityConfidence: 0,
            safetyConfidence: 1,
            riskLevel: "low",
            sceneDescription: "",
            innerVoice: nil,
            chipChecks: [:]
        )
    }
}
