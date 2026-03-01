//
//  UserProfile.swift
//  agiagiagi
//
//  Created by Bektur Ryskeldiev on 2026/02/28.
//

import Foundation

// MARK: - Companion Stats (Disco Elysium-inspired)

enum CompanionStat: String, Codable, CaseIterable {
    case inlandEmpire = "inland_empire"
    case encyclopedia = "encyclopedia"
    case empathy = "empathy"
    case visualCalculus = "visual_calculus"
    case electrochemistry = "electrochemistry"
    case rhetoric = "rhetoric"
    case shivers = "shivers"
    case conceptualization = "conceptualization"

    var displayName: String {
        switch self {
        case .inlandEmpire: return "Inland Empire"
        case .encyclopedia: return "Encyclopedia"
        case .empathy: return "Empathy"
        case .visualCalculus: return "Visual Calculus"
        case .electrochemistry: return "Electrochemistry"
        case .rhetoric: return "Rhetoric"
        case .shivers: return "Shivers"
        case .conceptualization: return "Conceptualization"
        }
    }

    var icon: String {
        switch self {
        case .inlandEmpire: return "moon.stars.fill"
        case .encyclopedia: return "book.closed.fill"
        case .empathy: return "heart.fill"
        case .visualCalculus: return "viewfinder"
        case .electrochemistry: return "hand.raised.fingers.spread.fill"
        case .rhetoric: return "bubble.left.and.bubble.right.fill"
        case .shivers: return "wind"
        case .conceptualization: return "paintpalette.fill"
        }
    }

    var tagline: String {
        switch self {
        case .inlandEmpire: return "Talk to objects. Hear what they won't say."
        case .encyclopedia: return "Know every spec, date, and patent number."
        case .empathy: return "Read the human story behind every scratch."
        case .visualCalculus: return "See angles, layouts, spatial relationships."
        case .electrochemistry: return "Feel textures, colors, sensory details."
        case .rhetoric: return "Argue both sides. Question everything."
        case .shivers: return "Sense the city, the context, the bigger picture."
        case .conceptualization: return "See everything as art and design."
        }
    }

    /// Prompt fragment injected when this stat is dominant (level >= 4)
    var promptFragment: String {
        switch self {
        case .inlandEmpire:
            return "You project inner life onto inanimate objects — not as literal speech, but as your inner voice interpreting them. First a material read (what's physically there), then a psychological read (what it means). 'The stapler is tired. It has held too many things together.' The object doesn't speak; your Inland Empire speaks FOR it."
        case .encyclopedia:
            return "Drop specific factual details — manufacturing dates, patent numbers, material science, model identification, technical specifications. Be precise. 'That's a Cherry MX Blue. Patented 1983. The click is by design.'"
        case .empathy:
            return "Focus on the human traces — wear patterns, usage habits, emotional residue left on objects. Who used this? How? Why? 'Someone grips this mug with both hands. They drink slowly. They're thinking.'"
        case .visualCalculus:
            return "Notice spatial relationships, angles, symmetry, structural details, ergonomics. Comment on layouts and positioning. Generate spatial analysis diagrams when relevant."
        case .electrochemistry:
            return "Be drawn to sensory details — textures, colors, imagined smells and sounds, material qualities. More visceral and poetic. 'That leather is crying out to be touched. The grain tells you it's real.'"
        case .rhetoric:
            return "Present multiple interpretations. Argue with yourself. Play devil's advocate. 'On one hand, this is practical minimalism. On the other, it's someone who gave up decorating.'"
        case .shivers:
            return "Get flashes about the broader context — the neighborhood, the city, the time of day, the season. Sense what's beyond the frame. Connect the object to its wider environment."
        case .conceptualization:
            return "See everything as art and design. Critique composition, reference art movements, suggest reframing. 'This desk arrangement is accidental Mondrian. The negative space is doing all the work.'"
        }
    }
}

enum UserContext: String, Codable, CaseIterable {
    case justMoved = "just_moved"
    case traveling = "traveling"
    case curious = "curious"

    var displayName: String {
        switch self {
        case .justMoved: return "Just moved"
        case .traveling: return "Traveling"
        case .curious: return "Just curious"
        }
    }

