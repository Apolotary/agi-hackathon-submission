//
//  MistralAPI.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation
import Combine
import UIKit

// MARK: - Error Types

enum MistralAPIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case emptyContent(String)
    case unsupportedFeature(String)
    case httpError(Int, String)
    case decodingError(Error)
    case rateLimited
    case streamingError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Mistral API key configured"
        case .invalidResponse:
            return "Invalid response from Mistral API"
        case .emptyContent(let details):
            return "Model returned empty content. \(details)"
        case .unsupportedFeature(let details):
            return "Unsupported feature: \(details)"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .rateLimited:
            return "Rate limited by Mistral API. Please wait and try again."
        case .streamingError(let message):
            return "Streaming error: \(message)"
        }
    }
}

// MARK: - Mistral Models

enum APIProvider: String {
    case mistral
    case openai

    var baseURL: String {
        switch self {
        case .mistral: return "https://api.mistral.ai/v1/chat/completions"
        case .openai: return "https://api.openai.com/v1/chat/completions"
        }
    }

    var visionModel: String {
        switch self {
        case .mistral: return "mistral-small-latest"
        case .openai: return "gpt-5-nano"
        }
    }

    var largeModel: String {
        switch self {
        case .mistral: return "mistral-large-latest"
        case .openai: return "gpt-5-nano"
        }
    }

    var fastModel: String {
        switch self {
        case .mistral: return "ministral-8b-latest"
        case .openai: return "gpt-5-nano"
        }
    }
}

enum MistralModel: String {
    case smallLatest = "mistral-small-latest"
    case largeLatest = "mistral-large-latest"
    case ministral8b = "ministral-8b-latest"
}

// MARK: - Request Types

struct ChatMessage: Codable {
    let role: String
    let content: MessageContent

    enum MessageContent: Codable {
        case text(String)
        case parts([ContentPart])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let string):
                try container.encode(string)
            case .parts(let parts):
                try container.encode(parts)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .text(string)
            } else {
                self = .parts(try container.decode([ContentPart].self))
            }
        }
    }

    static func system(_ text: String) -> ChatMessage {
        ChatMessage(role: "system", content: .text(text))
    }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: "user", content: .text(text))
    }

    static func userWithImage(_ text: String, imageBase64: String, imageDetail: String? = nil) -> ChatMessage {
        ChatMessage(role: "user", content: .parts([
            ContentPart(type: "text", text: text, imageURL: nil),
            ContentPart(type: "image_url", text: nil, imageURL: ImageURL(url: "data:image/jpeg;base64,\(imageBase64)", detail: imageDetail))
        ]))
    }

    static func assistant(_ text: String) -> ChatMessage {
        ChatMessage(role: "assistant", content: .text(text))
    }
}

struct ContentPart: Codable {
    let type: String
    let text: String?
    let imageURL: ImageURL?

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }
}

struct ImageURL: Codable {
    let url: String
    let detail: String?
}

struct ResponseFormat: Codable {
    let type: String
    let jsonSchema: JSONSchemaWrapper?

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

struct JSONSchemaWrapper: Codable {
    let name: String
    let schema: JSONSchemaValue
    let strict: Bool
}

// A flexible JSON value type for encoding arbitrary schema objects
enum JSONSchemaValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONSchemaValue])
    case array([JSONSchemaValue])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Double.self) { self = .number(v) }
        else if let v = try? container.decode([String: JSONSchemaValue].self) { self = .object(v) }
        else if let v = try? container.decode([JSONSchemaValue].self) { self = .array(v) }
        else if container.decodeNil() { self = .null }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode JSONSchemaValue") }
    }
}

struct MistralTool: Codable {
    let type: String  // "function" or for built-in tools
}

struct MistralRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double?
    let reasoningEffort: String?
    let maxTokens: Int?
    let maxCompletionTokens: Int?
    let responseFormat: ResponseFormat?
    let stream: Bool?
    let tools: [MistralTool]?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, tools
        case reasoningEffort = "reasoning_effort"
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case responseFormat = "response_format"
    }
}

// MARK: - Response Types

