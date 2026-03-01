//
//  WellbeingStore.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

// MARK: - Lens Ledger (objects seen)

struct LensLedgerEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let label: String
    let confidence: Double
    let scene: String
    let goal: String
    let deleted: Bool

    init(label: String, confidence: Double, scene: String, goal: String = "") {
        self.id = UUID()
        self.timestamp = Date()
        self.label = label
        self.confidence = confidence
        self.scene = scene
        self.goal = goal
        self.deleted = false
    }

    func softDeleted() -> LensLedgerEntry {
        LensLedgerEntry(id: id, timestamp: timestamp, label: label, confidence: confidence, scene: scene, goal: goal, deleted: true)
    }

    private init(id: UUID, timestamp: Date, label: String, confidence: Double, scene: String, goal: String, deleted: Bool) {
        self.id = id; self.timestamp = timestamp; self.label = label
        self.confidence = confidence; self.scene = scene; self.goal = goal; self.deleted = deleted
    }
}

// MARK: - Poetry/Text Log (texts read)

struct PoetryLogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let excerpt: String
    let sourceType: String   // "ocr", "sign", "label", "document"
    let tags: [String]
    let deleted: Bool

    init(excerpt: String, sourceType: String = "ocr", tags: [String] = []) {
        self.id = UUID()
        self.timestamp = Date()
        self.excerpt = excerpt
        self.sourceType = sourceType
        self.tags = tags
        self.deleted = false
    }

    func softDeleted() -> PoetryLogEntry {
        PoetryLogEntry(id: id, timestamp: timestamp, excerpt: excerpt, sourceType: sourceType, tags: tags, deleted: true)
    }

    private init(id: UUID, timestamp: Date, excerpt: String, sourceType: String, tags: [String], deleted: Bool) {
        self.id = id; self.timestamp = timestamp; self.excerpt = excerpt
        self.sourceType = sourceType; self.tags = tags; self.deleted = deleted
    }
}

// MARK: - One Minute Mirror (daily micro-reflection)

struct MirrorEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let mood: Int          // 1-5
    let note: String       // optional one-line note
    let deleted: Bool

    init(mood: Int, note: String = "") {
        self.id = UUID()
        self.timestamp = Date()
        self.mood = max(1, min(5, mood))
        self.note = note
        self.deleted = false
    }

    func softDeleted() -> MirrorEntry {
        MirrorEntry(id: id, timestamp: timestamp, mood: mood, note: note, deleted: true)
    }

    private init(id: UUID, timestamp: Date, mood: Int, note: String, deleted: Bool) {
        self.id = id; self.timestamp = timestamp; self.mood = mood; self.note = note; self.deleted = deleted
    }
}

// MARK: - Curiosity Catcher (I wonder...)

struct CuriosityEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let object: String
    let wonder: String     // "I wonder..." text
    let followUp: String   // actionable follow-up
    let deleted: Bool

    init(object: String, wonder: String, followUp: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.object = object
        self.wonder = wonder
        self.followUp = followUp
        self.deleted = false
    }

    func softDeleted() -> CuriosityEntry {
        CuriosityEntry(id: id, timestamp: timestamp, object: object, wonder: wonder, followUp: followUp, deleted: true)
    }

    private init(id: UUID, timestamp: Date, object: String, wonder: String, followUp: String, deleted: Bool) {
        self.id = id; self.timestamp = timestamp; self.object = object
        self.wonder = wonder; self.followUp = followUp; self.deleted = deleted
    }
}

// MARK: - WellbeingStore (local-first persistence)

@Observable
final class WellbeingStore {
    static let shared = WellbeingStore()

    private(set) var lensEntries: [LensLedgerEntry] = []
    private(set) var poetryEntries: [PoetryLogEntry] = []
    private(set) var mirrorEntries: [MirrorEntry] = []
    private(set) var curiosityEntries: [CuriosityEntry] = []

    /// When true, new observations are not persisted
    var savingPaused: Bool = false

    private static let maxEntries = 200