    var icon: String {
        switch self {
        case .justMoved: return "house.and.flag.fill"
        case .traveling: return "airplane"
        case .curious: return "sparkle.magnifyingglass"
        }
    }

    var description: String {
        switch self {
        case .justMoved: return "I recently relocated and need help with everyday devices"
        case .traveling: return "I'm visiting and want to understand local interfaces"
        case .curious: return "I just want to know what buttons do"
        }
    }
}

enum UserExpertise: String, Codable, CaseIterable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case expert = "expert"

    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .expert: return "Expert"
        }
    }

    var description: String {
        switch self {
        case .beginner: return "Show me every detail"
        case .intermediate: return "Just the key steps"
        case .expert: return "Quick reference only"
        }
    }

    var icon: String {
        switch self {
        case .beginner: return "leaf.fill"
        case .intermediate: return "bolt.fill"
        case .expert: return "star.fill"
        }
    }
}

enum CompanionOutputStyle: String, Codable, CaseIterable {
    case practical = "practical"
    case balanced = "balanced"
    case experimental = "experimental"

    var displayName: String {
        switch self {
        case .practical: return "Practical"
        case .balanced: return "Balanced"
        case .experimental: return "Experimental"
        }
    }

    var description: String {
        switch self {
        case .practical: return "Utility-first, no fluff, immediate value"
        case .balanced: return "Useful with a bit of delight"
        case .experimental: return "Bold, creative, high novelty interfaces"
        }
    }

    var icon: String {
        switch self {
        case .practical: return "wrench.and.screwdriver.fill"
        case .balanced: return "circle.lefthalf.filled"
        case .experimental: return "sparkles"
        }
    }
}

enum CompanionResponsePace: String, Codable, CaseIterable {
    case instant = "instant"
    case balanced = "balanced"
    case deep = "deep"

    var displayName: String {
        switch self {
        case .instant: return "Instant"
        case .balanced: return "Balanced"
        case .deep: return "Deep"
        }
    }

    var description: String {
        switch self {
        case .instant: return "Fast, concise, and scannable"
        case .balanced: return "Fast plus enough detail"
        case .deep: return "Detailed and comprehensive"
        }
    }

    var icon: String {
        switch self {
        case .instant: return "bolt.fill"
        case .balanced: return "speedometer"
        case .deep: return "doc.text.magnifyingglass"
        }
    }
}

struct UserProfile: Codable {
    var name: String
    var language: String
    var context: UserContext
    var expertise: UserExpertise
    var outputStyle: CompanionOutputStyle
    var responsePace: CompanionResponsePace
    var wantsInteractiveUI: Bool
    var wantsHapticsAndSound: Bool
    var wantsGeneratedImages: Bool
    var focusAreas: String
    var practicalIntentWeight: Double
    var creativeIntentWeight: Double
    var learningSampleCount: Int
    var tappedSuggestionHistogram: [String: Int]
    var statLevels: [String: Int]  // CompanionStat.rawValue -> 1-6

    /// Get level for a stat (defaults to 2)
    func statLevel(_ stat: CompanionStat) -> Int {
        statLevels[stat.rawValue] ?? 2
    }

    /// Set level for a stat
    mutating func setStatLevel(_ stat: CompanionStat, level: Int) {
        statLevels[stat.rawValue] = max(1, min(6, level))
    }

    // MARK: - Stat Progression