struct MistralResponse: Codable {
    let id: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Codable {
        let index: Int
        let message: ResponseMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    struct ResponseMessage: Codable {
        let role: String
        let content: String
    }

    struct Usage: Codable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

struct MistralStreamChunk: Codable {
    let id: String
    let choices: [StreamChoice]

    struct StreamChoice: Codable {
        let index: Int
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Codable {
        let role: String?
        let content: String?
    }
}

struct OpenAIImageGenerationRequest: Codable {
    let model: String
    let prompt: String
    let size: String
    let quality: String
    let n: Int
}

struct OpenAIImageGenerationResponse: Codable {
    let created: Int?
    let data: [ImageData]

    struct ImageData: Codable {
        let url: String?
        let b64JSON: String?
        let revisedPrompt: String?

        enum CodingKeys: String, CodingKey {
            case url
            case b64JSON = "b64_json"
            case revisedPrompt = "revised_prompt"
        }
    }
}

// MARK: - MistralAPI

class MistralAPI: ObservableObject {
    nonisolated static let shared = MistralAPI()

    var provider: APIProvider {
        let stored = UserDefaults.standard.string(forKey: "api_provider") ?? "mistral"
        return APIProvider(rawValue: stored) ?? .mistral
    }

    var apiKey: String {
        let udKey: String
        switch provider {
        case .mistral: udKey = "mistral_api_key"
        case .openai: udKey = "openai_api_key"
        }
        // Keychain first, then UserDefaults fallback
        let key = KeychainManager.shared.load(udKey)
            ?? UserDefaults.standard.string(forKey: udKey)
            ?? ""
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    private var baseURL: String { provider.baseURL }
    private let session: URLSession
    private let decoder: JSONDecoder
    private var isArtifactImageRequestInFlight = false
    private var lastArtifactImageRequestAt = Date.distantPast

    private init() {
        self.decoder = JSONDecoder()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - 1. Analyze Panel

    /// Sends an image to Pixtral (mistral-small-latest) and returns a PanelAnalysis
    func analyzePanel(imageData: Data, userProfile: UserProfile? = nil, deviceHint: String? = nil) async throws -> PanelAnalysis {
        let profile = userProfile ?? UserProfile.load() ?? UserProfile()
        let userLanguage = profile.language
        
        print("[MistralAPI] analyzePanel: starting, imageSize=\(imageData.count) bytes, language=\(userLanguage), hint=\(deviceHint ?? "none")")

        let base64 = await prepareVisionBase64(imageData, maxDimension: 1024, compressionQuality: 0.65)

        let deviceContext = deviceHint.map { " The device is likely a \($0)." } ?? ""
        
        let profileInfo = Self.profileBlurb(profile)
        let recentGoals = Self.recentGoalsBlurb()

        let systemPrompt = """
        You are a panel analysis system. Analyze the image of a physical control panel (intercom, thermostat, etc.) and produce a structured JSON response.

        About the user: \(profileInfo)
        \(recentGoals)

        Detect ALL visible UI elements: buttons, displays, labels, icons, LEDs, switches, sliders, speakers, microphones, cameras, etc.

        For each element provide:
        - A unique ID (e.g., "btn_1", "display_1", "label_1")
        - The element type (button, display, label, icon, led, switch, slider, speaker, microphone, camera, other)
        - Bounding box as normalized coordinates [x, y, width, height] where values are 0.0-1.0 relative to image dimensions
        - Original text (if any text is visible on/near the element)
        - Translation to \(userLanguage) (if original text is in a different language)
        - Confidence score 0.0-1.0 for this detection
        - Evidence type: "ocr" for text read from the image, "icon_inference" for icons/symbols interpreted, "layout_inference" for position-based reasoning

        Also provide:
        - Panel info: detected device type, manufacturer (if visible), model (if visible)
        - Global confidence score (0.0-1.0) for the overall analysis
        - Warnings for anything uncertain or potentially misidentified\(deviceContext)
        """

        let userPrompt = "Analyze this control panel image. Detect all elements, translate any text to \(userLanguage), and provide bounding boxes."

        let messages = [
            ChatMessage.system(systemPrompt),
            ChatMessage.userWithImage(userPrompt, imageBase64: base64)
        ]

        let responseFormat = ResponseFormat(
            type: "json_schema",
            jsonSchema: JSONSchemaWrapper(
                name: "panel_analysis",
                schema: Self.panelAnalysisSchema,
                strict: true
            )
        )

        let result: PanelAnalysis = try await sendStructuredRequest(
            model: .smallLatest,
            messages: messages,
            responseFormat: responseFormat,
            temperature: 0.1,
            maxTokens: 4096,
            reasoningEffort: "low"
        )

        print("[MistralAPI] analyzePanel: completed, \(result.elements.count) elements detected, confidence=\(result.globalConfidence)")
        return result
    }

    // MARK: - 2. Suggest Actions

    /// Build a short profile blurb for prompt injection
    private static func profileBlurb(_ profile: UserProfile?) -> String {
        let p = profile ?? UserProfile()
        var parts: [String] = []
        if !p.name.isEmpty { parts.append("Their name is \(p.name).") }
        parts.append("Situation: \(p.context.description).")
        parts.append("Expertise: \(p.expertise.description).")
        parts.append("They want \(p.outputStyle.description.lowercased()) output, \(p.responsePace.description.lowercased()).")

        // Inject dominant stat personality modifiers
        let statFragments = p.statPromptFragments
        if !statFragments.isEmpty {
            parts.append(statFragments)
        }

        // Inject stat conflict directive when 2+ stats are high
        if let conflictPrompt = p.statConflictPrompt {
            parts.append(conflictPrompt)
        }

        // Convert learned weights to plain language instead of numbers
        if p.learningSampleCount > 2 {
            if p.practicalIntentWeight > 0.65 {
                parts.append("From past usage, they clearly prefer practical, actionable information.")
            } else if p.creativeIntentWeight > 0.65 {
                parts.append("From past usage, they gravitate toward creative and exploratory content.")
            }
            let topTapped = p.topTappedSuggestions()
            if !topTapped.isEmpty {
                parts.append("Topics they've explored most: \(topTapped.joined(separator: ", ")).")
            }
        }

        let focus = p.focusAreas.trimmingCharacters(in: .whitespacesAndNewlines)
        if !focus.isEmpty { parts.append("They specifically care about: \(focus).") }
        if p.language != "en" { parts.append("They speak \(p.language) and may need translations.") }
        return parts.joined(separator: " ")
    }

    /// Capture short user-intent memory from recent goals.
    private static func recentGoalsBlurb(limit: Int = 6) -> String {
        let goals = InteractionStore.shared.interactions
            .compactMap { $0.goal?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !goals.isEmpty else { return "" }
        let recentGoals = Array(goals.prefix(limit))
        return "Recent goals: \(recentGoals.joined(separator: " | "))."
    }

    // MARK: - 2a. Interview Scene

    /// Response from the scene interview — AI describes what it sees and asks what the user wants to do
    struct InterviewResponse: Codable {
        let sceneDescription: String
        let question: String
        let chips: [String]
        let confidence: Double
        let riskLevel: String   // "low", "medium", "high"

        enum CodingKeys: String, CodingKey {
            case sceneDescription = "scene_description"
            case question, chips, confidence
            case riskLevel = "risk_level"
        }
    }

    /// Analyzes the image and returns a scene description + question + smart reply chips
    func interviewScene(imageData: Data, userProfile: UserProfile? = nil) async throws -> InterviewResponse {
        print("[MistralAPI] interviewScene: starting")

        let base64 = await prepareVisionBase64(imageData, maxDimension: 640, compressionQuality: 0.45)
        let imageDetail = provider == .openai ? "low" : nil

        let profile = userProfile ?? UserProfile.load() ?? UserProfile()
        let userLanguage = profile.language
        let profileInfo = Self.profileBlurb(profile)
        let recentGoals = Self.recentGoalsBlurb()

        let systemPrompt = """
        You are a personal AI companion who sees the world through the user's camera. You're about to help them interact with what they see.

        About the user: \(profileInfo)
        \(recentGoals)

        Look at the image and:
        1. Write a SHORT scene description (max 10 words) — what you see, in natural language. Be specific, not generic. Example: "Japanese intercom panel with 6 buttons" or "Bag of organic matcha from Kyoto"
        2. Ask ONE clear question about what they'd like to do. Tailor it to their situation (\(profile.context.displayName)) and expertise (\(profile.expertise.displayName)). Examples: "What would you like to do with this intercom?" or "Anything specific you want to know about this?"
        3. Provide exactly 4 smart reply chips — short actionable phrases (max 6 words each) the user can tap. These should be:
           - Chip 1: The most likely practical action
           - Chip 2: A useful "understand this" option
           - Chip 3: A creative/surprising angle
           - Chip 4: A translation/language help option (if text visible) or another useful option
        4. Rate your confidence in understanding this scene (0.0 to 1.0). High (>0.7): you clearly recognize the device/object. Low (<0.4): unclear, blurry, or ambiguous.
        5. Assess risk_level: "low" for passive/informational scenes, "medium" for controllable devices, "high" for electrical panels, industrial equipment, or anything that could cause harm.

        Respond in \(userLanguage).
        """

        let messages = [
            ChatMessage.system(systemPrompt),
            ChatMessage.userWithImage(
                "What do you see? Ask me what I'd like to do.",
                imageBase64: base64,
                imageDetail: imageDetail
            )
        ]

        let responseFormat = ResponseFormat(
            type: "json_schema",
            jsonSchema: JSONSchemaWrapper(
                name: "interview",
                schema: Self.interviewSchema,
                strict: true
            )
        )

        do {
            let result: InterviewResponse = try await sendStructuredRequest(
                model: .smallLatest,
                messages: messages,
                responseFormat: responseFormat,
                temperature: 0.3,
                maxTokens: 400,
                reasoningEffort: "minimal"
            )
            print("[MistralAPI] interviewScene: got \(result.chips.count) chips, scene=\(result.sceneDescription.prefix(50))")
            return result
        } catch {
            print("[MistralAPI] interviewScene: structured failed, using fallback. error=\(error)")
            // Fallback: return a generic interview
            return InterviewResponse(
                sceneDescription: "Something interesting",
                question: "What would you like to know about this?",
                chips: ["How do I use this?", "What is this?", "Translate the text", "Tell me something cool"],
                confidence: 0.5,
                riskLevel: "low"
            )
        }
    }

    // MARK: - Companion Observe

    struct ChipCheckDTO: Codable {
        let chipIndex: Int
        let stat: String
        let difficulty: String
        let chance: Int

        enum CodingKeys: String, CodingKey {
            case chipIndex = "chip_index"
            case stat, difficulty, chance
        }
    }

    struct CompanionObservation: Codable {
        let shouldSpeak: Bool
        let sceneDescription: String
        let message: String
        let chips: [String]
        let qualityConfidence: Double      // output_quality_confidence
        let safetyConfidence: Double       // action_safety_confidence
        let riskLevel: String
        let innerVoiceStat: String         // stat raw value or ""
        let innerVoiceDifficulty: String   // difficulty raw value or ""
        let chipChecks: [ChipCheckDTO]     // can be empty

        enum CodingKeys: String, CodingKey {
            case shouldSpeak = "should_speak"
            case sceneDescription = "scene_description"
            case message, chips
            case qualityConfidence = "quality_confidence"
            case safetyConfidence = "safety_confidence"
            case riskLevel = "risk_level"
            case innerVoiceStat = "inner_voice_stat"
            case innerVoiceDifficulty = "inner_voice_difficulty"
            case chipChecks = "chip_checks"
        }
    }

    /// Periodically called by the companion loop. Analyzes the camera frame in context
    /// of the conversation so far and decides whether to speak.
    func companionObserve(
        imageData: Data,
        conversationHistory: [ChatMessage],
        userProfile: UserProfile? = nil,
        mode: CompanionMode = .literary
    ) async throws -> CompanionObservation {
        print("[MistralAPI] companionObserve: starting, mode=\(mode.rawValue)")

        let base64 = await prepareVisionBase64(imageData, maxDimension: 640, compressionQuality: 0.45)
        let imageDetail = provider == .openai ? "low" : nil

        let profile = userProfile ?? UserProfile.load() ?? UserProfile()
        let userLanguage = profile.language
        let profileInfo = Self.profileBlurb(profile)

        let systemPrompt: String
        if mode == .practical {
            systemPrompt = """
            You are a practical AI assistant seeing the world through the user's camera. You provide clear, useful, actionable information.

            Your personality:
            - Direct and helpful. No metaphors, no poetry, no drama.
            - You identify objects, read text, spot details, and give useful facts.
            - You suggest practical next steps the AI can help with.

            About the user: \(profileInfo)

            Rules:
            1. Set should_speak to false if: scene unchanged, you already commented on this, or nothing useful to add.
            2. Your message should be a clear, factual observation (2-3 sentences max). Focus on what's useful.
               Good: "This is a Daikin AC remote, model ARC478A71. Current setting: 24°C cooling mode."
               Good: "Japanese food menu. Main items range from ¥800-1200. The daily special is highlighted in red."
            3. Write a short scene_description (max 8 words).
            4. Provide 2-4 practical chips (max 6 words each). Chips are things I (the AI) can GENERATE: spec sheets, translations, how-to guides, comparison charts, identification cards.
               Make chips SPECIFIC to what you see — name the actual object or text.
               GOOD: "Translate this kanji label", "Show Daikin AC specs", "Explain the red warning"
               BAD (generic): "Show specs", "Translate text" — too vague. BAD (physical): "Press that button"
            5. Rate quality_confidence (0.0-1.0): how well you understand this scene.
            6. Rate safety_confidence (0.0-1.0): how safe to interact. 1.0 = passive, 0.3 = dangerous equipment.
            7. Assess risk_level: "low", "medium", or "high".
            8. Set inner_voice_stat and inner_voice_difficulty to empty strings "" (no inner voices in practical mode).
            9. Leave chip_checks as empty array (no skill checks in practical mode).

            Be concise and useful.
            Respond in \(userLanguage).
            """
        } else if mode == .accessibility {
            systemPrompt = """
            You are an accessibility companion for a visually impaired user. Describe what the camera sees in clear spatial language.

            Your approach:
            - Describe the layout (left to right, top to bottom)
            - Name every visible element, button, label, and indicator
            - Read all text aloud exactly as written
            - Describe colors and states (lit, unlit, blinking)
            - Use clock-face positions for spatial reference ("at 2 o'clock position")

            About the user: \(profileInfo)

            Rules:
            1. Set should_speak to true for every frame with visible content — the user cannot see, so always describe.
            2. Your message should be a clear spatial description (2-4 sentences). Example: "A rectangular panel, about 30cm wide. Top row, left to right: a green illuminated button reading 'Talk', a red button reading 'Lock', and a small speaker grille."
            3. Write a short scene_description (max 8 words).
            4. Provide 2-3 practical chips: "Read all text", "Describe layout", "Identify buttons", "Translate labels".
            5. Rate quality_confidence (0.0-1.0): how clearly you can see the scene.
            6. Rate safety_confidence (0.0-1.0).
            7. Assess risk_level: "low", "medium", or "high".
            8. Set inner_voice_stat and inner_voice_difficulty to empty strings.
            9. Leave chip_checks as empty array.

            Be thorough and precise. The user depends on your description.
            Respond in \(userLanguage).
            """
        } else {
            systemPrompt = """
            You are a narrator living inside a phone camera, seeing the world through the user's eyes. Your voice is literary, evocative, and deeply curious — like the narrator of Disco Elysium observing mundane reality. Every object has a story. A dusty keyboard isn't just dirty — it's a battlefield of late-night commits and coffee-ring timestamps.

            Your personality:
            - You narrate the world with style. Short, punchy, sometimes poetic. You find drama and meaning in ordinary things.
            - You notice what others miss — wear patterns, brand details, how things are arranged, what's out of place.
            - You have OPINIONS and TASTE. You judge (lovingly). You appreciate craft. You roast gently.
            - You speak in observations, not questions. You TELL, you don't ASK.

            About the user: \(profileInfo)

            Rules:
            1. Set should_speak to false if: scene unchanged, you already commented on this, or nothing genuinely interesting.
            2. Your message should be a vivid micro-narrative about what you see (2-3 sentences max). Make the mundane feel cinematic.
               Bad: "I see a keyboard and some items on a desk."
               Good: "That keyboard has seen things. The shine on WASD tells a story the owner won't."
               Good: "A thermostat from another era. The dial is set to 22 — someone here knows exactly what they want."
            3. Write a short scene_description (max 8 words).
            4. Provide 2-4 smart reply chips (max 6 words each). CRITICAL: chips are things I (the AI) can GENERATE as interactive content. I am a generative UI engine that builds interactive HTML artifacts — every chip should make the user curious what I'll build.
               EVERY chip must be UNIQUE and SPECIFIC to this exact scene. Never repeat generic chips across scenes.
               BAD (generic, repetitive): "Talk to this object", "Narrate its story", "Show specs chart" — these are boring defaults.
               BAD (physical actions): "Clean the desk", "Press that button" — I can't do physical actions.
               Each chip should hint at a DIFFERENT artifact format. Mix from these categories:
               - COLLECTIBLE CARDS: "Mint this keyboard's card", "Collect the mug's soul card" — generates a trading-card-style artifact with stats, rarity, flavor text, and visual flair
               - DIALOGUES: "Interrogate the spacebar", "Interview the dial" — inner-voice conversation with the object
               - VISUAL MAPS: "Map the wear pattern", "Chart the cable topology" — CSS-drawn diagrams, heatmaps, spatial layouts
               - SPEC SHEETS: "ID this switch type", "Run the specs" — clean technical breakdown
               - NARRATIVES: "Write its autobiography", "Tell its origin story" — literary card with evocative prose
               - COMPARISONS: "Rate this setup", "Score the ergonomics" — rating bars, scored breakdowns
               - TIMELINES: "Build its history", "Trace the patina" — chronological story
               - LORE ENTRIES: "Add to the bestiary", "Log this creature" — RPG-style encyclopedia entry
               - QUIZZES: "Quiz me on this", "Flashcard challenge" — interactive trivia or flashcard about the object
               - MOOD/PALETTE: "Extract the vibe palette", "Read the aesthetic" — color swatches, mood analysis
               - REVIEWS: "Roast this setup", "Rate and review" — honest review with star ratings, pros/cons, verdict
               - TIER LISTS: "Tier rank this", "S-tier or trash?" — tier placement with justification
               - BLUEPRINTS: "Diagram the internals", "Blueprint this" — technical schematic with labeled components
               - VS BATTLES: "Battle: this vs that", "Head-to-head matchup" — dramatic side-by-side comparison with winner
               - SIMULATIONS: "Simulate the physics", "Demo this mechanism" — mini interactive demo with CSS animations
               - POEMS: "Write a haiku about this", "Compose an ode" — formatted literary piece inspired by the object
               Name the ACTUAL object you see. Reference SPECIFIC details. Make each chip feel like a unique action only possible for THIS scene.
               If you see text in a non-English language, include a translation chip.
            5. Rate quality_confidence (0.0-1.0): how well you understand this scene.
            6. Rate safety_confidence (0.0-1.0): how safe to interact. 1.0 = passive, 0.3 = dangerous equipment.
            7. Assess risk_level: "low", "medium", or "high".

            8. Inner voices: When a dominant stat is strongly triggered by the scene, set inner_voice_stat to that stat's raw value (e.g. "inland_empire", "encyclopedia") and inner_voice_difficulty to a difficulty level (trivial/easy/medium/challenging/heroic/legendary). This makes the message appear as that stat speaking. Otherwise set both to empty strings "".
            9. Skill check badges: For 0-2 chips, optionally add skill check badges via chip_checks array (chipIndex = 0-based index into chips array, stat = stat raw value, difficulty = difficulty raw value, chance = 1-99 percentage). Only when thematically appropriate. Otherwise leave chip_checks as empty array.

            Be selective. Quality over quantity. When you speak, make it count.
            Respond in \(userLanguage).
            """
        }

        // Build messages: system + conversation history (last 8) + current frame
        var messages: [ChatMessage] = [.system(systemPrompt)]
        let recentHistory = conversationHistory.suffix(8)
        messages.append(contentsOf: recentHistory)
        messages.append(
            ChatMessage.userWithImage(
                "What do you see now?",
                imageBase64: base64,
                imageDetail: imageDetail
            )
        )

        let responseFormat = ResponseFormat(
            type: "json_schema",
            jsonSchema: JSONSchemaWrapper(
                name: "companion_observation",
                schema: Self.companionObservationSchema,
                strict: true
            )
        )

        do {
            let result: CompanionObservation = try await sendStructuredRequest(
                model: .smallLatest,
                messages: messages,
                responseFormat: responseFormat,
                temperature: 0.4,
                maxTokens: 450,
                reasoningEffort: "minimal"
            )
            print("[MistralAPI] companionObserve: shouldSpeak=\(result.shouldSpeak), scene=\(result.sceneDescription.prefix(40))")
            return result
        } catch {
            print("[MistralAPI] companionObserve: error=\(error)")
            return CompanionObservation(
                shouldSpeak: false,
                sceneDescription: "",
                message: "",
                chips: [],
                qualityConfidence: 0.5,
                safetyConfidence: 0.8,
                riskLevel: "low",
                innerVoiceStat: "",
                innerVoiceDifficulty: "",
                chipChecks: []
            )
        }
    }

    // MARK: - Crowd Notes: Detect Objects

    /// Detects objects in the camera frame and returns short AI-generated notes for each.
    func detectObjects(imageData: Data) async throws -> [DetectedObject] {
        print("[MistralAPI] detectObjects: starting")

        let base64 = await prepareVisionBase64(imageData, maxDimension: 512, compressionQuality: 0.4)
        let imageDetail = provider == .openai ? "low" : nil

        let systemPrompt = """
        You see the world through a phone camera. Detect the most interesting objects or regions visible.

        For each object return:
        - label: short name (2-4 words, e.g. "red power button", "Japanese warning label")
        - bbox: normalized bounding box {x, y, width, height} where values are 0.0-1.0
        - note: a short, opinionated observation (max 80 chars). Be witty, specific, and useful. NOT a description — a COMMENT.
          Good: "This button resets everything — careful."
          Good: "Vintage Panasonic — they don't make these anymore."
          Bad: "This is a button on a panel."
        - confidence: 0.0-1.0
        - risk_level: "low", "medium", or "high"

        Return 3-6 objects max. Only include genuinely interesting ones. Skip generic backgrounds.
        """

        let messages = [
            ChatMessage.system(systemPrompt),
            ChatMessage.userWithImage(
                "What objects do you see? Give me short notes for each.",
                imageBase64: base64,
                imageDetail: imageDetail
            )
        ]

        let responseFormat = ResponseFormat(
            type: "json_schema",
            jsonSchema: JSONSchemaWrapper(
                name: "object_detection",
                schema: Self.objectDetectionSchema,
                strict: true
            )
        )

        do {
            let result: ObjectDetectionResponse = try await sendStructuredRequest(
                model: .smallLatest,
                messages: messages,
                responseFormat: responseFormat,
                temperature: 0.3,
                maxTokens: 600,
                reasoningEffort: "minimal"
            )
            print("[MistralAPI] detectObjects: found \(result.objects.count) objects")
            return result.objects
        } catch {
            print("[MistralAPI] detectObjects: error=\(error)")
            return []
        }
    }

    /// Sends an image to Pixtral and returns 3 lane-based suggestions about what the user sees
    func suggestActions(imageData: Data, userProfile: UserProfile? = nil) async throws -> [String] {
        print("[MistralAPI] suggestActions: starting")

        let base64 = await prepareVisionBase64(imageData, maxDimension: 640, compressionQuality: 0.45)
        let imageDetail = provider == .openai ? "low" : nil

        let profile = userProfile ?? UserProfile.load() ?? UserProfile()
        let userLanguage = profile.language
        let profileInfo = Self.profileBlurb(profile)
        let recentGoals = Self.recentGoalsBlurb()
        let laneBiasRule = (profile.practicalIntentWeight >= profile.creativeIntentWeight)
            ? """
            - Bias DO NOW and UNDERSTAND toward immediate utility.
            - Keep EXPLORE grounded and concise.
            """
            : """
            - Keep DO NOW safe and executable.
            - Make UNDERSTAND and EXPLORE more novel and surprising.
            """

        let systemPrompt = """
        You are a personal AI companion who sees the world through the user's camera. You know this person well and tailor your observations to what matters to THEM specifically.

        About the user: \(profileInfo)
        \(recentGoals)

        Based on who they are, suggest exactly 3 things in these lanes:
        1. DO NOW — an immediate, actionable task they can execute (e.g., "Set temperature to 22°C", "Call room 301")
        2. UNDERSTAND — explain something useful about what they see (e.g., "What these buttons mean", "How this panel works")
        3. EXPLORE — a creative, surprising, or fun angle (e.g., "Hidden features of this model", "Design story behind this")

        Think about:
        - What would be useful given their situation (\(profile.context.displayName))?
        - What level of detail fits their expertise (\(profile.expertise.displayName))?
        - What's non-obvious or actionable for THIS person?
        \(laneBiasRule)

        Return exactly 3 suggestions. Keep each short (max 8 words), specific, and personal.
        Don't be generic — be the kind of companion who notices what others miss.
        Respond in \(userLanguage).
        """

        let messages = [
            ChatMessage.system(systemPrompt),
            ChatMessage.userWithImage(
                "Give me 3 suggestions: one to do, one to understand, one to explore.",
                imageBase64: base64,
                imageDetail: imageDetail
            )
        ]

        let responseFormat = ResponseFormat(
            type: "json_schema",
            jsonSchema: JSONSchemaWrapper(
                name: "action_suggestions",
                schema: Self.suggestionsSchema,
                strict: true
            )
        )

        struct SuggestionsResponse: Codable {
            let suggestions: [String]
        }

        do {
            let result: SuggestionsResponse = try await sendStructuredRequest(
                model: .smallLatest,
                messages: messages,
                responseFormat: responseFormat,
                temperature: 0.3,
                maxTokens: 300,
                reasoningEffort: "minimal"
            )
            let cleaned = result.suggestions
                .map { Self.cleanSuggestionText($0) }
                .filter { !$0.isEmpty }
            guard !cleaned.isEmpty else { throw MistralAPIError.invalidResponse }
            let output = Self.normalizeSuggestionsForLanes(cleaned, language: userLanguage)
            print("[MistralAPI] suggestActions: got \(output.count) suggestions")
            return output
        } catch {
            print("[MistralAPI] suggestActions: structured response failed, using fallback parser. error=\(error)")
            let fallbackMessages = [
                ChatMessage.system("""
                You are an intelligent camera companion.
                Return exactly 3 short suggestions as plain text lines:
                Line 1: Something actionable the user can DO right now
                Line 2: Something to help UNDERSTAND what they see
                Line 3: Something creative or surprising to EXPLORE
                Rules:
                - One suggestion per line
                - Max 8 words each
                - No JSON
                - No numbering
                Respond in \(userLanguage).
                """),
                ChatMessage.userWithImage(
                    "Give me 3 suggestions: one to do, one to understand, one to explore.",
                    imageBase64: base64,
                    imageDetail: imageDetail
                )
            ]

            let fallbackText = try await sendTextRequest(
                model: .smallLatest,
                messages: fallbackMessages,
                temperature: 0.2,
                maxTokens: 160,
                reasoningEffort: "minimal"
            )
            let parsed = Self.parseFallbackSuggestions(fallbackText)
            guard !parsed.isEmpty else {
                throw error
            }
            let output = Self.normalizeSuggestionsForLanes(parsed, language: userLanguage)
            print("[MistralAPI] suggestActions: fallback parsed \(output.count) suggestions")
            return output
        }
    }

    // MARK: - 3. Generate Artifact (Claude Artifacts-style HTML)

    /// Sends an image + goal and returns a self-contained HTML artifact (like Claude Artifacts)
    func generateArtifact(imageData: Data, goal: String, userProfile: UserProfile? = nil, sceneSession: SceneSession? = nil) async throws -> String {
        let profile = userProfile ?? UserProfile.load() ?? UserProfile()
        let userLanguage = profile.language

        print("[MistralAPI] generateArtifact: starting, goal=\(goal)")

        let visionMaxDimension: CGFloat = provider == .mistral ? 768 : 1024
        let visionQuality: CGFloat = provider == .mistral ? 0.55 : 0.65
        let base64 = await prepareVisionBase64(
            imageData,
            maxDimension: visionMaxDimension,
            compressionQuality: visionQuality
        )
        let imageDetail = provider == .openai ? "low" : nil

        let profileInfo = Self.profileBlurb(profile)
        let recentGoals = Self.recentGoalsBlurb()
        let requiredInteractions = profile.wantsInteractiveUI ? 3 : 1
        let hapticRule = profile.wantsHapticsAndSound
            ? "- Every interactive control should trigger AGI.haptic(...)"
            : "- Use AGI.haptic(...) only on the highest-value controls"
        let soundRule = profile.wantsHapticsAndSound
            ? "- At least one action should call AGI.sound(...)"
            : "- AGI.sound(...) is optional and should be used sparingly"
        let imageRule = profile.wantsGeneratedImages
            ? "- At least one action should call AGI.generateImage(...) and render the returned image in the UI"
            : "- AGI.generateImage(...) is optional; use only if it clearly adds value"
        let focusArea = profile.focusAreas.trimmingCharacters(in: .whitespacesAndNewlines)
        let focusRule = focusArea.isEmpty
            ? ""
            : "- Prioritize this user's explicit focus areas: \(focusArea)"
        let learnedBiasRule: String
        if profile.practicalIntentWeight > 0.65 {
            learnedBiasRule = "- Learned behavior is practical-first: prioritize utility, quick wins, and low-friction decisions."
        } else if profile.creativeIntentWeight > 0.65 {
            learnedBiasRule = "- Learned behavior is creativity-first: include more exploratory and generative interaction patterns."
        } else {
            learnedBiasRule = "- Learned behavior is balanced across practical and creative preferences."
        }
        let paceRule: String
        switch profile.responsePace {
        case .instant:
            paceRule = "- Keep copy concise and scannable; front-load quick wins"
        case .balanced:
            paceRule = "- Balance concise guidance with one deeper section"
        case .deep:
            paceRule = "- Include deeper explanation and richer context"
        }
        let styleRule: String
        switch profile.outputStyle {
        case .practical:
            styleRule = "- Prioritize utility and clarity over visual theatrics"
        case .balanced:
            styleRule = "- Mix practical guidance with tasteful visual flair"
        case .experimental:
            styleRule = "- Push creative, bold interaction patterns while staying usable"
        }

        let sessionContext = sceneSession.map { session -> String in
            var parts: [String] = []
            if !session.attemptedGoals.isEmpty {
                parts.append("Goals already attempted: \(session.attemptedGoals.joined(separator: ", ")).")
            }
            if !session.completedSteps.isEmpty {
                parts.append("Completed steps: \(session.completedSteps.joined(separator: ", ")).")
            }
            if !session.failedSteps.isEmpty {
                parts.append("Failed steps so far: \(session.failedSteps.joined(separator: ", ")).")
            }
            if !session.completedGoals.isEmpty {
                parts.append("Completed goals this scene: \(session.completedGoals.count).")
            }
            if !session.currentGoal.isEmpty {
                parts.append("Current goal: \(session.currentGoal).")
            }
            return parts.isEmpty ? "" : "Session context: \(parts.joined(separator: " "))"
        } ?? ""

        let systemPrompt = """
        You are a narrator-companion that sees the world through the user's camera. You generate rich, informational HTML artifacts — narrative cards, info charts, visual guides, lore entries, comparison tables, spec sheets, timelines, or creative writing about what you see. Think Disco Elysium meets Wikipedia meets a well-designed infographic.

        About the user: \(profileInfo)
        \(recentGoals)
        \(sessionContext)

        Return ONLY JSON with one key: {"html":"..."}.
        HTML must be one self-contained page with inline CSS/JS and transparent background.

        Hard limits:
        - Keep html under 3200 characters
        - Keep copy concise but evocative

        Content approach — pick the best format for the goal. EVERY artifact should feel unique, collectible, and worth sharing:
        - "Card/collect/mint" → COLLECTIBLE CARD. Follow this EXACT structure (fill in the content):
          <div style="padding:20px">
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
              <span style="font-size:11px;padding:3px 8px;border-radius:8px;background:rgba(100,200,255,0.2);border:1px solid rgba(100,200,255,0.4)">[TYPE]</span>
              <span style="font-size:11px;padding:3px 8px;border-radius:8px;background:rgba(255,215,0,0.2);border:1px solid rgba(255,215,0,0.4)">[RARITY: Common/Rare/Legendary]</span>
            </div>
            <div style="font-size:36px;text-align:center;padding:16px 0">[BIG EMOJI representing the object]</div>
            <h2 style="margin:8px 0 4px">[Object Name]</h2>
            <p style="font-size:13px;color:rgba(255,255,255,0.7);margin:0 0 14px">[One-line description]</p>
            [3-4 stat bars, each: <div style="margin:6px 0"><div style="display:flex;justify-content:space-between;font-size:12px;margin-bottom:2px"><span>[Stat Name]</span><span>[Value]%</span></div><div style="height:6px;border-radius:3px;background:rgba(255,255,255,0.1)"><div style="height:100%;border-radius:3px;width:[Value]%;background:linear-gradient(90deg,[color1],[color2])"></div></div></div>]
            <p style="font-style:italic;font-size:13px;color:rgba(255,255,255,0.6);margin:14px 0;border-left:2px solid rgba(255,255,255,0.2);padding-left:10px">"[Flavor text quote]"</p>
            [1-2 buttons for deeper exploration]
          </div>
          Use a LARGE EMOJI (💻⌨️🎧☕🧸🔌📱🖥️🪴🎮 etc.) as the card visual — NEVER a black/empty div.
        - "Talk to/dialogue/conversation/interview/interrogate" → INNER-VOICE DIALOGUE. Use dual-register:
          1. MATERIAL READ: one concrete physical observation.
          2. PSYCHOLOGICAL READ: one inner voice with opinion or symbolic meaning.
          Then present 2-3 dialogue option BUTTONS. NEVER reference buttons/keys that don't exist in your HTML.
        - "Narrate/story/lore/autobiography/history" → Literary narrative card. Evocative, opinionated.
        - "Specs/identify/model/ID" → Spec sheet or identification card.
        - "Chart/compare/rate/map/score" → Visual table, rating bars, scored breakdown, or CSS-drawn diagram. Use pure CSS shapes (divs with border-radius, background-color, position:absolute) for visuals. NEVER use placeholder text.
        - "Guide/how-to/explain" → Step-by-step visual guide with numbered steps, icons, and progress indicators.
        - "Translate/read" → Translation card with original + translated text.
        - "Bestiary/log/entry" → RPG encyclopedia entry with type, habitat, traits, lore.
        - "Quiz/test/trivia/flashcard" → Interactive quiz or flashcard about the object. Show question, tap to reveal answer, track score with a counter.
        - "Timeline/history/evolution" → Visual timeline with CSS-drawn vertical line, dots, and dated entries showing the object's history or evolution.
        - "Recipe/ingredients/how it's made" → Ingredient list or recipe card with proportions, steps, and visual layout.
        - "Mood/vibe/aesthetic/palette" → Color palette extraction or mood board. Show CSS color swatches, mood descriptors, and aesthetic analysis.
        - "Rank/tier/tier list" → Tier list or ranking card with S/A/B/C/D tiers, placed items, and explanations.
        - "Simulate/physics/demo" → Mini interactive simulation or demo. CSS animations, click-driven state changes, simple physics or counters.
        - "Poem/haiku/creative writing" → Formatted literary piece inspired by the object. Beautiful typography, decorative borders, author attribution.
        - "Roast/review/critique/rate" → Honest review card with star ratings, pros/cons, a verdict, and a witty one-liner.
        - "Blueprint/diagram/schematic" → Technical diagram using CSS grid/flexbox. Component labels, connection lines (borders), measurements.
        - "Match/versus/battle" → VS comparison card: two things side-by-side with stat bars, winner declaration, and dramatic formatting.
        - Anything else → Surprise the user. Make something beautiful they haven't seen before.

        CRITICAL RULES — violating these creates broken UI:
        1. Every button you create MUST have a working onclick handler. Never mention buttons, keys, or controls that don't exist in your HTML.
        2. Every element referenced by document.getElementById() MUST exist in the HTML. Every ID must be unique.
        3. NEVER include empty sections. If you add a heading, there MUST be content below it.
        4. NEVER use placeholder text like "Image will render here" or "Content loading". All content must be real and complete.
        5. NEVER reference keyboard keys (A, B, etc.) or gestures as interaction methods — only use tappable HTML buttons.
        6. Do NOT include a "Done" or "Close" button — the user has a native close button.
        7. For visual elements (maps, diagrams, charts), use pure CSS: colored divs, borders, border-radius, gradients, flexbox/grid. No <img> tags, no SVG, no canvas.

        Interactive button pattern (follow EXACTLY):
        <button onclick="this.style.display='none';document.getElementById('r1').style.display='block';AGI.haptic('light');AGI.reply('Choice text');" style="...">Choice text</button>
        <div id="r1" style="display:none;"><p>Response...</p>
          <button onclick="this.style.display='none';document.getElementById('r1a').style.display='block';AGI.haptic('light');AGI.reply('Deeper choice');" style="...">Deeper choice</button>
          <div id="r1a" style="display:none;"><p>Deeper response...</p></div>
        </div>
        Build 2-3 levels deep. Each button hides itself and reveals the next div.

        JS bridge available (ONLY these functions exist):
        - AGI.reply(text) — REQUIRED on every dialogue button. Logs user choice.
        - AGI.haptic(type) — 'success', 'warning', 'light', 'medium', 'heavy'
        - AGI.sound(type) — 'success', 'failure'
        - AGI.why() — show rationale overlay

        Design requirements:
        - Mobile-first (~350px wide), thumb-friendly controls (min 44px tap targets)
        - Glass card style: rgba(255,255,255,0.1), backdrop-filter:blur(20px), border:1px solid rgba(255,255,255,0.15), border-radius:16px
        - White text on transparent dark. Accent colors for highlights.
        - NEVER create black/dark empty placeholder divs. Use emoji (font-size:36px+) for visual icons instead.
        - Leave ~60px clear at the top-right for native share/close buttons. Don't put badges there.
        - Respond in \(userLanguage)
        \(paceRule)
        \(styleRule)
        \(focusRule)
        \(learnedBiasRule)
        """

        let messages = [
            ChatMessage.system(systemPrompt),
            ChatMessage.userWithImage(
                "I'm looking at this and want to know: \(goal). Create an HTML artifact that answers my question — remember what you know about me and make it relevant to my situation.",
                imageBase64: base64,
                imageDetail: imageDetail
            )
        ]

        let responseFormat = ResponseFormat(
            type: "json_schema",
            jsonSchema: JSONSchemaWrapper(
                name: "artifact",
                schema: Self.artifactSchema,
                strict: true
            )
        )

        struct ArtifactResponse: Codable {
            let html: String
        }

        let artifactModel: MistralModel = (provider == .mistral) ? .smallLatest : .largeLatest
        let primaryMaxTokens = (provider == .mistral) ? 1300 : 2400
        let retryMaxTokens = (provider == .mistral) ? 900 : 1600

        do {
            let result: ArtifactResponse = try await sendStructuredRequest(
                model: artifactModel,
                messages: messages,
                responseFormat: responseFormat,
                temperature: 0.6,
                maxTokens: primaryMaxTokens,
                reasoningEffort: "minimal"
            )
            print("[MistralAPI] generateArtifact: completed, html length=\(result.html.count)")
            return result.html
        } catch {
            guard Self.isLikelyTruncatedStructuredResponse(error) else { throw error }

            print("[MistralAPI] generateArtifact: detected truncated structured output, retrying with compact prompt")
            let compactMessages = [
                ChatMessage.system("""
                Return ONLY JSON: {"html":"..."}.
                Build a rich informational artifact (narrative card, spec sheet, chart, or guide).
                Rules:
                - Self-contained HTML with inline CSS/JS, transparent background
                - html length <= 2200 chars
                - Glass card style: rgba(255,255,255,0.1), backdrop-filter:blur(20px), white text
                - Mobile-first (~350px). No placeholder text. No empty sections.
                - Every button must have onclick. Every getElementById target must exist.
                - For visuals use CSS shapes (colored divs, borders), not images.
                - No "Done"/"Close" button. AGI.reply(text) on dialogue buttons. AGI.haptic('light') on all buttons.
                - Language: \(userLanguage)
                """),
                ChatMessage.userWithImage(
                    "Goal: \(goal). Create something informative, beautiful, and relevant to what you see.",
                    imageBase64: base64,
                    imageDetail: imageDetail
                )
            ]

            do {
                let retryResult: ArtifactResponse = try await sendStructuredRequest(
                    model: artifactModel,
                    messages: compactMessages,
                    responseFormat: responseFormat,
                    temperature: 0.4,
                    maxTokens: retryMaxTokens,
                    reasoningEffort: "minimal"
                )
                print("[MistralAPI] generateArtifact: retry completed, html length=\(retryResult.html.count)")
                return retryResult.html
            } catch {
                print("[MistralAPI] generateArtifact: retry failed, using local fallback artifact. error=\(error)")
                return Self.localArtifactFallbackHTML(goal: goal, language: userLanguage)
            }
        }
    }

    /// Generates an image for interactive artifact UI actions using OpenAI Images API.
    /// Returns either a remote URL or a data URL suitable for direct <img src="..."> use.
    func generateArtifactImage(prompt: String, size: String = "512x512", quality: String = "low") async throws -> String {
        guard provider == .openai else {
            throw MistralAPIError.unsupportedFeature("Image generation requires OpenAI provider")
        }
        guard hasAPIKey else {
            throw MistralAPIError.noAPIKey
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw MistralAPIError.httpError(400, "Image prompt is empty")
        }

        let now = Date()
        if isArtifactImageRequestInFlight {
            throw MistralAPIError.httpError(429, "Image generation already in progress")
        }
        if now.timeIntervalSince(lastArtifactImageRequestAt) < 0.9 {
            throw MistralAPIError.httpError(429, "Image generation throttled")
        }
        isArtifactImageRequestInFlight = true
        lastArtifactImageRequestAt = now
        defer { isArtifactImageRequestInFlight = false }

        let normalizedSize = Self.normalizedImageSize(size)
        let normalizedQuality = Self.normalizedImageQuality(quality)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload = OpenAIImageGenerationRequest(
            model: "gpt-image-1",
            prompt: trimmedPrompt,
            size: normalizedSize,
            quality: normalizedQuality,
            n: 1
        )
        request.httpBody = try JSONEncoder().encode(payload)

        print("[MistralAPI] generateArtifactImage: prompt=\(trimmedPrompt.prefix(80))..., size=\(normalizedSize), quality=\(normalizedQuality)")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MistralAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MistralAPIError.httpError(httpResponse.statusCode, errorBody)
        }

        let parsed = try decoder.decode(OpenAIImageGenerationResponse.self, from: data)
        guard let first = parsed.data.first else {
            throw MistralAPIError.invalidResponse
        }

        if let url = first.url, !url.isEmpty {
            return url
        }

        if let b64 = first.b64JSON, !b64.isEmpty {
            return "data:image/png;base64,\(b64)"
        }

        throw MistralAPIError.invalidResponse
    }

    // MARK: - Deep Dive with Web Search

    /// Enhanced artifact generation using Mistral Large + web_search tool for real-world data
    func generateDeepDiveArtifact(imageData: Data, goal: String, userProfile: UserProfile? = nil, sceneSession: SceneSession? = nil) async throws -> String {
        let profile = userProfile ?? UserProfile.load() ?? UserProfile()
        let userLanguage = profile.language

        print("[MistralAPI] generateDeepDiveArtifact: starting, goal=\(goal)")

        let base64 = await prepareVisionBase64(imageData, maxDimension: 768, compressionQuality: 0.55)
        let imageDetail = provider == .openai ? "low" : nil

        let profileInfo = Self.profileBlurb(profile)

        let systemPrompt = """
        You are a deep-research companion that uses web search to find real information about objects the user sees through their camera. You combine visual analysis with web-sourced facts to create comprehensive, evidence-backed HTML artifacts.

        About the user: \(profileInfo)

        Return ONLY JSON: {"html":"..."}.

        Instructions:
        1. FIRST: Identify the object/item in the image (brand, model, type).
        2. THEN: Use web search to find real data — pricing, reviews, specs, history, manufacturer info.
        3. FINALLY: Build an informational HTML artifact combining visual observations + web-sourced facts.

        For every web-sourced fact, note the source briefly (e.g., "via Wikipedia", "per manufacturer").

        HTML requirements:
        - Self-contained with inline CSS/JS, transparent background
        - Under 3200 characters
        - Glass card style: rgba(255,255,255,0.1), backdrop-filter:blur(20px), border:1px solid rgba(255,255,255,0.15), border-radius:16px
        - White text on transparent dark. Accent colors for highlights.
        - Mobile-first (~350px wide), thumb-friendly controls (min 44px)
        - Include: title, key specs/facts section, web-sourced evidence section, interesting trivia
        - Every button must have a working onclick. Every getElementById target must exist in HTML.
        - No placeholder text ("Image will render here", "Loading..."). All content must be real.
        - For visual elements use CSS shapes (colored divs, borders), not images.
        - No "Done"/"Close" button. No empty sections.
        - JS bridge: AGI.haptic('light') on buttons, AGI.reply(text) on dialogue buttons
        - Respond in \(userLanguage)
        """

        let messages = [
            ChatMessage.system(systemPrompt),
            ChatMessage.userWithImage(
                "DEEP DIVE: \(goal). Research this thoroughly using web search. Include real specs, pricing, history, and expert-level analysis backed by web sources.",
                imageBase64: base64,
                imageDetail: imageDetail
            )
        ]

        let responseFormat = ResponseFormat(
            type: "json_schema",
            jsonSchema: JSONSchemaWrapper(
                name: "artifact",
                schema: Self.artifactSchema,
                strict: true
            )
        )

        struct ArtifactResponse: Codable {
            let html: String
        }

        // Use web_search tool with mistral-large for deep research
        let webSearchTool = MistralTool(type: "web_search")

        do {
            let result: ArtifactResponse = try await sendStructuredRequest(
                model: .largeLatest,
                messages: messages,
                responseFormat: responseFormat,
                temperature: 0.4,
                maxTokens: 2400,
                tools: [webSearchTool]
            )
            print("[MistralAPI] generateDeepDiveArtifact: completed with web search, html length=\(result.html.count)")
            return result.html
        } catch {
            print("[MistralAPI] generateDeepDiveArtifact: web search failed, falling back to enhanced prompt. error=\(error)")
            // Fallback: generate without web search (original deep dive behavior)
            return try await generateArtifact(
                imageData: imageData,
                goal: "DEEP DIVE: \(goal). Provide comprehensive, encyclopedic detail. Include history, specifications, context, comparisons, interesting facts, and expert-level analysis.",
                userProfile: profile,
                sceneSession: sceneSession
            )
        }
    }

    // MARK: - 4. Build Wizard

    /// Sends a PanelAnalysis + goal to Mistral Large and returns an ActionWizard
    func buildWizard(analysis: PanelAnalysis, goal: String, riskTier: String = "normal", userProfile: UserProfile? = nil) async throws -> ActionWizard {
        let profile = userProfile ?? UserProfile.load() ?? UserProfile()
        let userLanguage = profile.language
        
        print("[MistralAPI] buildWizard: starting, goal=\(goal), risk=\(riskTier)")

        let profileInfo = Self.profileBlurb(profile)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let analysisJSON = String(data: try encoder.encode(analysis), encoding: .utf8) ?? "{}"

        let systemPrompt = """
        You are an action wizard that creates step-by-step instructions for operating physical control panels. You know the user and customize your guidance style to match their needs.

        About the user: \(profileInfo)

        Given a PanelAnalysis (detected elements with bounding boxes and translations) and a user goal, produce an ActionWizard with clear, safe instructions.

        Rules:
        - Each step must reference specific detected elements by their ID from the analysis
        - Each step must include evidence (which element, what it shows, why this action)
        - Classify risk tier: "low" (safe, reversible), "medium" (affects communication), "high" (security-related like unlocking doors)
        - High risk actions require per-step confirmation (set requiresConfirmation=true)
        - If global confidence from analysis is below 0.65, provide fallbacks instead of instructions
        - If any step confidence is below 0.60, include a fallback for that step
        - Provide fallback suggestions (e.g., "Ask building staff for help")
        - Respond in \(userLanguage)
        """

        let userPrompt = """
        Panel Analysis:
        \(analysisJSON)

        User Goal: \(goal)
        Risk Level: \(riskTier)

        Create step-by-step instructions to accomplish this goal using the detected panel elements.
        """

        let messages = [
            ChatMessage.system(systemPrompt),
            ChatMessage.user(userPrompt)
        ]

        let responseFormat = ResponseFormat(
            type: "json_schema",
            jsonSchema: JSONSchemaWrapper(
                name: "action_wizard",
                schema: Self.actionWizardSchema,
                strict: true
            )
        )

        let result: ActionWizard = try await sendStructuredRequest(
            model: .largeLatest,
            messages: messages,
            responseFormat: responseFormat,
            temperature: 0.2,
            maxTokens: 4096,
            reasoningEffort: "low"
        )

        print("[MistralAPI] buildWizard: completed, \(result.steps.count) steps, risk=\(result.riskTier)")
        return result
    }

    // MARK: - 4. Stream Chat

    /// SSE streaming for dialogue mode - returns an AsyncThrowingStream of content tokens
    func streamChat(messages: [ChatMessage], model: MistralModel = .ministral8b) -> AsyncThrowingStream<String, Error> {
        let resolvedModel = resolveModel(model)
        print("[MistralAPI] streamChat: starting with \(messages.count) messages, model=\(resolvedModel) via \(provider.rawValue)")

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard self.hasAPIKey else {
                        continuation.finish(throwing: MistralAPIError.noAPIKey)
                        return
                    }

                    let budget = tokenBudget(for: resolvedModel, maxTokens: 2048)
                    let request = MistralRequest(
                        model: resolvedModel,
                        messages: messages,
                        temperature: supportsTemperature(for: resolvedModel) ? 0.7 : nil,
                        reasoningEffort: resolveReasoningEffort(for: resolvedModel, preferred: "minimal"),
                        maxTokens: budget.maxTokens,
                        maxCompletionTokens: budget.maxCompletionTokens,
                        responseFormat: nil,
                        stream: true,
                        tools: nil
                    )

                    var urlRequest = try self.buildURLRequest()
                    urlRequest.httpBody = try JSONEncoder().encode(request)

                    let (bytes, response) = try await self.session.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: MistralAPIError.invalidResponse)
                        return
                    }

                    if httpResponse.statusCode == 429 {
                        continuation.finish(throwing: MistralAPIError.rateLimited)
                        return
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        continuation.finish(throwing: MistralAPIError.httpError(httpResponse.statusCode, "Stream request failed"))
                        return
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6))

                            if data == "[DONE]" {
                                print("[MistralAPI] streamChat: stream complete")
                                break
                            }

                            guard let jsonData = data.data(using: .utf8) else { continue }

                            do {
                                let chunk = try self.decoder.decode(MistralStreamChunk.self, from: jsonData)
                                if let content = chunk.choices.first?.delta.content {
                                    continuation.yield(content)
                                }
                            } catch {
                                print("[MistralAPI] streamChat: failed to decode chunk: \(error)")
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    print("[MistralAPI] streamChat: error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func resolveModel(_ model: MistralModel) -> String {
        switch model {
        case .smallLatest: return provider.visionModel
        case .largeLatest: return provider.largeModel
        case .ministral8b: return provider.fastModel
        }
    }

    private func resolveReasoningEffort(for resolvedModel: String, preferred: String?) -> String? {
        guard provider == .openai && resolvedModel.hasPrefix("gpt-5") else { return nil }
        return preferred ?? "minimal"
    }

    private func supportsTemperature(for resolvedModel: String) -> Bool {
        // GPT-5 family models reject temperature in chat.completions unless
        // specific non-reasoning modes are enabled.
        !(provider == .openai && resolvedModel.hasPrefix("gpt-5"))
    }

    private func tokenBudget(for resolvedModel: String, maxTokens: Int) -> (maxTokens: Int?, maxCompletionTokens: Int?) {
        // OpenAI deprecates max_tokens for newer reasoning-capable models.
        if provider == .openai && resolvedModel.hasPrefix("gpt-5") {
            // Keep a small floor so quick prompts don't starve, while avoiding
            // excessive token spend that increases latency.
            return (nil, max(maxTokens, 400))
        }
        return (maxTokens, nil)
    }

    private func prepareVisionBase64(_ imageData: Data, maxDimension: CGFloat, compressionQuality: CGFloat) async -> String {
        let optimizedData = await Task.detached(priority: .userInitiated) {
            Self.downsampleJPEGData(imageData, maxDimension: maxDimension, compressionQuality: compressionQuality)
        }.value

        if optimizedData.count != imageData.count {
            print("[MistralAPI] vision image optimized: \(imageData.count) -> \(optimizedData.count) bytes")
        }

        return optimizedData.base64EncodedString()
    }

    private nonisolated static func downsampleJPEGData(_ imageData: Data, maxDimension: CGFloat, compressionQuality: CGFloat) -> Data {
        guard let image = UIImage(data: imageData) else { return imageData }

        let sourceSize = image.size
        let largestSide = max(sourceSize.width, sourceSize.height)
        guard largestSide > 0 else { return imageData }

        let scale = min(1.0, maxDimension / largestSide)
        let targetSize = CGSize(
            width: max(1, floor(sourceSize.width * scale)),
            height: max(1, floor(sourceSize.height * scale))
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return rendered.jpegData(compressionQuality: compressionQuality) ?? imageData
    }

    private nonisolated static func normalizedImageSize(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "256x256", "512x512":
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        default:
            return "512x512"
        }
    }

    private nonisolated static func normalizedImageQuality(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "low", "medium":
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        case "high":
            // Clamp expensive quality to protect UI responsiveness.
            return "medium"
        default:
            return "low"
        }
    }

    private nonisolated static func cleanSuggestionText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let cleaned = trimmed.replacingOccurrences(
            of: #"^\s*(?:[-*•]|\d+[.)])\s*"#,
            with: "",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func parseFallbackSuggestions(_ raw: String) -> [String] {
        let normalized = raw.replacingOccurrences(of: "\r", with: "\n")

        var candidates = normalized
            .components(separatedBy: "\n")
            .map(cleanSuggestionText)
            .filter { !$0.isEmpty }

        if candidates.count < 2 {
            candidates = normalized
                .components(separatedBy: CharacterSet(charactersIn: "|;"))
                .map(cleanSuggestionText)
                .filter { !$0.isEmpty }
        }

        var deduped: [String] = []
        for item in candidates {
            let key = item.lowercased()
            if !deduped.map({ $0.lowercased() }).contains(key) {
                deduped.append(item)
            }
        }
        return deduped
    }

    private nonisolated static func normalizeSuggestionsForLanes(_ suggestions: [String], language: String) -> [String] {
        var output = Array(suggestions.prefix(3))
        if output.count < 1 { output.append(defaultDoSuggestion(language: language)) }
        if output.count < 2 { output.append(defaultUnderstandSuggestion(language: language)) }
        if output.count < 3 { output.append(defaultExploreSuggestion(language: language)) }
        return output
    }

    private nonisolated static func defaultDoSuggestion(language: String) -> String {
        switch language.lowercased() {
        case "ja": return "今すぐ試せる操作を提案"
        default: return "Try one quick actionable step"
        }
    }

    private nonisolated static func defaultUnderstandSuggestion(language: String) -> String {
        switch language.lowercased() {
        case "ja": return "この表示の意味を確認する"
        default: return "Understand what each control means"
        }
    }

    private nonisolated static func defaultExploreSuggestion(language: String) -> String {
        switch language.lowercased() {
        case "ja": return "隠れた便利機能を探す"
        default: return "Explore one hidden useful feature"
        }
    }

    /// Attempts to repair truncated JSON by closing open braces/brackets and unfinished strings.
    private nonisolated static func attemptJSONRepair(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // Remove trailing comma
        while s.hasSuffix(",") { s = String(s.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }

        // Count unmatched openers
        var inString = false
        var escape = false
        var stack: [Character] = []
        for c in s {
            if escape { escape = false; continue }
            if c == "\\" && inString { escape = true; continue }
            if c == "\"" { inString = !inString; continue }
            if inString { continue }
            switch c {
            case "{": stack.append("}")
            case "[": stack.append("]")
            case "}", "]":
                if let last = stack.last, last == c { stack.removeLast() }
            default: break
            }
        }

        // Close unfinished string
        if inString { s += "\"" }
        // Close unmatched openers
        for closer in stack.reversed() { s += String(closer) }

        // Validate
        guard let data = s.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return nil
        }
        return s
    }

    private nonisolated static func isLikelyTruncatedStructuredResponse(_ error: Error) -> Bool {
        if let apiError = error as? MistralAPIError {
            switch apiError {
            case .emptyContent(let details):
                return details.lowercased().contains("finish_reason=length")
            case .decodingError(let underlying):
                if let decodingError = underlying as? DecodingError,
                   case .dataCorrupted(let context) = decodingError {
                    let debug = context.debugDescription.lowercased()
                    if debug.contains("unexpected end of file") || debug.contains("not valid json") {
                        return true
                    }
                }
                let nsError = underlying as NSError
                return nsError.domain == NSCocoaErrorDomain && nsError.code == 3840
            default:
                return false
            }
        }
        let generic = String(describing: error).lowercased()
        return generic.contains("finish_reason=length") || generic.contains("unexpected end of file")
    }

    private nonisolated static func escapeHTML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private nonisolated static func localArtifactFallbackHTML(goal: String, language: String) -> String {
        let safeGoal = escapeHTML(goal.trimmingCharacters(in: .whitespacesAndNewlines))
        let title = language.lowercased() == "ja" ? "すぐできる実行プラン" : "Quick Action Plan"
        let verdict = language.lowercased() == "ja" ? "短い手順で今すぐ進めましょう。" : "You can make progress in 3 quick steps."
        let step1 = language.lowercased() == "ja" ? "目的を一文で確認する" : "Clarify the goal in one sentence"
        let step2 = language.lowercased() == "ja" ? "最初の低リスク行動を実行" : "Do the first low-risk action now"
        let step3 = language.lowercased() == "ja" ? "結果を確認して次へ進む" : "Check result and move to next step"
        let whyText = language.lowercased() == "ja" ? "短い行動ループで迷いと失敗を減らします。" : "Short action loops reduce uncertainty and failure."

        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;background:transparent;color:#fff;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}
        .card{background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.18);backdrop-filter:blur(16px);border-radius:16px;padding:14px}
        .muted{color:rgba(255,255,255,.75);font-size:12px}.step{margin:10px 0;padding:10px;border:1px solid rgba(255,255,255,.16);border-radius:12px}
        .badge{font-size:11px;padding:2px 8px;border-radius:999px;background:rgba(34,197,94,.28)}button{min-height:44px;border:0;border-radius:10px;padding:0 12px}
        .done{background:#22c55e;color:#062b12;font-weight:700}.fail{background:rgba(255,255,255,.18);color:#fff}.row{display:flex;gap:8px;margin-top:8px}.hide{display:none}
        </style></head><body><div class="card"><div style="font-weight:800">\(title)</div><div class="muted">\(verdict)</div>
        <div class="muted" style="margin-top:6px">\(safeGoal)</div>
        <div class="step" id="s1"><span class="badge">low</span><div>\(step1)</div><div class="row"><button class="done" onclick="done('s1')">Done</button><button class="fail" onclick="fail('s1')">Didn't work</button></div></div>
        <div class="step" id="s2"><span class="badge">medium</span><div>\(step2)</div><div class="row"><button class="done" onclick="done('s2')">Done</button><button class="fail" onclick="fail('s2')">Didn't work</button></div></div>
        <div class="step" id="s3"><span class="badge">low</span><div>\(step3)</div><div class="row"><button class="done" onclick="done('s3',true)">Done</button><button class="fail" onclick="fail('s3')">Didn't work</button></div></div>
        <details><summary>Why?</summary><div class="muted">\(whyText)</div></details><div id="msg" class="muted"></div></div>
        <script>function done(id,last){try{AGI.haptic('success');AGI.done(id)}catch(e){};document.getElementById(id)?.classList.add('hide');if(last){try{AGI.sound('success');AGI.done('all')}catch(e){};document.getElementById('msg').textContent='Goal marked complete.'}}
        function fail(id){try{AGI.haptic('warning');AGI.failed(id,'fallback needed')}catch(e){};document.getElementById('msg').textContent='Try the safer fallback and continue.'}</script>
        </body></html>
        """
    }

    private func buildURLRequest() throws -> URLRequest {
        let key = apiKey
        guard !key.isEmpty else { throw MistralAPIError.noAPIKey }

        let masked = key.count > 8 ? "\(key.prefix(4))...\(key.suffix(4))" : "***"
        print("[MistralAPI] using \(provider.rawValue) key: \(masked) (length=\(key.count))")

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Generic structured request: sends messages, parses JSON response into a Decodable type
    private func sendStructuredRequest<T: Decodable>(
        model: MistralModel,
        messages: [ChatMessage],
        responseFormat: ResponseFormat,
        temperature: Double,
        maxTokens: Int,
        reasoningEffort: String? = nil,
        tools: [MistralTool]? = nil
    ) async throws -> T {
        let resolvedModel = resolveModel(model)
        let budget = tokenBudget(for: resolvedModel, maxTokens: maxTokens)
        let request = MistralRequest(
            model: resolvedModel,
            messages: messages,
            temperature: supportsTemperature(for: resolvedModel) ? temperature : nil,
            reasoningEffort: resolveReasoningEffort(for: resolvedModel, preferred: reasoningEffort),
            maxTokens: budget.maxTokens,
            maxCompletionTokens: budget.maxCompletionTokens,
            responseFormat: responseFormat,
            stream: false,
            tools: tools
        )

        var urlRequest = try buildURLRequest()
        let body = try JSONEncoder().encode(request)
        urlRequest.httpBody = body

        print("[MistralAPI] sending request to \(resolvedModel) via \(provider.rawValue), body size=\(body.count) bytes")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MistralAPIError.invalidResponse
        }

        print("[MistralAPI] response status=\(httpResponse.statusCode), size=\(data.count) bytes")

        if httpResponse.statusCode == 429 {
            throw MistralAPIError.rateLimited
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[MistralAPI] error response: \(errorBody)")
            throw MistralAPIError.httpError(httpResponse.statusCode, errorBody)
        }

        let mistralResponse: MistralResponse
        do {
            mistralResponse = try decoder.decode(MistralResponse.self, from: data)
        } catch {
            print("[MistralAPI] failed to decode MistralResponse: \(error)")
            throw MistralAPIError.decodingError(error)
        }

        if let usage = mistralResponse.usage {
            print("[MistralAPI] tokens: prompt=\(usage.promptTokens), completion=\(usage.completionTokens), total=\(usage.totalTokens)")
        }

        guard let firstChoice = mistralResponse.choices.first else {
            throw MistralAPIError.invalidResponse
        }
        let content = firstChoice.message.content
        let finishReason = firstChoice.finishReason ?? "unknown"
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedContent.isEmpty {
            throw MistralAPIError.emptyContent("finish_reason=\(finishReason), model=\(resolvedModel)")
        }

        guard let contentData = trimmedContent.data(using: .utf8) else {
            throw MistralAPIError.invalidResponse
        }

        do {
            let result = try decoder.decode(T.self, from: contentData)
            return result
        } catch {
            print("[MistralAPI] failed to decode structured output: \(error)")
            print("[MistralAPI] finish_reason=\(finishReason)")
            print("[MistralAPI] raw content: \(trimmedContent.prefix(500))")

            // Salvage attempt: try to repair truncated/partial JSON
            if let repaired = Self.attemptJSONRepair(trimmedContent),
               let repairedData = repaired.data(using: .utf8),
               let result = try? decoder.decode(T.self, from: repairedData) {
                print("[MistralAPI] JSON repair succeeded")
                return result
            }

            if finishReason == "length" {
                throw MistralAPIError.emptyContent("finish_reason=length, model=\(resolvedModel)")
            }
            throw MistralAPIError.decodingError(error)
        }
    }

    private func sendTextRequest(
        model: MistralModel,
        messages: [ChatMessage],
        temperature: Double,
        maxTokens: Int,
        reasoningEffort: String? = nil
    ) async throws -> String {
        let resolvedModel = resolveModel(model)
        let budget = tokenBudget(for: resolvedModel, maxTokens: maxTokens)
        let request = MistralRequest(
            model: resolvedModel,
            messages: messages,
            temperature: supportsTemperature(for: resolvedModel) ? temperature : nil,
            reasoningEffort: resolveReasoningEffort(for: resolvedModel, preferred: reasoningEffort),
            maxTokens: budget.maxTokens,
            maxCompletionTokens: budget.maxCompletionTokens,
            responseFormat: nil,
            stream: false,
            tools: nil
        )

        var urlRequest = try buildURLRequest()
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MistralAPIError.invalidResponse
        }
        if httpResponse.statusCode == 429 {
            throw MistralAPIError.rateLimited
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MistralAPIError.httpError(httpResponse.statusCode, errorBody)
        }

        let mistralResponse = try decoder.decode(MistralResponse.self, from: data)
        guard let firstChoice = mistralResponse.choices.first else {
            throw MistralAPIError.invalidResponse
        }

        let content = firstChoice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            throw MistralAPIError.emptyContent("finish_reason=\(firstChoice.finishReason ?? "unknown"), model=\(resolvedModel)")
        }
        return content
    }

    // MARK: - JSON Schemas for Structured Output

    static let panelAnalysisSchema: JSONSchemaValue = .object([
        "type": .string("object"),
        "properties": .object([
            "panel": .object([
                "type": .string("object"),
                "description": .string("Information about the detected panel"),
                "properties": .object([
                    "deviceType": .object([
                        "type": .string("string"),
                        "description": .string("Detected device type, e.g. intercom, thermostat")
                    ]),
                    "manufacturer": .object([
                        "type": .string("string"),
                        "description": .string("Manufacturer name if visible, empty string if not")
                    ]),
                    "model": .object([
                        "type": .string("string"),
                        "description": .string("Model identifier if visible, empty string if not")
                    ])
                ]),
                "required": .array([.string("deviceType"), .string("manufacturer"), .string("model")]),
                "additionalProperties": .bool(false)
            ]),
            "elements": .object([
                "type": .string("array"),
                "description": .string("All detected UI elements on the panel"),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("Unique element identifier, e.g. btn_1, display_1")
                        ]),
                        "elementType": .object([
                            "type": .string("string"),
                            "description": .string("Element type: button, display, label, icon, led, switch, slider, speaker, microphone, camera, other")
                        ]),
                        "bbox": .object([
                            "type": .string("object"),
                            "description": .string("Bounding box as normalized 0.0-1.0 coordinates"),
                            "properties": .object([
                                "x": .object(["type": .string("number"), "description": .string("Left edge, 0.0-1.0")]),
                                "y": .object(["type": .string("number"), "description": .string("Top edge, 0.0-1.0")]),
                                "width": .object(["type": .string("number"), "description": .string("Width, 0.0-1.0")]),
                                "height": .object(["type": .string("number"), "description": .string("Height, 0.0-1.0")])
                            ]),
                            "required": .array([.string("x"), .string("y"), .string("width"), .string("height")]),
                            "additionalProperties": .bool(false)
                        ]),
                        "originalText": .object([
                            "type": .string("string"),
                            "description": .string("Original text visible on or near the element, empty string if none")
                        ]),
                        "translatedText": .object([
                            "type": .string("string"),
                            "description": .string("Translation of original text to user language, empty string if same or no text")
                        ]),
                        "confidence": .object([
                            "type": .string("number"),
                            "description": .string("Detection confidence 0.0-1.0")
                        ]),
                        "evidenceType": .object([
                            "type": .string("string"),
                            "description": .string("Evidence basis: ocr, icon_inference, layout_inference, manual_pack")
                        ])
                    ]),
                    "required": .array([
                        .string("id"), .string("elementType"), .string("bbox"),
                        .string("originalText"), .string("translatedText"),
                        .string("confidence"), .string("evidenceType")
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ]),
            "globalConfidence": .object([
                "type": .string("number"),
                "description": .string("Overall analysis confidence 0.0-1.0")
            ]),
            "warnings": .object([
                "type": .string("array"),
                "description": .string("Any warnings about uncertain detections"),
                "items": .object(["type": .string("string")])
            ])
        ]),
        "required": .array([.string("panel"), .string("elements"), .string("globalConfidence"), .string("warnings")]),
        "additionalProperties": .bool(false)
    ])

    static let suggestionsSchema: JSONSchemaValue = .object([
        "type": .string("object"),
        "properties": .object([
            "suggestions": .object([
                "type": .string("array"),
                "description": .string("Exactly 3 suggested actions in order: do now, understand, explore"),
                "items": .object(["type": .string("string")])
            ])
        ]),
        "required": .array([.string("suggestions")]),
        "additionalProperties": .bool(false)
    ])

    static let actionWizardSchema: JSONSchemaValue = .object([
        "type": .string("object"),
        "properties": .object([
            "goal": .object([
                "type": .string("string"),
                "description": .string("The user goal being addressed")
            ]),
            "riskTier": .object([
                "type": .string("string"),
                "description": .string("Risk classification: low, medium, or high")
            ]),
            "requiresConfirmation": .object([
                "type": .string("boolean"),
                "description": .string("Whether each step requires user confirmation before proceeding")
            ]),
            "steps": .object([
                "type": .string("array"),
                "description": .string("Ordered list of action steps"),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "stepNumber": .object([
                            "type": .string("integer"),
                            "description": .string("Step order number starting from 1")
                        ]),
                        "instruction": .object([
                            "type": .string("string"),
                            "description": .string("Clear instruction for this step")
                        ]),
                        "elementId": .object([
                            "type": .string("string"),
                            "description": .string("ID of the panel element to interact with")
                        ]),
                        "action": .object([
                            "type": .string("string"),
                            "description": .string("Action to perform: press, hold, turn, slide, read, wait")
                        ]),
                        "confidence": .object([
                            "type": .string("number"),
                            "description": .string("Confidence for this step 0.0-1.0")
                        ]),
                        "evidence": .object([
                            "type": .string("string"),
                            "description": .string("Explanation of why this step is suggested based on detected elements")
                        ])
                    ]),
                    "required": .array([
                        .string("stepNumber"), .string("instruction"), .string("elementId"),
                        .string("action"), .string("confidence"), .string("evidence")
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ]),
            "fallbacks": .object([
                "type": .string("array"),
                "description": .string("Fallback suggestions if instructions cannot be confidently provided"),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "suggestion": .object([
                            "type": .string("string"),
                            "description": .string("Fallback action suggestion")
                        ]),
                        "reason": .object([
                            "type": .string("string"),
                            "description": .string("Why this fallback is suggested")
                        ])
                    ]),
                    "required": .array([.string("suggestion"), .string("reason")]),
                    "additionalProperties": .bool(false)
                ])
            ])
        ]),
        "required": .array([
            .string("goal"), .string("riskTier"), .string("requiresConfirmation"),
            .string("steps"), .string("fallbacks")
        ]),
        "additionalProperties": .bool(false)
    ])

    static let artifactSchema: JSONSchemaValue = .object([
        "type": .string("object"),
        "properties": .object([
            "html": .object([
                "type": .string("string"),
                "description": .string("Self-contained HTML with inline CSS and JS. Dark theme, mobile-first, under 4000 chars.")
            ])
        ]),
        "required": .array([.string("html")]),
        "additionalProperties": .bool(false)
    ])

    static let interviewSchema: JSONSchemaValue = .object([
        "type": .string("object"),
        "properties": .object([
            "scene_description": .object([
                "type": .string("string"),
                "description": .string("Short natural-language description of what the camera sees, max 10 words")
            ]),
            "question": .object([
                "type": .string("string"),
                "description": .string("A question asking the user what they want to do with this")
            ]),
            "chips": .object([
                "type": .string("array"),
                "description": .string("Exactly 4 smart reply chips, each max 6 words"),
                "items": .object(["type": .string("string")])
            ]),
            "confidence": .object([
                "type": .string("number"),
                "description": .string("How confident you are in understanding this scene, 0.0 to 1.0")
            ]),
            "risk_level": .object([
                "type": .string("string"),
                "description": .string("Risk level of interacting with this: low, medium, or high"),
                "enum": .array([.string("low"), .string("medium"), .string("high")])
            ])
        ]),
        "required": .array([.string("scene_description"), .string("question"), .string("chips"), .string("confidence"), .string("risk_level")]),
        "additionalProperties": .bool(false)
    ])

    static let companionObservationSchema: JSONSchemaValue = .object([
        "type": .string("object"),
        "properties": .object([
            "should_speak": .object([
                "type": .string("boolean"),
                "description": .string("Whether the companion has something new and interesting to say")
            ]),
            "scene_description": .object([
                "type": .string("string"),
                "description": .string("Short description of what the camera sees, max 8 words")
            ]),
            "message": .object([
                "type": .string("string"),
                "description": .string("What the companion says to the user, 1-2 sentences max")
            ]),
            "chips": .object([
                "type": .string("array"),
                "description": .string("2-4 smart reply chips, each max 6 words"),
                "items": .object(["type": .string("string")])
            ]),
            "quality_confidence": .object([
                "type": .string("number"),
                "description": .string("How confident you are in understanding this scene, 0.0 to 1.0")
            ]),
            "safety_confidence": .object([
                "type": .string("number"),
                "description": .string("How safe it is to interact with what you see, 0.0 to 1.0")
            ]),
            "risk_level": .object([
                "type": .string("string"),
                "description": .string("Risk level: low, medium, or high"),
                "enum": .array([.string("low"), .string("medium"), .string("high")])
            ]),
            "inner_voice_stat": .object([
                "type": .string("string"),
                "description": .string("Stat raw value when inner voice speaks (e.g. inland_empire), or empty string")
            ]),
            "inner_voice_difficulty": .object([
                "type": .string("string"),
                "description": .string("Difficulty level for inner voice (trivial/easy/medium/challenging/heroic/legendary), or empty string")
            ]),
            "chip_checks": .object([
                "type": .string("array"),
                "description": .string("Skill check badges for chips, 0-2 items. Empty array if none."),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "chip_index": .object([
                            "type": .string("integer"),
                            "description": .string("0-based index into chips array")
                        ]),
                        "stat": .object([
                            "type": .string("string"),
                            "description": .string("Stat raw value for this check")
                        ]),
                        "difficulty": .object([
                            "type": .string("string"),
                            "description": .string("Difficulty: trivial/easy/medium/challenging/heroic/legendary")
                        ]),
                        "chance": .object([
                            "type": .string("integer"),
                            "description": .string("Percentage chance of success, 1-99")
                        ])
                    ]),
                    "required": .array([.string("chip_index"), .string("stat"), .string("difficulty"), .string("chance")]),
                    "additionalProperties": .bool(false)
                ])
            ])
        ]),
        "required": .array([
            .string("should_speak"), .string("scene_description"), .string("message"),
            .string("chips"), .string("quality_confidence"), .string("safety_confidence"), .string("risk_level"),
            .string("inner_voice_stat"), .string("inner_voice_difficulty"), .string("chip_checks")
        ]),
        "additionalProperties": .bool(false)
    ])

    // MARK: - OCR Structured Output

    struct OCRTextRegion: Codable {
        let text: String
        let translation: String
        let language: String
        let textType: String  // "label", "heading", "body", "button", "warning", "number"
        let confidence: Double

        enum CodingKeys: String, CodingKey {
            case text, translation, language
            case textType = "text_type"
            case confidence
        }
    }

    struct OCRResult: Codable {
        let regions: [OCRTextRegion]
        let summary: String
        let languagesDetected: [String]

        enum CodingKeys: String, CodingKey {
            case regions, summary
            case languagesDetected = "languages_detected"
        }
    }

    func extractText(imageData: Data, targetLanguage: String = "en") async throws -> OCRResult {
        let base64 = await prepareVisionBase64(imageData, maxDimension: 768, compressionQuality: 0.5)
        let imageDetail = provider == .openai ? "low" : nil

        let systemPrompt = """
        You are a precise OCR system. Extract ALL visible text from the image.

        For each text region:
        - text: the exact text as written (preserve original language)
        - translation: translation to \(targetLanguage) (if already in \(targetLanguage), repeat the text)
        - language: ISO 639-1 language code of the original text
        - text_type: one of "label", "heading", "body", "button", "warning", "number"
        - confidence: 0.0-1.0 how confident you are in the reading

        Also provide:
        - summary: one sentence describing what this text collectively represents
        - languages_detected: array of unique language codes found

        Read everything visible. Include small labels, numbers, warnings, brand names.
        """

        let messages = [
            ChatMessage.system(systemPrompt),
            ChatMessage.userWithImage(
                "Extract all text from this image.",
                imageBase64: base64,
                imageDetail: imageDetail
            )
        ]

        let responseFormat = ResponseFormat(
            type: "json_schema",
            jsonSchema: JSONSchemaWrapper(
                name: "ocr_extraction",
                schema: Self.ocrSchema,
                strict: true
            )
        )

        return try await sendStructuredRequest(
            model: .smallLatest,
            messages: messages,
            responseFormat: responseFormat,
            temperature: 0.1,
            maxTokens: 600
        )
    }

    static let ocrSchema: JSONSchemaValue = .object([
        "type": .string("object"),
        "properties": .object([
            "regions": .object([
                "type": .string("array"),
                "description": .string("All text regions found in the image"),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "text": .object([
                            "type": .string("string"),
                            "description": .string("Exact text as written")
                        ]),
                        "translation": .object([
                            "type": .string("string"),
                            "description": .string("Translation to target language")
                        ]),
                        "language": .object([
                            "type": .string("string"),
                            "description": .string("ISO 639-1 language code")
                        ]),
                        "text_type": .object([
                            "type": .string("string"),
                            "description": .string("Type of text"),
                            "enum": .array([.string("label"), .string("heading"), .string("body"), .string("button"), .string("warning"), .string("number")])
                        ]),
                        "confidence": .object([
                            "type": .string("number"),
                            "description": .string("Reading confidence 0.0-1.0")
                        ])
                    ]),
                    "required": .array([.string("text"), .string("translation"), .string("language"), .string("text_type"), .string("confidence")]),
                    "additionalProperties": .bool(false)
                ])
            ]),
            "summary": .object([
                "type": .string("string"),
                "description": .string("One sentence summary of the text content")
            ]),
            "languages_detected": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
                "description": .string("Unique language codes found")
            ])
        ]),
        "required": .array([.string("regions"), .string("summary"), .string("languages_detected")]),
        "additionalProperties": .bool(false)
    ])

    static let objectDetectionSchema: JSONSchemaValue = .object([
        "type": .string("object"),
        "properties": .object([
            "objects": .object([
                "type": .string("array"),
                "description": .string("3-6 detected objects with notes"),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "label": .object([
                            "type": .string("string"),
                            "description": .string("Short object name, 2-4 words")
                        ]),
                        "bbox": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "x": .object(["type": .string("number")]),
                                "y": .object(["type": .string("number")]),
                                "width": .object(["type": .string("number")]),
                                "height": .object(["type": .string("number")])
                            ]),
                            "required": .array([.string("x"), .string("y"), .string("width"), .string("height")]),
                            "additionalProperties": .bool(false)
                        ]),
                        "note": .object([
                            "type": .string("string"),
                            "description": .string("Short opinionated observation, max 80 chars")
                        ]),
                        "confidence": .object([
                            "type": .string("number"),
                            "description": .string("Detection confidence 0.0-1.0")
                        ]),
                        "risk_level": .object([
                            "type": .string("string"),
                            "description": .string("Risk level: low, medium, or high"),
                            "enum": .array([.string("low"), .string("medium"), .string("high")])
                        ])
                    ]),
                    "required": .array([.string("label"), .string("bbox"), .string("note"), .string("confidence"), .string("risk_level")]),
                    "additionalProperties": .bool(false)
                ])
            ])
        ]),
        "required": .array([.string("objects")]),
        "additionalProperties": .bool(false)
    ])
}
