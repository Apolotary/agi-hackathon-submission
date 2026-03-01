//
//  VoiceView.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import SwiftUI

enum VoiceMode: String, CaseIterable {
    case narrate = "Narrate Steps"
    case dialogue = "Dialogue Mode"
}

struct VoiceView: View {
    @State private var selectedMode: VoiceMode = .narrate
    @State private var tts = ElevenLabsTTS.shared
    @State private var currentStepIndex: Int? = nil
    @State private var isPlayingAll = false

    private var store: InteractionStore { InteractionStore.shared }

    private var latestWizard: ActionWizard? {
        store.interactions.first?.actionWizard
    }

    private var panelContext: String {
        guard let interaction = store.interactions.first,
              let analysis = interaction.panelAnalysis else { return "" }
        return "Device: \(analysis.panel.deviceFamily). Goal: \(interaction.goal ?? "unknown"). \(analysis.elements.count) elements detected."
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode picker
                Picker("Mode", selection: $selectedMode) {
                    ForEach(VoiceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                // Content
                switch selectedMode {
                case .narrate:
                    narrateContent
                case .dialogue:
                    dialogueContent
                }
            }
            .navigationTitle("Voice")
        }
    }

    // MARK: - Narrate Mode

    @ViewBuilder
    private var narrateContent: some View {
        if let wizard = latestWizard {
            VStack(spacing: 0) {
                // Goal header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(wizard.goal)
                            .font(.headline)
                        Text("Risk: \(wizard.riskTier)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    playAllButton
                }
                .padding()

                Divider()

                // Steps list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(wizard.steps.enumerated()), id: \.element.id) { index, step in
                            stepRow(step: step, index: index)
                        }
                    }
                    .padding()
                }
            }
        } else {
            emptyState
        }
    }

    private func stepRow(step: WizardStep, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Step number
            ZStack {
                Circle()
                    .fill(currentStepIndex == index ? Color.blue : Color(.systemGray5))
                    .frame(width: 32, height: 32)
                Text("\(index + 1)")
                    .font(.caption.bold())
                    .foregroundColor(currentStepIndex == index ? .white : .primary)
            }

            // Instruction text
            VStack(alignment: .leading, spacing: 4) {
                Text(step.instruction)
                    .font(.body)
                    .foregroundColor(currentStepIndex == index ? .primary : .secondary)

                if step.requiresConfirmation {
                    Label("Requires confirmation", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            // Play button for this step
            Button {
                speakStep(step, at: index)
            } label: {
                Image(systemName: currentStepIndex == index && tts.isSpeaking ? "speaker.wave.3.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(currentStepIndex == index && tts.isSpeaking ? .blue : .secondary)
                    .symbolEffect(.variableColor.iterative, isActive: currentStepIndex == index && tts.isSpeaking)
            }
            .disabled(isPlayingAll && currentStepIndex != index)
        }
        .padding(.vertical, 4)
        .opacity(currentStepIndex == nil || currentStepIndex == index ? 1.0 : 0.5)
    }

    private var playAllButton: some View {
        Button {
            if isPlayingAll {
                stopAll()
            } else {
                playAll()
            }
        } label: {
            Label(
                isPlayingAll ? "Stop" : "Play All",
                systemImage: isPlayingAll ? "stop.fill" : "play.fill"
            )
            .font(.subheadline.bold())
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isPlayingAll ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
            .foregroundColor(isPlayingAll ? .red : .blue)
            .clipShape(Capsule())
        }
    }

    // MARK: - Dialogue Mode

    @ViewBuilder
    private var dialogueContent: some View {
        DialogueView(panelContext: panelContext)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Take a photo first to get started")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Use the Camera tab to analyze a panel,\nthen come back here for voice guidance.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - TTS Actions

    private func speakStep(_ step: WizardStep, at index: Int) {
        Task {
            tts.stop()
            currentStepIndex = index
            try? await tts.speak(text: step.instruction)
            if currentStepIndex == index {
                currentStepIndex = nil
            }
        }
    }

    private func playAll() {
        guard let wizard = latestWizard else { return }
        isPlayingAll = true

        Task {
            for (index, step) in wizard.steps.enumerated() {
                guard isPlayingAll else { break }
                currentStepIndex = index
                try? await tts.speak(text: step.instruction)
            }
            isPlayingAll = false
            currentStepIndex = nil
        }
    }

    private func stopAll() {
        isPlayingAll = false
        currentStepIndex = nil
        tts.stop()
    }
}

#Preview {
    VoiceView()
}