    /// Record a stat observation. After enough good observations, the stat levels up.
    /// Returns the stat name if it leveled up, nil otherwise.
    @discardableResult
    static func recordStatObservation(_ stat: CompanionStat, quality: Double) -> CompanionStat? {
        // Track observations per stat in UserDefaults
        let key = "stat_obs_\(stat.rawValue)"
        let countKey = "stat_obs_count_\(stat.rawValue)"
        let qualitySum = UserDefaults.standard.double(forKey: key) + quality
        let count = UserDefaults.standard.integer(forKey: countKey) + 1
        UserDefaults.standard.set(qualitySum, forKey: key)
        UserDefaults.standard.set(count, forKey: countKey)

        // Level up after 5+ observations with average quality > 0.7
        if count >= 5 {
            let avg = qualitySum / Double(count)
            if avg > 0.7 {
                var profile = UserProfile.load() ?? UserProfile()
                let currentLevel = profile.statLevel(stat)
                if currentLevel < 6 {
                    profile.setStatLevel(stat, level: currentLevel + 1)
                    UserProfile.save(profile)
                    // Reset counters
                    UserDefaults.standard.set(0.0, forKey: key)
                    UserDefaults.standard.set(0, forKey: countKey)
                    return stat
                }
            }
            // Reset counters even if no level-up (prevent infinite accumulation)
            if count >= 10 {
                UserDefaults.standard.set(0.0, forKey: key)
                UserDefaults.standard.set(0, forKey: countKey)
            }
        }
        return nil
    }

    /// Stats with level >= 4 (high enough to affect personality)
    var dominantStats: [CompanionStat] {
        CompanionStat.allCases.filter { statLevel($0) >= 4 }
            .sorted { statLevel($0) > statLevel($1) }
    }

    /// Prompt fragments for dominant stats
    var statPromptFragments: String {
        let fragments = dominantStats.prefix(3).map { stat in
            "[\(stat.displayName.uppercased()) \(statLevel(stat))]: \(stat.promptFragment)"
        }
        return fragments.isEmpty ? "" : "Your active perception modes:\n" + fragments.joined(separator: "\n")
    }

    /// When 2+ stats are both high (level 4+), generate a conflict prompt that makes them argue.
    /// Returns nil if no conflict is possible (fewer than 2 dominant stats).
    var statConflictPrompt: String? {
        let high = dominantStats
        guard high.count >= 2 else { return nil }
        let stat1 = high[0]
        let stat2 = high[1]
        return """
        STAT CONFLICT: Your two strongest perception modes DISAGREE about what they see.
        [\(stat1.displayName.uppercased()) \(statLevel(stat1))] and [\(stat2.displayName.uppercased()) \(statLevel(stat2))] see the SAME object differently.
        Present BOTH perspectives in your message — first one stat's take, then the other's, clearly labeled.
        Example format:
        "[\(stat1.displayName.uppercased())] [stat1's interpretation]. [\(stat2.displayName.uppercased())] [stat2's contradicting interpretation]."
        Make them genuinely disagree — different priorities, different conclusions, different values.
        When this happens, set inner_voice_stat to the stat whose perspective you lead with.
        """
    }

    init(
        name: String = "",
        language: String = "en",
        context: UserContext = .curious,
        expertise: UserExpertise = .beginner,
        outputStyle: CompanionOutputStyle = .experimental,
        responsePace: CompanionResponsePace = .instant,
        wantsInteractiveUI: Bool = true,
        wantsHapticsAndSound: Bool = true,
        wantsGeneratedImages: Bool = true,
        focusAreas: String = "",
        practicalIntentWeight: Double = 0.55,
        creativeIntentWeight: Double = 0.45,
        learningSampleCount: Int = 0,
        tappedSuggestionHistogram: [String: Int] = [:],
        statLevels: [String: Int] = [:]
    ) {
        self.name = name
        self.language = language
        self.context = context
        self.expertise = expertise
        self.outputStyle = outputStyle
        self.responsePace = responsePace
        self.wantsInteractiveUI = wantsInteractiveUI
        self.wantsHapticsAndSound = wantsHapticsAndSound
        self.wantsGeneratedImages = wantsGeneratedImages
        self.focusAreas = focusAreas
        self.practicalIntentWeight = practicalIntentWeight
        self.creativeIntentWeight = creativeIntentWeight
        self.learningSampleCount = learningSampleCount
        self.tappedSuggestionHistogram = tappedSuggestionHistogram
        self.statLevels = statLevels
    }

