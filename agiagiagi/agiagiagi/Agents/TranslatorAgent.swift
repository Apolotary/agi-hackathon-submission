//
//  TranslatorAgent.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

struct TranslationResult {
    let detectedLanguages: [String]
    let translations: [String: String]  // originalText -> translatedText
    let elementTranslations: [String: String]  // elementId -> translatedText
}

actor TranslatorAgent {
    static let agentName = "Translator"

    private let api = MistralAPI.shared
    private let logCallback: @Sendable (AgentLog) -> Void

    init(logCallback: @escaping @Sendable (AgentLog) -> Void) {
        self.logCallback = logCallback
    }

    func translate(imageData: Data, userProfile: UserProfile, partialAnalysis: PanelAnalysis?) async throws -> TranslationResult {
        log(.spawned, "Initializing OCR and translation agent")

        log(.working, "Reading text from panel image")

        // Use the existing analyze endpoint which already does OCR + translation
        let analysis = try await api.analyzePanel(
            imageData: imageData,
            userProfile: userProfile,
            deviceHint: partialAnalysis?.panel.deviceFamily
        )

        // Extract translation mappings
        var translations: [String: String] = [:]
        var elementTranslations: [String: String] = [:]
        var detectedLanguages: Set<String> = []

        for element in analysis.elements {
            let rawText = element.displayLabel
            if !rawText.isEmpty {
                // Check if any translation exists
                for trans in element.translations {
                    translations[rawText] = trans.text
                    elementTranslations[element.elementId] = trans.text
                    detectedLanguages.insert(trans.language)
                }
            }
        }

        let langList = detectedLanguages.isEmpty ? ["unknown"] : Array(detectedLanguages)
        log(.done, "Translated \(translations.count) text elements, detected languages: \(langList.joined(separator: ", "))")

        return TranslationResult(
            detectedLanguages: langList,
            translations: translations,
            elementTranslations: elementTranslations
        )
    }

    private func log(_ status: AgentStatus, _ message: String) {
        let entry = AgentLog(agentName: Self.agentName, status: status, message: message)
        logCallback(entry)
    }
}