    private static var baseDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("wellbeing", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() { loadAll() }

    // MARK: - Lens Ledger

    func addLensEntry(_ entry: LensLedgerEntry) {
        guard !savingPaused else { return }
        lensEntries.insert(entry, at: 0)
        trimAndSave(\.lensEntries, file: "lens.json")
    }

    func deleteLensEntry(id: UUID) {
        if let idx = lensEntries.firstIndex(where: { $0.id == id }) {
            lensEntries[idx] = lensEntries[idx].softDeleted()
            save(lensEntries, file: "lens.json")
        }
    }

    var activeLensEntries: [LensLedgerEntry] { lensEntries.filter { !$0.deleted } }

    // MARK: - Poetry Log

    func addPoetryEntry(_ entry: PoetryLogEntry) {
        guard !savingPaused else { return }
        poetryEntries.insert(entry, at: 0)
        trimAndSave(\.poetryEntries, file: "poetry.json")
    }

    func deletePoetryEntry(id: UUID) {
        if let idx = poetryEntries.firstIndex(where: { $0.id == id }) {
            poetryEntries[idx] = poetryEntries[idx].softDeleted()
            save(poetryEntries, file: "poetry.json")
        }
    }

    var activePoetryEntries: [PoetryLogEntry] { poetryEntries.filter { !$0.deleted } }

    // MARK: - Mirror

    func addMirrorEntry(_ entry: MirrorEntry) {
        guard !savingPaused else { return }
        mirrorEntries.insert(entry, at: 0)
        trimAndSave(\.mirrorEntries, file: "mirror.json")
    }

    func deleteMirrorEntry(id: UUID) {
        if let idx = mirrorEntries.firstIndex(where: { $0.id == id }) {
            mirrorEntries[idx] = mirrorEntries[idx].softDeleted()
            save(mirrorEntries, file: "mirror.json")
        }
    }

    var activeMirrorEntries: [MirrorEntry] { mirrorEntries.filter { !$0.deleted } }

    // MARK: - Curiosity

    func addCuriosityEntry(_ entry: CuriosityEntry) {
        guard !savingPaused else { return }
        curiosityEntries.insert(entry, at: 0)
        trimAndSave(\.curiosityEntries, file: "curiosity.json")
    }

    func deleteCuriosityEntry(id: UUID) {
        if let idx = curiosityEntries.firstIndex(where: { $0.id == id }) {
            curiosityEntries[idx] = curiosityEntries[idx].softDeleted()
            save(curiosityEntries, file: "curiosity.json")
        }
    }

    var activeCuriosityEntries: [CuriosityEntry] { curiosityEntries.filter { !$0.deleted } }

    // MARK: - Bulk operations

    func deleteAllHistory() {
        lensEntries = []
        poetryEntries = []
        mirrorEntries = []
        curiosityEntries = []
        save(lensEntries, file: "lens.json")
        save(poetryEntries, file: "poetry.json")
        save(mirrorEntries, file: "mirror.json")
        save(curiosityEntries, file: "curiosity.json")
    }

    // MARK: - Persistence

    private func trimAndSave<T: Codable>(_ keyPath: ReferenceWritableKeyPath<WellbeingStore, [T]>, file: String) {
        if self[keyPath: keyPath].count > Self.maxEntries {
            self[keyPath: keyPath] = Array(self[keyPath: keyPath].prefix(Self.maxEntries))
        }
        save(self[keyPath: keyPath], file: file)
    }

    private func save<T: Codable>(_ items: [T], file: String) {
        let url = Self.baseDir.appendingPathComponent(file)
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[WellbeingStore] save \(file) failed: \(error)")
        }
    }

    private func load<T: Codable>(file: String) -> [T] {
        let url = Self.baseDir.appendingPathComponent(file)
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            return []
        }
    }

    private func loadAll() {
        lensEntries = load(file: "lens.json")
        poetryEntries = load(file: "poetry.json")
        mirrorEntries = load(file: "mirror.json")
        curiosityEntries = load(file: "curiosity.json")
    }

    // MARK: - Journal Export

    func generateJournalExport(profile: UserProfile) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var lines: [String] = []
        lines.append("AGI Companion Journal")
        lines.append("=====================")
        lines.append("Observer: \(profile.name.isEmpty ? "Anonymous" : profile.name)")
        lines.append("Date: \(dateFormatter.string(from: Date()))")
        lines.append("")

        // Stats
        let dominant = profile.dominantStats
        if !dominant.isEmpty {
            lines.append("Dominant Perception Stats:")
            for stat in dominant {
                lines.append("  \(stat.displayName): Level \(profile.statLevel(stat))")
            }
            lines.append("")
        }

        // Scans
        let scans = activeLensEntries
        if !scans.isEmpty {
            lines.append("Objects Observed (\(scans.count)):")
            for entry in scans.prefix(20) {
                let date = dateFormatter.string(from: entry.timestamp)
                lines.append("  [\(date)] \(entry.scene.isEmpty ? entry.label : entry.scene)")
                if !entry.goal.isEmpty {
                    lines.append("    Goal: \(entry.goal)")
                }
            }
            lines.append("")
        }

        // Texts
        let texts = activePoetryEntries
        if !texts.isEmpty {
            lines.append("Saved Texts (\(texts.count)):")
            for entry in texts.prefix(10) {
                lines.append("  \"\(entry.excerpt.prefix(100))\"")
            }
            lines.append("")
        }

        // Reflections
        let mirrors = activeMirrorEntries
        if !mirrors.isEmpty {
            lines.append("Reflections (\(mirrors.count)):")
            for entry in mirrors.prefix(10) {
                let mood = String(repeating: "*", count: entry.mood)
                lines.append("  [\(mood)] \(entry.note.prefix(80))")
            }
            lines.append("")
        }

        // Curiosities
        let curiosities = activeCuriosityEntries
        if !curiosities.isEmpty {
            lines.append("Curiosities (\(curiosities.count)):")
            for entry in curiosities.prefix(10) {
                lines.append("  \(entry.object): \(entry.wonder)")
            }
            lines.append("")
        }

        lines.append("---")
        lines.append("Generated by AGI — Mistral Hackathon 2026")

        return lines.joined(separator: "\n")
    }
}
