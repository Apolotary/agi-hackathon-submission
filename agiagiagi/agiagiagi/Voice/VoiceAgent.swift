//
//  VoiceAgent.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

enum ConversationState: String {
    case idle
    case connecting
    case active
    case ended
}

protocol VoiceAgentProtocol: AnyObject {
    var state: ConversationState { get }
    func startConversation(agentId: String) async throws
    func endConversation()
    func send(text: String) async throws
}

/// Mock voice agent that uses Mistral streaming + ElevenLabs TTS as a simulated voice conversation.
/// Can be swapped for the real ElevenLabs Conversational AI SDK later.
@Observable
final class MockVoiceAgent: VoiceAgentProtocol {
    var state: ConversationState = .idle
    var lastResponse: String = ""

    private let tts = ElevenLabsTTS.shared
    private var conversationHistory: [ChatMessage] = []
    private var systemPrompt: String = ""

    func startConversation(agentId: String) async throws {
        state = .connecting

        systemPrompt = """
        You are a helpful panel assistant for AGI. You help users understand and operate \
        physical control panels like intercoms and thermostats. Keep responses concise and conversational \
        since they will be spoken aloud. Guide users step by step. Agent ID: \(agentId).
        """

        conversationHistory = [
            ChatMessage.system(systemPrompt)
        ]

        state = .active
    }

    func endConversation() {
        tts.stop()
        conversationHistory.removeAll()
        state = .ended

        // Reset to idle after a moment
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            state = .idle
        }
    }

    func send(text: String) async throws {
        guard state == .active else { return }

        conversationHistory.append(ChatMessage.user(text))

        var fullResponse = ""
        let stream = MistralAPI.shared.streamChat(
            messages: conversationHistory,
            model: .ministral8b
        )

        for try await token in stream {
            fullResponse += token
        }

        conversationHistory.append(ChatMessage.assistant(fullResponse))
        lastResponse = fullResponse

        // Speak the response via TTS
        try? await tts.speak(text: fullResponse)
    }
}
