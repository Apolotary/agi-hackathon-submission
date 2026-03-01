//
//  CrowdNote.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

/// A detected object or region with an AI-generated note anchored to a camera position.
struct CrowdNote: Identifiable {
    let id: UUID
    let trackId: Int            // stable ID across frames
    let label: String           // e.g. "button", "thermostat dial", "warning sign"
    var bbox: NormalizedBBox    // 0-1 normalized
    var note: String            // short AI note (<= 90 chars)
    var confidence: Double
    let riskLevel: String       // "low", "medium", "high"
    let timestamp: Date
    var pinned: Bool
    var hidden: Bool
    var expanded: Bool          // user tapped to expand

    init(
        trackId: Int,
        label: String,
        bbox: NormalizedBBox,
        note: String,
        confidence: Double = 0.7,
        riskLevel: String = "low"
    ) {
        self.id = UUID()
        self.trackId = trackId
        self.label = label
        self.bbox = bbox
        self.note = note
        self.confidence = confidence
        self.riskLevel = riskLevel
        self.timestamp = Date()
        self.pinned = false
        self.hidden = false
        self.expanded = false
    }
}

struct NormalizedBBox: Codable {
    var x: Double      // left edge, 0-1
    var y: Double      // top edge, 0-1
    var width: Double   // 0-1
    var height: Double  // 0-1

    /// Center point
    var centerX: Double { x + width / 2 }
    var centerY: Double { y + height / 2 }
}

// MARK: - API Response

struct DetectedObject: Codable {
    let label: String
    let bbox: NormalizedBBox
    let note: String
    let confidence: Double
    let riskLevel: String

    enum CodingKeys: String, CodingKey {
        case label, bbox, note, confidence
        case riskLevel = "risk_level"
    }
}

struct ObjectDetectionResponse: Codable {
    let objects: [DetectedObject]
}
