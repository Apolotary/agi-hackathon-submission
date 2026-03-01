//
//  DialogueView.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import SwiftUI

struct DialogueView: View {
    let panelContext: String

    @State private var bridge = DialogueBridge()
    @State private var tts = ElevenLabsTTS.shared
    @State private var stt = VoxtralSTT.shared
    @State private var conversationHistory: [ChatMessage] = []
    @State private var isProcessing = false
    @State private var finalizeVoiceTask: Task<Void, Never>?

    private var systemPrompt: String {
        """
        You are a helpful panel assistant for AGI in an RPG-style dialogue interface. \
        You help users understand and operate physical control panels like intercoms and thermostats.

        \(panelContext.isEmpty ? "" : "Context about the current panel:\n\(panelContext)\n")

        IMPORTANT: After each response, provide exactly 2-3 reply options for the user in this format:
        Put your conversational response first, then on a new line write OPTIONS: followed by options separated by |
        Example: "The unlock button is the large green one on the right side."
        OPTIONS: How do I press it?|What does the red button do?|I want to call the front desk instead

        Keep responses concise since they will be spoken aloud.
        """
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            DialogueWebView(bridge: bridge)
                .ignoresSafeArea()

            // Live transcript overlay when listening
            if stt.isListening {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                        Text(stt.partialTranscript.isEmpty ? "Listening..." : stt.partialTranscript)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .lineLimit(3)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text("Dialogue")
                        .font(.headline)
                        .foregroundColor(.white)
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.7)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // Mic button for Voxtral STT
                    Button {
                        toggleVoiceInput()
                    } label: {
                        Image(systemName: stt.isListening ? "mic.fill" : "mic")
                            .foregroundColor(stt.isListening ? .red : .white)
                            .symbolEffect(.pulse, isActive: stt.isListening)
                    }
                    .disabled(isProcessing)

                    if tts.isSpeaking {
                        Button {
                            tts.stop()
                        } label: {
                            Image(systemName: "speaker.slash.fill")
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
        .onAppear {
            bridge.onAction = { action in
                handleAction(action)
            }
            startConversation()
        }
        .onDisappear {
            finalizeVoiceTask?.cancel()
            finalizeVoiceTask = nil
            stt.cancel()
        }
    }

    private func startConversation() {
        conversationHistory = [
            ChatMessage.system(systemPrompt),
            ChatMessage.user("Hello! I need help with this panel.")
        ]
        sendAndProcess()
    }

    private func handleAction(_ action: DialogueAction) {
        switch action {
        case .selectOption(let text):
            addUserMessageAndProcess(text)
        case .sendText(let text):
            addUserMessageAndProcess(text)
        }
    }

    private func addUserMessageAndProcess(_ text: String) {
        guard !isProcessing else { return }
        bridge.addMessage(role: "user", content: text)
        conversationHistory.append(ChatMessage.user(text))
        sendAndProcess()
    }

    private func sendAndProcess() {
        guard !isProcessing else { return }
        isProcessing = true
        bridge.setState("thinking")

        Task {
            var fullResponse = ""
            let stream = MistralAPI.shared.streamChat(
                messages: conversationHistory,
                model: .ministral8b
            )

            do {
                for try await token in stream {
                    fullResponse += token
                }
            } catch {
                print("[DialogueView] Stream error: \(error)")
                fullResponse = "I'm sorry, I had trouble processing that. Could you try again?"
            }

            let (message, options) = parseResponse(fullResponse)
            conversationHistory.append(ChatMessage.assistant(fullResponse))

            // Display the assistant message
            bridge.addMessage(role: "assistant", content: message)

            // Speak the response
            bridge.setState("speaking")
            try? await tts.speak(text: message)

            // Show options or text input
            if !options.isEmpty {
                let optionTuples = options.map { (id: $0, text: $0) }
                bridge.setOptions(optionTuples)
            } else {
                bridge.showTextInput()
            }

            bridge.setState("idle")
            isProcessing = false
        }
    }

    // MARK: - Voice Input (Voxtral STT)

    private func toggleVoiceInput() {
        if stt.isListening {
            // Stop and send the transcribed text
            stt.stopListening()
            // Wait a moment for final transcript
            finalizeVoiceTask?.cancel()
            finalizeVoiceTask = Task {
                try? await Task.sleep(for: .seconds(2.5))
                if Task.isCancelled { return }
                let text = stt.finalTranscript.isEmpty ? stt.partialTranscript : stt.finalTranscript
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    addUserMessageAndProcess(trimmed)
                }
            }
        } else {
            // Stop any TTS first, then start listening
            finalizeVoiceTask?.cancel()
            finalizeVoiceTask = nil
            tts.stop()
            stt.startListening()
        }
    }

    private func parseResponse(_ response: String) -> (message: String, options: [String]) {
        let parts = response.components(separatedBy: "OPTIONS:")
        let message = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)

        var options: [String] = []
        if parts.count > 1 {
            options = parts[1]
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return (message, options)
    }
}
