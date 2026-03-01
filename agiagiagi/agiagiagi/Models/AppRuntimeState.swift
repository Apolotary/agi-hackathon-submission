//
//  AppRuntimeState.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

/// Runtime state machine for the embodied AI companion.
/// Transitions follow the execution plan's rules.
enum AppRuntimeState: String, CaseIterable {
    case idle           // App open, camera not active
    case cameraActive   // Camera feed running, not yet analyzing
    case perceiving     // Analyzing current frame
    case prompting      // Showing observation/question to user
    case acting         // User engaged, artifact generating/active
    case verifying      // Checking step completion
    case learning       // Recording outcome to session/memory
    case paused         // User paused the companion
    case errorSafe      // Error or unsafe state — guidance only, no actions

    var displayLabel: String {
        switch self {
        case .idle: return "Idle"
        case .cameraActive: return "Watching"
        case .perceiving: return "Looking..."
        case .prompting: return "Ready"
        case .acting: return "Working"
        case .verifying: return "Checking"
        case .learning: return "Remembering"
        case .paused: return "Paused"
        case .errorSafe: return "Safe Mode"
        }
    }

    var isSensing: Bool {
        self == .cameraActive || self == .perceiving
    }

    var allowsProactivePrompt: Bool {
        self == .cameraActive || self == .perceiving || self == .prompting
    }

    var allowsArtifactGeneration: Bool {
        self == .prompting
    }

    var isActionable: Bool {
        self != .errorSafe && self != .paused
    }

    /// Valid transitions from this state
    var validTransitions: Set<AppRuntimeState> {
        switch self {
        case .idle:
            return [.cameraActive, .paused]
        case .cameraActive:
            return [.perceiving, .paused, .idle, .errorSafe]
        case .perceiving:
            return [.prompting, .cameraActive, .paused, .errorSafe]
        case .prompting:
            return [.acting, .perceiving, .cameraActive, .paused, .errorSafe]
        case .acting:
            return [.verifying, .prompting, .cameraActive, .acting, .idle, .paused, .errorSafe]
        case .verifying:
            return [.learning, .acting, .errorSafe, .paused]
        case .learning:
            return [.perceiving, .cameraActive, .paused]
        case .paused:
            return [.cameraActive, .idle]
        case .errorSafe:
            return [.cameraActive, .idle, .paused]
        }
    }

    /// Attempt a transition; returns the new state if valid, nil if rejected
    func transition(to next: AppRuntimeState) -> AppRuntimeState? {
        guard validTransitions.contains(next) else {
            print("[StateMachine] Rejected transition: \(self.rawValue) -> \(next.rawValue)")
            return nil
        }
        return next
    }
}
