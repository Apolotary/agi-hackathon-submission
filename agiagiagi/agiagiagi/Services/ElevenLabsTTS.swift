//
//  ElevenLabsTTS.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation
import AVFoundation

// MARK: - Stat Voice Profile

struct StatVoiceProfile {
    let stability: Double
    let similarityBoost: Double
    let speed: Double

    static let `default` = StatVoiceProfile(stability: 0.5, similarityBoost: 0.75, speed: 1.0)

    static func forStat(_ stat: CompanionStat) -> StatVoiceProfile {
        switch stat {
        case .inlandEmpire:
            return StatVoiceProfile(stability: 0.3, similarityBoost: 0.85, speed: 0.9)
        case .encyclopedia:
            return StatVoiceProfile(stability: 0.7, similarityBoost: 0.6, speed: 1.1)
        case .empathy:
            return StatVoiceProfile(stability: 0.4, similarityBoost: 0.9, speed: 0.95)
        case .visualCalculus:
            return StatVoiceProfile(stability: 0.65, similarityBoost: 0.65, speed: 1.05)
        case .electrochemistry:
            return StatVoiceProfile(stability: 0.25, similarityBoost: 0.8, speed: 1.15)
        case .rhetoric:
            return StatVoiceProfile(stability: 0.55, similarityBoost: 0.7, speed: 1.0)
        case .shivers:
            return StatVoiceProfile(stability: 0.2, similarityBoost: 0.9, speed: 0.85)
        case .conceptualization:
            return StatVoiceProfile(stability: 0.45, similarityBoost: 0.75, speed: 0.95)
        }
    }
}

@Observable
final class ElevenLabsTTS: NSObject, AVAudioPlayerDelegate {
    static let shared = ElevenLabsTTS()

    var isSpeaking = false

    private var audioPlayer: AVAudioPlayer?
    private var speakContinuation: CheckedContinuation<Void, Error>?
    private let defaultVoiceId = "21m00Tcm4TlvDq8ikWAM" // Rachel

    private var apiKey: String {
        KeychainManager.shared.load("elevenlabs_api_key")
            ?? UserDefaults.standard.string(forKey: "elevenlabs_api_key")
            ?? ""
    }

    private var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private override init() {
        super.init()
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("[ElevenLabsTTS] Failed to configure audio session: \(error)")
        }
    }

    func speak(text: String, voiceId: String? = nil, voiceProfile: StatVoiceProfile? = nil) async throws {
        guard hasAPIKey else {
            print("[ElevenLabsTTS] No API key configured")
            throw ElevenLabsTTSError.noAPIKey
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stop()

        let vid = voiceId ?? defaultVoiceId
        let urlString = "https://api.elevenlabs.io/v1/text-to-speech/\(vid)/stream"
        guard let url = URL(string: urlString) else {
            throw ElevenLabsTTSError.invalidURL
        }

        let profile = voiceProfile ?? .default

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": trimmed,
            "model_id": "eleven_flash_v2_5",
            "voice_settings": [
                "stability": profile.stability,
                "similarity_boost": profile.similarityBoost,
                "speed": profile.speed
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[ElevenLabsTTS] Requesting TTS for \(trimmed.prefix(50))...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsTTSError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[ElevenLabsTTS] HTTP \(httpResponse.statusCode): \(errorBody)")
            throw ElevenLabsTTSError.httpError(httpResponse.statusCode, errorBody)
        }

        // Save to temp file and play
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("tts_\(UUID().uuidString).mp3")
        try data.write(to: tempURL)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let player = try AVAudioPlayer(contentsOf: tempURL)
                player.delegate = self
                self.audioPlayer = player
                self.speakContinuation = continuation

                self.isSpeaking = true
                player.play()
                print("[ElevenLabsTTS] Playing audio, duration=\(player.duration)s")
            } catch {
                continuation.resume(throwing: error)
            }
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil

        if let continuation = speakContinuation {
            speakContinuation = nil
            continuation.resume(throwing: CancellationError())
        }

        isSpeaking = false
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isSpeaking = false
            if let continuation = self.speakContinuation {
                self.speakContinuation = nil
                continuation.resume()
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.isSpeaking = false
            if let continuation = self.speakContinuation {
                self.speakContinuation = nil
                continuation.resume(throwing: error ?? ElevenLabsTTSError.playbackFailed)
            }
        }
    }
}

enum ElevenLabsTTSError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case httpError(Int, String)
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No ElevenLabs API key configured"
        case .invalidURL:
            return "Invalid TTS URL"
        case .invalidResponse:
            return "Invalid response from ElevenLabs"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .playbackFailed:
            return "Audio playback failed"
        }
    }
}
