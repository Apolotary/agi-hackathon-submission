//
//  HomeView.swift
//  agiagiagi
//
//  Created by Bektur Ryskeldiev on 2026/02/28.
//

import SwiftUI

struct HomeView: View {
    @State private var profile = UserProfile.load() ?? UserProfile()
    @State private var wellbeing = WellbeingStore.shared
    @State private var store = InteractionStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    characterCard
                    aiSystemSection
                    statsGrid
                    recentScansSection
                    interactionHistorySection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Character")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        shareJournal()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .onAppear {
                profile = UserProfile.load() ?? UserProfile()
            }
        }
    }

    // MARK: - Character Card

    private var characterCard: some View {
        VStack(spacing: 12) {
            // Companion avatar
            Group {
                if let img = UIImage(named: "companion_avatar") {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.4)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                        Text(initials)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.5), Color.blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.5
                    )
            )

            // Name
            Text(profile.name.isEmpty ? "Anonymous Observer" : profile.name)
                .font(.title2)
                .fontWeight(.bold)

            // Personality bio
            if !personalityBio.isEmpty {
                Text(personalityBio)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            // Context + expertise tagline
            HStack(spacing: 8) {
                Label(profile.context.displayName, systemImage: profile.context.icon)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())

                Label(profile.expertise.displayName, systemImage: "star.fill")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
            .foregroundStyle(.secondary)

            // Dominant stats summary
            if !profile.dominantStats.isEmpty {
                HStack(spacing: 6) {
                    ForEach(profile.dominantStats.prefix(3), id: \.self) { stat in
                        Label(stat.displayName, systemImage: stat.icon)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(statColor(stat))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(statColor(stat).opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }

            // Quick stats row
            HStack(spacing: 24) {
                statCounter(
                    value: wellbeing.activeLensEntries.count,
                    label: "Scanned",
                    icon: "eye.fill"
                )
                statCounter(
                    value: store.interactions.count,
                    label: "Artifacts",
                    icon: "sparkles"
                )
                statCounter(
                    value: profile.learningSampleCount,
                    label: "Learned",
                    icon: "brain"
                )
            }
            .padding(.top, 4)

            // Last session summary
            if let sessionSummary = UserDefaults.standard.dictionary(forKey: "last_session_summary") as? [String: Int],
               let lastTime = UserDefaults.standard.object(forKey: "last_session_time") as? Double {
                let lastDate = Date(timeIntervalSince1970: lastTime)
                let apiCalls = sessionSummary["api_calls"] ?? 0
                let duration = sessionSummary["session_duration"] ?? 0
                let minutes = duration / 60

                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Last: \(minutes)m, \(apiCalls) calls")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(lastDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
        .padding(.top, 8)
    }

    private func statCounter(value: Int, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - AI System

    private var aiSystemSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI System")
                .font(.headline)
                .padding(.leading, 4)

            HStack(spacing: 12) {
                aiMetric(
                    icon: "brain.head.profile.fill",
                    value: "\(PromptOptimizer.shared.totalVersions)",
                    label: "Prompt Versions",
                    color: .purple
                )
                aiMetric(
                    icon: "book.closed.fill",
                    value: "\(KnowledgeBase.shared.entryCount)",
                    label: "Knowledge",
                    color: .cyan
                )
                aiMetric(
                    icon: "waveform.path.ecg",
                    value: "\(AgentTraceCollector.shared.totalAPICalls)",
                    label: "API Calls",
                    color: .orange
                )
            }

            // Prompt optimizer detail
            let agentTypes = PromptOptimizer.shared.agentTypes
            if !agentTypes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(agentTypes, id: \.self) { agent in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.purple.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Text(agent)
                                .font(.caption2)
                                .fontWeight(.medium)
                            Spacer()
                            if let score = PromptOptimizer.shared.getBestScore(for: agent) {
                                Text("\(Int(score * 100))%")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.purple)
                            }
                            Text("\(PromptOptimizer.shared.versionCount(for: agent))v")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.regularMaterial)
                )
            }
        }
    }

    private func aiMetric(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Perception Stats")
                    .font(.headline)
                    .padding(.leading, 4)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        for stat in CompanionStat.allCases {
                            profile.setStatLevel(stat, level: Int.random(in: 1...6))
                        }
                        UserProfile.save(profile)
                    }
                } label: {
                    Label("Randomize", systemImage: "dice.fill")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.purple)
                }
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                ForEach(CompanionStat.allCases, id: \.self) { stat in
                    statBar(stat)
                }
            }
        }
    }

    private func statBar(_ stat: CompanionStat) -> some View {
        let level = profile.statLevel(stat)
        let color = statColor(stat)

        return HStack(spacing: 8) {
            Image(systemName: stat.icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(stat.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(0.15))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(level) / 6.0, height: 6)
                    }
                }
                .frame(height: 6)
            }

            Text("\(level)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(color)
                .monospacedDigit()
                .frame(width: 14)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    // MARK: - Recent Scans

    private var recentScansSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recently Scanned")
                .font(.headline)
                .padding(.leading, 4)

            let entries = wellbeing.activeLensEntries.prefix(8)
            if entries.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No scans yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.regularMaterial)
                )
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(Array(entries), id: \.id) { entry in
                        scanCard(entry)
                    }
                }
            }
        }
    }

    private func scanCard(_ entry: LensLedgerEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "eye.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Spacer()
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(entry.scene.isEmpty ? entry.label : entry.scene)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)

            if !entry.goal.isEmpty {
                Text(entry.goal)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    // MARK: - Interaction History

    private var interactionHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Artifact History")
                .font(.headline)
                .padding(.leading, 4)

            if store.interactions.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No artifacts created yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.regularMaterial)
                )
            } else {
                ForEach(store.interactions.prefix(10)) { interaction in
                    interactionRow(interaction)
                }
            }
        }
    }

    private func interactionRow(_ interaction: PanelInteraction) -> some View {
        HStack(spacing: 12) {
            if let image = interaction.thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(interaction.deviceFamily.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let goal = interaction.goal {
                    Text(goal.replacingOccurrences(of: "_", with: " "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(interaction.timestamp, style: .relative)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    // MARK: - Helpers

    private var initials: String {
        let name = profile.name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return "?" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var personalityBio: String {
        let dominant = profile.dominantStats
        guard !dominant.isEmpty else {
            return "A fresh observer. The world awaits your perception."
        }

        let statDescriptions: [CompanionStat: String] = [
            .inlandEmpire: "a dreamer who hears what objects won't say",
            .encyclopedia: "a walking database of specs and trivia",
            .empathy: "a reader of human traces in everyday things",
            .visualCalculus: "a spatial analyst who sees structure everywhere",
            .electrochemistry: "a sensualist drawn to texture and color",
            .rhetoric: "a debater who questions everything",
            .shivers: "a psychic who senses the bigger picture",
            .conceptualization: "an artist who finds beauty in the mundane"
        ]

        let parts = dominant.prefix(2).compactMap { stat -> String? in
            guard let desc = statDescriptions[stat] else { return nil }
            return "\(desc) (\(stat.displayName) \(profile.statLevel(stat)))"
        }

        if parts.count == 2 {
            return "An observer who is \(parts[0]) and \(parts[1])."
        } else if let first = parts.first {
            return "An observer who is \(first)."
        }
        return ""
    }

    private func shareJournal() {
        let journalText = WellbeingStore.shared.generateJournalExport(profile: profile)
        let activityVC = UIActivityViewController(
            activityItems: [journalText],
            applicationActivities: nil
        )
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    private func statColor(_ stat: CompanionStat) -> Color {
        switch stat {
        case .inlandEmpire: return Color(red: 0.6, green: 0.3, blue: 0.9)
        case .encyclopedia: return Color(red: 0.2, green: 0.8, blue: 0.9)
        case .empathy: return Color(red: 0.95, green: 0.4, blue: 0.6)
        case .visualCalculus: return Color(red: 0.3, green: 0.9, blue: 0.5)
        case .electrochemistry: return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .rhetoric: return Color(red: 0.9, green: 0.85, blue: 0.3)
        case .shivers: return Color(red: 0.4, green: 0.5, blue: 0.95)
        case .conceptualization: return Color(red: 0.85, green: 0.3, blue: 0.8)
        }
    }
}

#Preview {
    HomeView()
}
