//
//  AgentSwarmView.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import SwiftUI

// MARK: - Agent Node View

struct AgentNodeView: View {
    let name: String
    let icon: String
    let status: AgentStatus
    let latestMessage: String?

    @State private var isPulsing = false
    @State private var appeared = false

    private var statusColor: Color {
        switch status {
        case .spawned: return .gray
        case .working: return .blue
        case .done: return .green
        case .failed: return .red
        }
    }

    private var statusIcon: String {
        switch status {
        case .spawned: return "circle.dotted"
        case .working: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                    .scaleEffect(isPulsing ? 1.15 : 1.0)

                Circle()
                    .strokeBorder(statusColor, lineWidth: 2)
                    .frame(width: 56, height: 56)

                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(statusColor)
            }

            Text(name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Image(systemName: statusIcon)
                .font(.caption2)
                .foregroundStyle(statusColor)
                .symbolEffect(.rotate, isActive: status == .working)

            if let message = latestMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 120)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: statusColor.opacity(status == .done ? 0.3 : 0), radius: 8)
        )
        .scaleEffect(appeared ? 1.0 : 0.5)
        .opacity(appeared ? 1.0 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appeared = true
            }
        }
        .onChange(of: status) { _, newStatus in
            if newStatus == .working {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    isPulsing = false
                }
            }
        }
    }
}

// MARK: - Connection Arrow

struct ConnectionArrow: View {
    let isActive: Bool
    let direction: Direction

    enum Direction {
        case down
        case right
    }

    var body: some View {
        Group {
            if direction == .down {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(isActive ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 2, height: 20)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(isActive ? .blue : .gray.opacity(0.3))
                }
            } else {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(isActive ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 20, height: 2)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(isActive ? .blue : .gray.opacity(0.3))
                }
            }
        }
        .opacity(isActive ? 1.0 : 0.5)
    }
}

// MARK: - Quality Score Badge

struct QualityScoreBadge: View {
    let score: Double

    private var color: Color {
        if score >= 0.8 { return .green }
        if score >= 0.6 { return .yellow }
        return .red
    }

    private var label: String {
        if score >= 0.8 { return "Excellent" }
        if score >= 0.6 { return "Good" }
        if score >= 0.4 { return "Fair" }
        return "Low"
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.0f%%", score * 100))
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(color)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Quality Score")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: color.opacity(0.3), radius: 8)
        )
    }
}

// MARK: - Log Entry View

struct LogEntryView: View {
    let log: AgentLog

    private var statusColor: Color {
        switch log.status {
        case .spawned: return .gray
        case .working: return .blue
        case .done: return .green
        case .failed: return .red
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(log.agentName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(statusColor)

                    Spacer()

                    Text(Self.timeFormatter.string(from: log.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                Text(log.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Main Swarm View

struct AgentSwarmView: View {
    let swarm: AgentSwarm
    let qualityScore: Double?

    init(swarm: AgentSwarm, qualityScore: Double? = nil) {
        self.swarm = swarm
        self.qualityScore = qualityScore
    }

    private func latestMessage(for agentName: String) -> String? {
        swarm.agentLogs
            .last(where: { $0.agentName == agentName })?
            .message
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            if swarm.isRunning {
                VStack(spacing: 4) {
                    ProgressView(value: swarm.progress) {
                        Text(swarm.currentPhase)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tint(.blue)
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }

            // Agent flow diagram
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 4) {
                    // Row 1: Parallel agents (Detector + Translator)
                    HStack(spacing: 24) {
                        AgentNodeView(
                            name: "Detector",
                            icon: "magnifyingglass",
                            status: swarm.detectorStatus,
                            latestMessage: latestMessage(for: PanelDetectorAgent.agentName)
                        )

                        AgentNodeView(
                            name: "Translator",
                            icon: "globe",
                            status: swarm.translatorStatus,
                            latestMessage: latestMessage(for: TranslatorAgent.agentName)
                        )
                    }
                    .padding(.top, 12)

                    // Arrows down from both to merge point
                    HStack(spacing: 80) {
                        ConnectionArrow(
                            isActive: swarm.detectorStatus == .done || swarm.detectorStatus == .working,
                            direction: .down
                        )
                        ConnectionArrow(
                            isActive: swarm.translatorStatus == .done || swarm.translatorStatus == .working,
                            direction: .down
                        )
                    }

                    // Row 2: Merge indicator + Wizard
                    HStack(spacing: 16) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(180))

                        ConnectionArrow(
                            isActive: swarm.wizardStatus == .working || swarm.wizardStatus == .done,
                            direction: .right
                        )

                        AgentNodeView(
                            name: "Wizard",
                            icon: "wand.and.stars",
                            status: swarm.wizardStatus,
                            latestMessage: latestMessage(for: WizardAgent.agentName)
                        )
                    }

                    // Arrow down to evaluator
                    ConnectionArrow(
                        isActive: swarm.evaluatorStatus == .working || swarm.evaluatorStatus == .done,
                        direction: .down
                    )

                    // Row 3: Evaluator + Quality Score
                    HStack(spacing: 16) {
                        AgentNodeView(
                            name: "Evaluator",
                            icon: "checkmark.seal",
                            status: swarm.evaluatorStatus,
                            latestMessage: latestMessage(for: EvaluatorAgent.agentName)
                        )

                        if let score = qualityScore, !swarm.isRunning {
                            ConnectionArrow(isActive: true, direction: .right)
                            QualityScoreBadge(score: score)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Divider()
                .padding(.vertical, 8)

            // Live-scrolling log
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(swarm.agentLogs) { log in
                            LogEntryView(log: log)
                                .id(log.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 200)
                .onChange(of: swarm.agentLogs.count) { _, _ in
                    if let lastLog = swarm.agentLogs.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Preview

#Preview {
    let swarm = AgentSwarm()
    AgentSwarmView(swarm: swarm, qualityScore: 0.85)
        .padding()
}
