//
//  InteractionStore.swift
//  agiagiagi
//
//  Created by Bektur Ryskeldiev on 2026/02/28.
//

import Foundation
import SwiftUI

struct PanelInteraction: Codable, Identifiable {
    let id: UUID
    let imageData: Data
    let panelAnalysis: PanelAnalysis?
    let actionWizard: ActionWizard?
    let timestamp: Date
    let deviceFamily: String
    let goal: String?

    init(imageData: Data, panelAnalysis: PanelAnalysis?, actionWizard: ActionWizard?, deviceFamily: String, goal: String?) {
        self.id = UUID()
        self.imageData = imageData
        self.panelAnalysis = panelAnalysis
        self.actionWizard = actionWizard
        self.timestamp = Date()
        self.deviceFamily = deviceFamily
        self.goal = goal
    }

    var thumbnailImage: UIImage? {
        UIImage(data: imageData)
    }
}

@Observable
final class InteractionStore {
    static let shared = InteractionStore()

    var interactions: [PanelInteraction] = []

    private static let maxInteractions = 20

    private static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("interactions.json")
    }

    private init() {
        load()
    }

    func add(_ interaction: PanelInteraction) {
        interactions.insert(interaction, at: 0)
        if interactions.count > Self.maxInteractions {
            interactions = Array(interactions.prefix(Self.maxInteractions))
        }
        save()
    }

    func remove(at offsets: IndexSet) {
        interactions.remove(atOffsets: offsets)
        save()
    }

    func clearAll() {
        interactions.removeAll()
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(interactions)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            print("Failed to save interactions: \(error)")
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: Self.fileURL)
            interactions = try JSONDecoder().decode([PanelInteraction].self, from: data)
        } catch {
            interactions = []
        }
    }
}