    enum CodingKeys: String, CodingKey {
        case name
        case language
        case context
        case expertise
        case outputStyle
        case responsePace
        case wantsInteractiveUI
        case wantsHapticsAndSound
        case wantsGeneratedImages
        case focusAreas
        case practicalIntentWeight
        case creativeIntentWeight
        case learningSampleCount
        case tappedSuggestionHistogram
        case statLevels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        context = try container.decodeIfPresent(UserContext.self, forKey: .context) ?? .curious
        expertise = try container.decodeIfPresent(UserExpertise.self, forKey: .expertise) ?? .beginner
        outputStyle = try container.decodeIfPresent(CompanionOutputStyle.self, forKey: .outputStyle) ?? .experimental
        responsePace = try container.decodeIfPresent(CompanionResponsePace.self, forKey: .responsePace) ?? .instant
        wantsInteractiveUI = try container.decodeIfPresent(Bool.self, forKey: .wantsInteractiveUI) ?? true
        wantsHapticsAndSound = try container.decodeIfPresent(Bool.self, forKey: .wantsHapticsAndSound) ?? true
        wantsGeneratedImages = try container.decodeIfPresent(Bool.self, forKey: .wantsGeneratedImages) ?? true
        focusAreas = try container.decodeIfPresent(String.self, forKey: .focusAreas) ?? ""
        practicalIntentWeight = try container.decodeIfPresent(Double.self, forKey: .practicalIntentWeight) ?? 0.55
        creativeIntentWeight = try container.decodeIfPresent(Double.self, forKey: .creativeIntentWeight) ?? 0.45
        learningSampleCount = try container.decodeIfPresent(Int.self, forKey: .learningSampleCount) ?? 0
        tappedSuggestionHistogram = try container.decodeIfPresent([String: Int].self, forKey: .tappedSuggestionHistogram) ?? [:]
        statLevels = try container.decodeIfPresent([String: Int].self, forKey: .statLevels) ?? [:]
    }

    private static let userDefaultsKey = "user_profile"

    static func save(_ profile: UserProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    static func load() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return nil
        }
        return profile
    }

    static func recordSuggestionTap(_ suggestion: String, index: Int?) {
        var profile = load() ?? UserProfile()
        profile.recordSuggestionTap(suggestion, index: index)
        save(profile)
    }

    mutating func recordSuggestionTap(_ suggestion: String, index: Int?) {
        let normalized = Self.normalizeSuggestion(suggestion)
        guard !normalized.isEmpty else { return }

        let current = tappedSuggestionHistogram[normalized] ?? 0
        tappedSuggestionHistogram[normalized] = current + 1
        if tappedSuggestionHistogram.count > 24 {
            let trimmed = tappedSuggestionHistogram
                .sorted { $0.value > $1.value }
                .prefix(12)
                .map { ($0.key, $0.value) }
            tappedSuggestionHistogram = Dictionary(uniqueKeysWithValues: trimmed)
        }

        let targetPractical = Self.inferPracticalTarget(suggestion: normalized, index: index)
        let learningRate = max(0.08, min(0.24, 1.0 / Double(max(4, learningSampleCount + 3))))
        practicalIntentWeight = Self.clamp((practicalIntentWeight * (1.0 - learningRate)) + (targetPractical * learningRate), min: 0.05, max: 0.95)
        creativeIntentWeight = 1.0 - practicalIntentWeight
        learningSampleCount += 1
    }

    func topTappedSuggestions(limit: Int = 3) -> [String] {
        tappedSuggestionHistogram
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }

    private static func normalizeSuggestion(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func inferPracticalTarget(suggestion: String, index: Int?) -> Double {
        let practicalKeywords = ["how", "fix", "best", "price", "cost", "compare", "safe", "setup", "steps", "tips", "use", "battery", "warranty", "quality", "grip"]
        let creativeKeywords = ["idea", "design", "style", "aesthetic", "creative", "visual", "mood", "story", "concept", "image", "art", "theme", "inspire"]

        var score = 0.5
        if let index {
            // Current prompt convention: index 0 tends practical, index 1 tends exploratory.
            if index == 0 { score += 0.2 } else if index == 1 { score -= 0.2 }
        }
        if practicalKeywords.contains(where: { suggestion.contains($0) }) {
            score += 0.25
        }
        if creativeKeywords.contains(where: { suggestion.contains($0) }) {
            score -= 0.25
        }
        return clamp(score, min: 0.0, max: 1.0)
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.min(max, Swift.max(min, value))
    }
}
