//
//  OnboardingView.swift
//  agiagiagi
//
//  Created by Bektur Ryskeldiev on 2026/02/28.
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isOnboardingComplete: Bool
    @State private var currentStep = 0
    @State private var profile = UserProfile(name: OnboardingView.generateName())

    private static let nameAdjectives = ["Curious", "Brave", "Nimble", "Keen", "Swift", "Bright", "Bold", "Sharp", "Quick", "Witty"]
    private static let nameNouns = ["Explorer", "Traveler", "Pioneer", "Scout", "Seeker", "Finder", "Rover", "Voyager", "Wanderer", "Navigator"]

    private static func generateName() -> String {
        let adj = nameAdjectives.randomElement() ?? "Curious"
        let noun = nameNouns.randomElement() ?? "Explorer"
        return "\(adj) \(noun)"
    }

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
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<4) { index in
                    Capsule()
                        .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)

            TabView(selection: $currentStep) {
                languageStep.tag(0)
                contextStep.tag(1)
                expertiseStep.tag(2)
                statsStep.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentStep)

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()

                if currentStep < 3 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        UserProfile.save(profile)
                        UserDefaults.standard.set(true, forKey: "onboarding_completed")
                        isOnboardingComplete = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Step 1: Language

    private var languageStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "globe")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("What language\ndo you speak?")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Translations will be shown in this language")
                .font(.body)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(languages, id: \.code) { lang in
                    Button {
                        profile.language = lang.code
                    } label: {
                        Text(lang.name)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(profile.language == lang.code ? Color.accentColor : Color.secondary.opacity(0.1))
                            )
                            .foregroundColor(profile.language == lang.code ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal, 16)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Step 2: Context

    private var contextStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("What brings\nyou here?")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                ForEach(UserContext.allCases, id: \.self) { ctx in
                    Button {
                        profile.context = ctx
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: ctx.icon)
                                .font(.title2)
                                .frame(width: 40)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(ctx.displayName)
                                    .font(.headline)
                                Text(ctx.description)
                                    .font(.caption)
                                    .foregroundColor(profile.context == ctx ? .white.opacity(0.8) : .secondary)
                            }

                            Spacer()

                            if profile.context == ctx {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(profile.context == ctx ? Color.accentColor : Color.secondary.opacity(0.1))
                        )
                        .foregroundColor(profile.context == ctx ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal, 16)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Step 3: Expertise

    private var expertiseStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("How comfortable\nare you with tech?")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("This helps us adjust the level of detail")
                .font(.body)
                .foregroundColor(.secondary)

            VStack(spacing: 16) {
                ForEach(UserExpertise.allCases, id: \.self) { level in
                    Button {
                        profile.expertise = level
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: level.icon)
                                .font(.title2)
                                .frame(width: 40)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(level.displayName)
                                    .font(.headline)
                                Text(level.description)
                                    .font(.caption)
                                    .foregroundColor(profile.expertise == level ? .white.opacity(0.8) : .secondary)
                            }

                            Spacer()

                            if profile.expertise == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(profile.expertise == level ? Color.accentColor : Color.secondary.opacity(0.1))
                        )
                        .foregroundColor(profile.expertise == level ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal, 16)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Step 4: Perception Stats

    private var statsStep: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 8)

            Text("How do you\nsee the world?")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Pick your dominant perception. Set high stats to shape how your companion thinks.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(CompanionStat.allCases, id: \.self) { stat in
                        statRow(stat)
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer()
                .frame(height: 8)
        }
        .padding(.horizontal, 16)
    }

    private func statRow(_ stat: CompanionStat) -> some View {
        let level = profile.statLevel(stat)
        let isHigh = level >= 4

        return HStack(spacing: 12) {
            Image(systemName: stat.icon)
                .font(.title3)
                .foregroundStyle(isHigh ? .white : .secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(stat.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(stat.tagline)
                    .font(.caption2)
                    .foregroundColor(isHigh ? .white.opacity(0.7) : .secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Level pips
            HStack(spacing: 3) {
                ForEach(1...6, id: \.self) { pip in
                    Circle()
                        .fill(pip <= level ? (isHigh ? Color.white : Color.accentColor) : Color.secondary.opacity(0.2))
                        .frame(width: 8, height: 8)
                }
            }

            // Stepper buttons
            HStack(spacing: 4) {
                Button {
                    var p = profile
                    p.setStatLevel(stat, level: level - 1)
                    profile = p
                } label: {
                    Image(systemName: "minus")
                        .font(.caption2.bold())
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.secondary.opacity(0.15)))
                }
                .disabled(level <= 1)

                Button {
                    var p = profile
                    p.setStatLevel(stat, level: level + 1)
                    profile = p
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2.bold())
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.secondary.opacity(0.15)))
                }
                .disabled(level >= 6)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHigh ? Color.accentColor : Color.secondary.opacity(0.08))
        )
        .foregroundColor(isHigh ? .white : .primary)
    }
}

// MARK: - Profile Editor (reusable from Settings)

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profile: UserProfile

    init() {
        _profile = State(initialValue: UserProfile.load() ?? UserProfile())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Perception Stats") {
                    ForEach(CompanionStat.allCases, id: \.self) { stat in
                        statEditorRow(stat)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        UserProfile.save(profile)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func statEditorRow(_ stat: CompanionStat) -> some View {
        let level = profile.statLevel(stat)
        return HStack {
            Image(systemName: stat.icon)
                .foregroundStyle(level >= 4 ? Color.accentColor : Color.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(stat.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(stat.tagline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 3) {
                ForEach(1...6, id: \.self) { pip in
                    Circle()
                        .fill(pip <= level ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(width: 7, height: 7)
                }
            }

            Stepper("", value: Binding(
                get: { profile.statLevel(stat) },
                set: { profile.setStatLevel(stat, level: $0) }
            ), in: 1...6)
            .labelsHidden()
            .fixedSize()
        }
    }
}

#Preview {
    OnboardingView(isOnboardingComplete: .constant(false))
}
