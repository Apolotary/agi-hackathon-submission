//
//  PanelAnalysis.swift
//  agiagiagi
//
//  Created by Bektur Ryskeldiev on 2026/02/28.
//

import Foundation

struct BBox: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    // Accept both "w"/"h" and "width"/"height" from different providers
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexKeys.self)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = (try? container.decode(Double.self, forKey: .width)) ?? (try? container.decode(Double.self, forKey: .w)) ?? 0
        height = (try? container.decode(Double.self, forKey: .height)) ?? (try? container.decode(Double.self, forKey: .h)) ?? 0
    }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    private enum FlexKeys: String, CodingKey {
        case x, y, w, h, width, height
    }
}

struct Evidence: Codable {
    let type: String
    let rawValue: String
    let confidence: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"
        rawValue = (try? container.decode(String.self, forKey: .rawValue)) ?? ""
        confidence = (try? container.decode(Double.self, forKey: .confidence)) ?? 0.5
    }

    enum CodingKeys: String, CodingKey {
        case type
        case rawValue = "raw_value"
        case confidence
    }
}

struct Translation: Codable {
    let language: String
    let text: String
}

struct ElementLabel: Codable {
    let rawText: String
    let normalizedText: String

    enum CodingKeys: String, CodingKey {
        case rawText = "raw_text"
        case normalizedText = "normalized_text"
    }
}

struct PanelElement: Codable, Identifiable {
    let elementId: String
    let kind: String
    let bbox: BBox
    let label: ElementLabel?
    let translations: [Translation]
    let confidence: Double
    let evidence: [Evidence]
    // Extra fields from OpenAI responses
    let originalText: String?
    let translatedText: String?

    var id: String { elementId }

    var displayLabel: String {
        label?.rawText ?? originalText ?? translatedText ?? kind
    }

    var displayTranslation: String? {
        translations.first?.text ?? translatedText
    }

    init(elementId: String, kind: String, bbox: BBox, label: ElementLabel?, translations: [Translation], confidence: Double, evidence: [Evidence], originalText: String? = nil, translatedText: String? = nil) {
        self.elementId = elementId
        self.kind = kind
        self.bbox = bbox
        self.label = label
        self.translations = translations
        self.confidence = confidence
        self.evidence = evidence
        self.originalText = originalText
        self.translatedText = translatedText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        elementId = (try? container.decode(String.self, forKey: .elementId)) ?? (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        kind = (try? container.decode(String.self, forKey: .kind)) ?? (try? container.decode(String.self, forKey: .elementType)) ?? "unknown"
        bbox = try container.decode(BBox.self, forKey: .bbox)
        label = try? container.decode(ElementLabel.self, forKey: .label)
        translations = (try? container.decode([Translation].self, forKey: .translations)) ?? []
        confidence = (try? container.decode(Double.self, forKey: .confidence)) ?? 0.5
        evidence = (try? container.decode([Evidence].self, forKey: .evidence)) ?? []
        originalText = try? container.decode(String.self, forKey: .originalText)
        translatedText = try? container.decode(String.self, forKey: .translatedText)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(elementId, forKey: .elementId)
        try container.encode(kind, forKey: .kind)
        try container.encode(bbox, forKey: .bbox)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encode(translations, forKey: .translations)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(evidence, forKey: .evidence)
        try container.encodeIfPresent(originalText, forKey: .originalText)
        try container.encodeIfPresent(translatedText, forKey: .translatedText)
    }

    enum CodingKeys: String, CodingKey {
        case elementId = "element_id"
        case id
        case kind
        case elementType
        case bbox
        case label
        case translations
        case confidence
        case evidence
        case originalText
        case translatedText
        case evidenceType
    }
}

struct PanelInfo: Codable {
    let deviceFamily: String
    let manufacturer: String?
    let modelHint: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Accept "device_family" or "deviceType"
        deviceFamily = (try? container.decode(String.self, forKey: .deviceFamily))
            ?? (try? container.decode(String.self, forKey: .deviceType))
            ?? "unknown"
        manufacturer = try? container.decode(String.self, forKey: .manufacturer)
        modelHint = (try? container.decode(String.self, forKey: .modelHint))
            ?? (try? container.decode(String.self, forKey: .model))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceFamily, forKey: .deviceFamily)
        try container.encodeIfPresent(manufacturer, forKey: .manufacturer)
        try container.encodeIfPresent(modelHint, forKey: .modelHint)
    }

    enum CodingKeys: String, CodingKey {
        case deviceFamily = "device_family"
        case deviceType
        case manufacturer
        case modelHint = "model_hint"
        case model
    }
}

struct PanelAnalysis: Codable {
    let panel: PanelInfo
    let elements: [PanelElement]
    let globalConfidence: Double
    let warnings: [String]

    init(panel: PanelInfo, elements: [PanelElement], globalConfidence: Double, warnings: [String]) {
        self.panel = panel
        self.elements = elements
        self.globalConfidence = globalConfidence
        self.warnings = warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        panel = try container.decode(PanelInfo.self, forKey: .panel)
        elements = (try? container.decode([PanelElement].self, forKey: .elements)) ?? []
        globalConfidence = (try? container.decode(Double.self, forKey: .globalConfidence)) ?? 0.5
        warnings = (try? container.decode([String].self, forKey: .warnings)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case panel
        case elements
        case globalConfidence = "global_confidence"
        case warnings
    }
}
