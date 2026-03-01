//
//  KnowledgeBase.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

struct KnowledgeEntry: Codable, Identifiable {
    let id: UUID
    let deviceType: String
    let keywords: [String]
    let panelAnalysis: PanelAnalysis
    let qualityScore: Double
    let timestamp: Date

    init(deviceType: String, keywords: [String], panelAnalysis: PanelAnalysis, qualityScore: Double) {
        self.id = UUID()
        self.deviceType = deviceType
        self.keywords = keywords
        self.panelAnalysis = panelAnalysis
        self.qualityScore = qualityScore
        self.timestamp = Date()
    }
}

final class KnowledgeBase {
    static let shared = KnowledgeBase()

    private var entries: [KnowledgeEntry] = []
    private let maxEntries = 100

    private static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("knowledge_base.json")
    }

    private init() {
        load()
    }

    var entryCount: Int { entries.count }

    func findSimilar(deviceType: String, keywords: [String]) -> [KnowledgeEntry] {
        let normalizedType = deviceType.lowercased()
        let normalizedKeywords = Set(keywords.map { $0.lowercased() })

        return entries
            .filter { entry in
                let typeMatch = entry.deviceType.lowercased() == normalizedType
                let keywordOverlap = Set(entry.keywords.map { $0.lowercased() })
                    .intersection(normalizedKeywords)
                return typeMatch || !keywordOverlap.isEmpty
            }
            .sorted { $0.qualityScore > $1.qualityScore }
            .prefix(3)
            .map { $0 }
    }

    func addEntry(_ entry: KnowledgeEntry) {
        entries.append(entry)

        // Prune by quality score if over limit
        if entries.count > maxEntries {
            entries.sort { $0.qualityScore > $1.qualityScore }
            entries = Array(entries.prefix(maxEntries))
        }

        save()
    }

    func contextSummary(for entries: [KnowledgeEntry]) -> String {
        guard !entries.isEmpty else { return "" }

        var summary = "Previous analyses of similar panels:\n"
        for (i, entry) in entries.enumerated() {
            summary += "  [\(i+1)] Device: \(entry.deviceType), "
            summary += "Elements: \(entry.panelAnalysis.elements.count), "
            summary += "Confidence: \(String(format: "%.2f", entry.panelAnalysis.globalConfidence)), "
            summary += "Quality: \(String(format: "%.2f", entry.qualityScore))\n"

            let elementSummary = entry.panelAnalysis.elements.prefix(5).map { el in
                "\(el.kind)(\(el.elementId))"
            }.joined(separator: ", ")
            summary += "    Elements: \(elementSummary)\n"
        }
        return summary
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            print("[KnowledgeBase] Failed to save: \(error)")
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: Self.fileURL)
            entries = try JSONDecoder().decode([KnowledgeEntry].self, from: data)
        } catch {
            entries = []
        }
    }
}
