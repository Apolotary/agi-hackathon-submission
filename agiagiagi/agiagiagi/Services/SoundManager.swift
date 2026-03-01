//
//  SoundManager.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import AVFoundation
import UIKit

@Observable
final class SoundManager {
    static let shared = SoundManager()

    var isMuted = false

    // Separate players for BGM (loops) and SFX (one-shots)
    private var bgmPlayer: AVAudioPlayer?
    private var sfxPlayer: AVAudioPlayer?
    private var currentBGM: BGM?

    enum BGM: String {
        case idle = "idle_ambient"
        case observing = "observing_drone"
        case narration = "narration_bed"
        case tension = "tension_ambient"
    }

    enum SFX: String {
        case bubbleAppear = "bubble_appear"
        case artifactOpen = "artifact_open"
        case artifactClose = "artifact_close"
        case artifactReveal = "artifact_reveal"
        case modeSwitch = "mode_switch"
        case errorSound = "error_sound"
        case objectDetected = "object_detected"
        case pinNote = "pin_note"
        case thinkingTick = "thinking_tick"
        case successChime = "success_chime"
        case scrollPast = "scroll_past"
    }

    private init() {
        // Configure audio session for mixing with other apps
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - BGM

    func playBGM(_ bgm: BGM, volume: Float = 0.08, fadeIn: Bool = true) {
        guard !isMuted else { return }
        guard bgm != currentBGM else { return }

        stopBGM(fadeOut: true)
        currentBGM = bgm

        guard let url = Bundle.main.url(forResource: bgm.rawValue, withExtension: "mp3", subdirectory: nil) else {
            print("[SoundManager] BGM not found: \(bgm.rawValue)")
            return
        }

        do {
            bgmPlayer = try AVAudioPlayer(contentsOf: url)
            bgmPlayer?.numberOfLoops = -1 // loop forever
            bgmPlayer?.volume = fadeIn ? 0 : volume

            bgmPlayer?.prepareToPlay()
            bgmPlayer?.play()

            if fadeIn {
                fadeVolume(player: bgmPlayer, to: volume, duration: 1.5)
            }
        } catch {
            print("[SoundManager] BGM play error: \(error)")
        }
    }

    func stopBGM(fadeOut: Bool = true) {
        guard let player = bgmPlayer else { return }
        currentBGM = nil

        if fadeOut {
            fadeVolume(player: player, to: 0, duration: 0.8) {
                player.stop()
            }
        } else {
            player.stop()
        }
        bgmPlayer = nil
    }

    // MARK: - SFX

    func play(_ sfx: SFX, volume: Float = 0.3) {
        guard !isMuted else { return }

        guard let url = Bundle.main.url(forResource: sfx.rawValue, withExtension: "mp3", subdirectory: nil) else {
            print("[SoundManager] SFX not found: \(sfx.rawValue)")
            return
        }

        do {
            sfxPlayer = try AVAudioPlayer(contentsOf: url)
            sfxPlayer?.volume = volume
            sfxPlayer?.prepareToPlay()
            sfxPlayer?.play()
        } catch {
            print("[SoundManager] SFX play error: \(error)")
        }
    }

    // MARK: - State-driven BGM

    func updateBGMForState(_ state: AppRuntimeState, isGenerating: Bool = false) {
        guard !isMuted else { return }

        switch state {
        case .idle, .paused:
            stopBGM()
        case .cameraActive:
            playBGM(.idle)
        case .perceiving:
            playBGM(.observing)
        case .prompting:
            playBGM(.narration)
        case .acting:
            if isGenerating {
                playBGM(.observing)
            } else {
                playBGM(.narration)
            }
        case .verifying, .learning:
            playBGM(.narration)
        case .errorSafe:
            playBGM(.tension)
        }
    }

    // MARK: - TTS Ducking

    private var preDuckVolume: Float = 0.08

    func duckForNarration() {
        guard let player = bgmPlayer else { return }
        preDuckVolume = player.volume
        fadeVolume(player: player, to: 0.02, duration: 0.15)
    }

    func unduckAfterNarration() {
        guard let player = bgmPlayer else { return }
        fadeVolume(player: player, to: preDuckVolume, duration: 0.3)
    }

    // MARK: - Helpers

    private func fadeVolume(player: AVAudioPlayer?, to target: Float, duration: TimeInterval, completion: (() -> Void)? = nil) {
        guard let player else { completion?(); return }

        let steps = 20
        let interval = duration / Double(steps)
        let delta = (target - player.volume) / Float(steps)
        var step = 0

        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            step += 1
            player.volume = player.volume + delta

            if step >= steps {
                timer.invalidate()
                player.volume = target
                completion?()
            }
        }
    }
}
