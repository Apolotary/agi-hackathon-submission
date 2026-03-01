//
//  SettingsView.swift
//  agiagiagi
//
//  Created by Bektur Ryskeldiev on 2026/02/28.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("api_provider") private var apiProvider = "mistral"
    @AppStorage("mistral_api_key") private var mistralAPIKey = ""
    @AppStorage("openai_api_key") private var openaiAPIKey = ""
    @AppStorage("elevenlabs_api_key") private var elevenLabsAPIKey = ""
    @AppStorage("elevenlabs_agent_id") private var elevenLabsAgentID = ""
    @AppStorage("onboarding_completed") private var onboardingCompleted = true

    @AppStorage("sensing_paused") private var sensingPaused = false
    @AppStorage("proactive_prompts_paused") private var proactivePromptsPaused = false
    @AppStorage("dont_save_interactions") private var dontSaveInteractions = false

    @State private var profile: UserProfile = UserProfile.load() ?? UserProfile()
    @State private var showResetConfirmation = false
    @State private var showClearHistoryConfirmation = false
    @State private var showDeleteWellbeingConfirmation = false
    @State private var showProfileEditor = false

    private let languages: [(code: String, name: String)] = [
        ("en", "English"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("pt", "Portuguese"),
        ("ru", "Russian"),
        ("ar", "Arabic")
    ]

    var body: some View {
        NavigationStack {
            Form {
                apiKeysSection
                profileSection
                statsSection
                privacySection
                demoSection
                aboutSection
                resetSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorView()
                    .onDisappear {
                        profile = UserProfile.load() ?? UserProfile()
                    }
            }
        }
    }

    // MARK: - API Keys

    private var apiKeysSection: some View {
        Section {
            Picker("AI Provider", selection: $apiProvider) {
                Text("Mistral").tag("mistral")
                Text("OpenAI").tag("openai")
            }

            if apiProvider == "mistral" {
                VStack(alignment: .leading, spacing: 4) {
                    SecureField("Mistral API Key", text: $mistralAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .onChange(of: mistralAPIKey) { _, val in KeychainManager.shared.store(val, for: "mistral_api_key") }
                    Text("Get your key at console.mistral.ai")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    SecureField("OpenAI API Key", text: $openaiAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .onChange(of: openaiAPIKey) { _, val in KeychainManager.shared.store(val, for: "openai_api_key") }
                    Text("Get your key at platform.openai.com")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Model: gpt-5-nano")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                SecureField("ElevenLabs API Key", text: $elevenLabsAPIKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .onChange(of: elevenLabsAPIKey) { _, val in KeychainManager.shared.store(val, for: "elevenlabs_api_key") }
                Text("Stored securely in iOS Keychain")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("ElevenLabs Agent ID", text: $elevenLabsAgentID)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Text("Found in your ElevenLabs conversational agent settings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("API Keys")
        }
    }

    // MARK: - Profile

    private var profileSection: some View {
        Section("Profile") {
            TextField("Name", text: $profile.name)
                .onChange(of: profile.name) { _, _ in saveProfile() }

            Picker("Language", selection: $profile.language) {
                ForEach(languages, id: \.code) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }
            .onChange(of: profile.language) { _, _ in saveProfile() }

            Picker("Context", selection: $profile.context) {
                ForEach(UserContext.allCases, id: \.self) { ctx in
                    Label(ctx.displayName, systemImage: ctx.icon).tag(ctx)
                }
            }
            .onChange(of: profile.context) { _, _ in saveProfile() }

            Picker("Expertise", selection: $profile.expertise) {
                ForEach(UserExpertise.allCases, id: \.self) { level in
                    Label(level.displayName, systemImage: level.icon).tag(level)
                }
            }
            .onChange(of: profile.expertise) { _, _ in saveProfile() }

            Picker("Output Style", selection: $profile.outputStyle) {
                ForEach(CompanionOutputStyle.allCases, id: \.self) { style in
                    Label(style.displayName, systemImage: style.icon).tag(style)
                }
            }
            .onChange(of: profile.outputStyle) { _, _ in saveProfile() }

            Picker("Response Pace", selection: $profile.responsePace) {
                ForEach(CompanionResponsePace.allCases, id: \.self) { pace in
                    Label(pace.displayName, systemImage: pace.icon).tag(pace)
                }
            }
            .onChange(of: profile.responsePace) { _, _ in saveProfile() }

            Toggle("Interactive Controls", isOn: $profile.wantsInteractiveUI)
                .onChange(of: profile.wantsInteractiveUI) { _, _ in saveProfile() }
            Toggle("Haptics + Sound", isOn: $profile.wantsHapticsAndSound)
                .onChange(of: profile.wantsHapticsAndSound) { _, _ in saveProfile() }
            Toggle("Generated Images", isOn: $profile.wantsGeneratedImages)
                .onChange(of: profile.wantsGeneratedImages) { _, _ in saveProfile() }

            TextField("Focus Areas (optional)", text: $profile.focusAreas, axis: .vertical)
                .lineLimit(2...4)
                .onChange(of: profile.focusAreas) { _, _ in saveProfile() }

            LabeledContent("Learned Practical", value: "\(Int((profile.practicalIntentWeight * 100).rounded()))%")
            LabeledContent("Learned Creative", value: "\(Int((profile.creativeIntentWeight * 100).rounded()))%")
            LabeledContent("Learning Samples", value: "\(profile.learningSampleCount)")

            Button("Reset Learned Weights", role: .destructive) {
                profile.practicalIntentWeight = 0.55
                profile.creativeIntentWeight = 0.45
                profile.learningSampleCount = 0
                profile.tappedSuggestionHistogram = [:]
                saveProfile()
            }
        }
    }

    // MARK: - Perception Stats

    private var statsSection: some View {
        Section {
            let dominant = profile.dominantStats
            if dominant.isEmpty {
                Text("No dominant stats yet. Tap Edit to shape your companion's perception.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dominant, id: \.self) { stat in
                    HStack(spacing: 10) {
                        Image(systemName: stat.icon)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stat.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(stat.tagline)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(profile.statLevel(stat))")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            ForEach(CompanionStat.allCases.filter { profile.statLevel($0) < 4 }, id: \.self) { stat in
                HStack(spacing: 10) {
                    Image(systemName: stat.icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    Text(stat.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(profile.statLevel(stat))")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }

            Button("Edit Perception Stats") {
                showProfileEditor = true
            }
        } header: {
            Text("Perception Stats")
        } footer: {
            Text("Stats at 4+ shape how your companion sees the world. High Inland Empire lets it talk to objects.")
        }
    }

    // MARK: - Privacy & Wellbeing

    private var privacySection: some View {
        Section {
            Toggle("Mute Sounds", isOn: Binding(
                get: { SoundManager.shared.isMuted },
                set: { SoundManager.shared.isMuted = $0 }
            ))
            Toggle("Pause Sensing", isOn: $sensingPaused)
            Toggle("Pause Proactive Prompts", isOn: $proactivePromptsPaused)
            Toggle("Don't Save Interactions", isOn: $dontSaveInteractions)
                .onChange(of: dontSaveInteractions) { _, newValue in
                    WellbeingStore.shared.savingPaused = newValue
                }

            LabeledContent("Objects Seen", value: "\(WellbeingStore.shared.activeLensEntries.count)")
            LabeledContent("Texts Saved", value: "\(WellbeingStore.shared.activePoetryEntries.count)")
            LabeledContent("Reflections", value: "\(WellbeingStore.shared.activeMirrorEntries.count)")
            LabeledContent("Curiosities", value: "\(WellbeingStore.shared.activeCuriosityEntries.count)")

            Button("Delete Wellbeing History", role: .destructive) {
                showDeleteWellbeingConfirmation = true
            }
            .confirmationDialog("Delete all wellbeing data?", isPresented: $showDeleteWellbeingConfirmation, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    WellbeingStore.shared.deleteAllHistory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove all saved observations, texts, reflections, and curiosities.")
            }
        } header: {
            Text("Privacy & Wellbeing")
        } footer: {
            Text("All data is stored locally on this device. Nothing is sent to any server.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "AGI")
            LabeledContent("Version", value: "1.0 (Hackathon)")
            LabeledContent("Event", value: "Mistral Worldwide Hackathon, Tokyo 2026")
            LabeledContent("Built by", value: "Bektur Ryskeldiev")
        }
    }

    // MARK: - Debug

    // MARK: - Demo Mode

    @AppStorage("demo_mode") private var demoMode = false

    private var demoSection: some View {
        Section {
            Toggle("Demo Mode", isOn: $demoMode)
            if demoMode {
                Text("Uses cached responses. Safe for live stage demo — never fails due to network.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Demo")
        } footer: {
            Text("Enable before going on stage. Guarantees smooth demo even without Wi-Fi.")
        }
    }

    private var resetSection: some View {
        Section("Debug") {
            Button("Reset Onboarding", role: .destructive) {
                showResetConfirmation = true
            }
            .confirmationDialog("Reset onboarding?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
                Button("Reset", role: .destructive) {
                    UserDefaults.standard.removeObject(forKey: "user_profile")
                    onboardingCompleted = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will clear your profile and show the onboarding flow again.")
            }

            Button("Clear History", role: .destructive) {
                showClearHistoryConfirmation = true
            }
            .confirmationDialog("Clear all history?", isPresented: $showClearHistoryConfirmation, titleVisibility: .visible) {
                Button("Clear All", role: .destructive) {
                    InteractionStore.shared.clearAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all saved panel interactions.")
            }
        }
    }

    private func saveProfile() {
        UserProfile.save(profile)
    }
}

#Preview {
    SettingsView()
}
