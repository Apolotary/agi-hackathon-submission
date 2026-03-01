//
//  SuggestionView.swift
//  agiagiagi
//
//  Created by Bektur Ryskeldiev on 2026/02/28.
//

import SwiftUI

struct SuggestionView: View {
    let imageData: Data
    let image: UIImage
    let suggestions: [String]

    @State private var customGoal = ""
    @State private var showCustomField = false
    @State private var isLoading = false
    @State private var loadingMessage = "Analyzing panel..."
    @State private var errorMessage: String?
    @State private var showError = false

    @State private var analysis: PanelAnalysis?
    @State private var wizard: ActionWizard?
    @State private var navigateToResult = false

    // Agent Swarm mode
    @State private var useAgentSwarm = false
    @State private var swarm = AgentSwarm()
    @State private var showSwarmSheet = false
    @State private var swarmResult: SwarmResult?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Panel image preview
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
                    .padding(.horizontal)

                if isLoading && !useAgentSwarm {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text(loadingMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)
                } else if !isLoading {
                    VStack(spacing: 8) {
                        Text("What would you like to do?")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text("Select an action or enter your own")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Agent Mode toggle
                    HStack {
                        Image(systemName: useAgentSwarm ? "cpu.fill" : "cpu")
                            .foregroundStyle(useAgentSwarm ? .purple : .secondary)
                        Text("Agent Swarm")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Toggle("", isOn: $useAgentSwarm)
                            .labelsHidden()
                            .tint(.purple)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(useAgentSwarm ? Color.purple.opacity(0.08) : Color.gray.opacity(0.06))
                    )
                    .padding(.horizontal)

                    // Suggested goals
                    VStack(spacing: 12) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                            Button {
                                UserProfile.recordSuggestionTap(suggestion, index: index)
                                Task { await runAnalysis(goal: suggestion) }
                            } label: {
                                HStack {
                                    Text(suggestion)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Image(systemName: useAgentSwarm ? "cpu" : "arrow.right.circle.fill")
                                        .font(.title3)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(useAgentSwarm ? .purple.opacity(0.1) : .blue.opacity(0.1))
                                .foregroundStyle(useAgentSwarm ? .purple : .blue)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Custom goal
                    if showCustomField {
                        VStack(spacing: 12) {
                            TextField("Describe what you want to do...", text: $customGoal)
                                .textFieldStyle(.roundedBorder)
                                .padding(.horizontal)

                            Button {
                                guard !customGoal.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                Task { await runAnalysis(goal: customGoal) }
                            } label: {
                                Text("Go")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(customGoal.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : (useAgentSwarm ? .purple : .blue))
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(customGoal.trimmingCharacters(in: .whitespaces).isEmpty)
                            .padding(.horizontal)
                        }
                    } else {
                        Button {
                            withAnimation { showCustomField = true }
                        } label: {
                            HStack {
                                Image(systemName: "pencil")
                                Text("Something else...")
                            }
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToResult) {
            if let analysis, let wizard {
                CameraResultView(image: image, analysis: analysis, wizard: wizard)
            }
        }
        .sheet(isPresented: $showSwarmSheet) {
            NavigationStack {
                VStack(spacing: 0) {
                    AgentSwarmView(swarm: swarm, qualityScore: swarmResult?.qualityScore)
                        .padding()
                }
                .navigationTitle("Agent Swarm")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if !swarm.isRunning {
                            Button("Done") {
                                showSwarmSheet = false
                                if let result = swarmResult,
                                   let panelAnalysis = result.panelAnalysis,
                                   let actionWizard = result.actionWizard {
                                    analysis = panelAnalysis
                                    wizard = actionWizard
                                    navigateToResult = true
                                }
                            }
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    private func runAnalysis(goal: String) async {
        if useAgentSwarm {
            await runSwarm(goal: goal)
        } else {
            await runWizard(goal: goal)
        }
    }

    private func runSwarm(goal: String) async {
        let profile = UserProfile.load() ?? UserProfile()
        swarm = AgentSwarm()
        swarmResult = nil
        showSwarmSheet = true

        let result = await swarm.analyze(
            imageData: imageData,
            goal: goal,
            userProfile: profile
        )
        swarmResult = result

        // Save interaction if we got results
        if let panelAnalysis = result.panelAnalysis {
            let interaction = PanelInteraction(
                imageData: imageData,
                panelAnalysis: panelAnalysis,
                actionWizard: result.actionWizard,
                deviceFamily: panelAnalysis.panel.deviceFamily,
                goal: goal
            )
            InteractionStore.shared.add(interaction)
        }
    }

    private func runWizard(goal: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let profile = UserProfile.load() ?? UserProfile()
            loadingMessage = "Analyzing panel..."
            let panelAnalysis = try await MistralAPI.shared.analyzePanel(imageData: imageData, userProfile: profile)
            analysis = panelAnalysis

            loadingMessage = "Building instructions..."
            let actionWizard = try await MistralAPI.shared.buildWizard(
                analysis: panelAnalysis,
                goal: goal,
                userProfile: profile
            )
            wizard = actionWizard

            // Save interaction
            let interaction = PanelInteraction(
                imageData: imageData,
                panelAnalysis: panelAnalysis,
                actionWizard: actionWizard,
                deviceFamily: panelAnalysis.panel.deviceFamily,
                goal: goal
            )
            InteractionStore.shared.add(interaction)

            navigateToResult = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
