//
//  agiagiagiApp.swift
//  agiagiagi
//
//  Created by Bektur Ryskeldiev on 2026/02/28.
//

import SwiftUI

@main
struct agiagiagiApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // One-time migration from UserDefaults to Keychain
        KeychainManager.migrateFromUserDefaults()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                saveSessionSummary()
            }
        }
    }

    private func saveSessionSummary() {
        let trace = AgentTraceCollector.shared
        let sessionDuration = Int(Date().timeIntervalSince(trace.sessionStartTime))
        guard trace.totalAPICalls > 0 else { return }

        let summary = [
            "session_duration": sessionDuration,
            "api_calls": trace.totalAPICalls,
            "events": trace.events.count
        ] as [String: Int]

        UserDefaults.standard.set(summary, forKey: "last_session_summary")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "last_session_time")
    }
}
