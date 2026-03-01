//
//  VoxtralSTT.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation
import AVFoundation

/// Voxtral Realtime speech-to-text via WebSocket.
/// Audio format: PCM 16-bit signed LE, 16 kHz, mono.
@Observable
final class VoxtralSTT: NSObject {
    static let shared = VoxtralSTT()

    var isListening = false
    var partialTranscript = ""
    var finalTranscript = ""

    private var webSocketTask: URLSessionWebSocketTask?
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var scheduledDisconnectToken: UUID?

    private let endpoint = "wss://api.mistral.ai/v1/realtime"
    private let sampleRate: Double = 16000

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "mistral_api_key") ?? ""
    }

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Start listening: opens WebSocket + microphone, streams audio chunks.
    func startListening() {
        guard !isListening else { return }
        guard !apiKey.isEmpty else {
            print("[VoxtralSTT] No Mistral API key")
            return
        }

        partialTranscript = ""
        finalTranscript = ""
        scheduledDisconnectToken = nil

        guard connectWebSocket() else { return }
        guard startAudioCapture() else {
            disconnectWebSocket()
            return
        }
        isListening = true
    }

    /// Stop listening: closes mic + WebSocket, commits buffer.
    func stopListening() {
        guard isListening else { return }
        isListening = false

        stopAudioCapture()

        // Commit the buffer to get final transcription
        sendJSON(["type": "input_audio_buffer.commit"])

        // Give the server a moment to finalize, then disconnect
        let token = UUID()
        scheduledDisconnectToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.scheduledDisconnectToken == token else { return }
            self.disconnectWebSocket()
            self.scheduledDisconnectToken = nil
        }
    }

    /// Cancel listening without waiting for final result.
    func cancel() {
        isListening = false
        stopAudioCapture()
        disconnectWebSocket()
        scheduledDisconnectToken = nil
        partialTranscript = ""
    }

    // MARK: - WebSocket

    private func connectWebSocket() -> Bool {
        guard let url = URL(string: endpoint) else { return false }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        // Send session config
        sendJSON([
            "type": "session.update",
            "model": "voxtral-mini-transcribe-realtime-2602",
            "target_streaming_delay_ms": 480
        ])

        receiveMessages()
        print("[VoxtralSTT] WebSocket connected")
        return true
    }

    private func disconnectWebSocket() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleServerMessage(text)
                default:
                    break
                }
                // Keep receiving
                self.receiveMessages()

            case .failure(let error):
                print("[VoxtralSTT] WebSocket receive error: \(error)")
            }
        }
    }

    private func handleServerMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "session.created":
            print("[VoxtralSTT] Session created")

        case "transcription.delta":
            if let delta = json["delta"] as? String {
                DispatchQueue.main.async {
                    self.partialTranscript += delta
                }
            }

        case "transcription.done":
            if let finalText = json["text"] as? String {
                DispatchQueue.main.async {
                    self.finalTranscript = finalText
                    self.partialTranscript = finalText
                    print("[VoxtralSTT] Final: \(finalText)")
                }
            }

        case "error":
            let errorMsg = json["error"] as? String ?? "unknown"
            print("[VoxtralSTT] Server error: \(errorMsg)")

        default:
            break
        }
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(str)) { error in
            if let error {
                print("[VoxtralSTT] Send error: \(error)")
            }
        }
    }

    // MARK: - Audio Capture

    private func startAudioCapture() -> Bool {
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        self.inputNode = inputNode

        // Configure audio session for recording
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setPreferredSampleRate(sampleRate)
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)
        } catch {
            print("[VoxtralSTT] Audio session error: \(error)")
            return false
        }

        // Target format: PCM 16-bit int, 16kHz, mono
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            print("[VoxtralSTT] Failed to create target format")
            return false
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Install a tap on the input node
        // We'll convert from the input format to our target format
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("[VoxtralSTT] Failed to create converter from \(inputFormat) to \(targetFormat)")
            return false
        }

        let bufferSize: AVAudioFrameCount = 4096

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self, self.isListening else { return }

            // Convert to 16kHz PCM16
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * self.sampleRate / inputFormat.sampleRate)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if let error {
                print("[VoxtralSTT] Conversion error: \(error)")
                return
            }
            guard convertedBuffer.frameLength > 0 else { return }

            // Extract raw PCM bytes and send as base64
            guard let channelData = convertedBuffer.int16ChannelData else { return }
            let byteCount = Int(convertedBuffer.frameLength) * 2 // 16-bit = 2 bytes per sample
            let data = Data(bytes: channelData[0], count: byteCount)
            let base64 = data.base64EncodedString()

            self.sendJSON([
                "type": "input_audio_buffer.append",
                "audio": base64
            ])
        }

        do {
            try engine.start()
            print("[VoxtralSTT] Audio engine started")
            return true
        } catch {
            print("[VoxtralSTT] Engine start error: \(error)")
            return false
        }
    }

    private func stopAudioCapture() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("[VoxtralSTT] Audio session deactivate error: \(error)")
        }
    }
}
