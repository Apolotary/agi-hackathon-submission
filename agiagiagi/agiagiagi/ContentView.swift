//
//  ContentView.swift
//  agiagiagi
//
//  Created by Bektur Ryskeldiev on 2026/02/28.
//

import SwiftUI

struct ContentView: View {
    @State private var isOnboardingComplete = UserDefaults.standard.bool(forKey: "onboarding_completed")
    @State private var selectedTab = 0

    var body: some View {
        if isOnboardingComplete {
            TabView(selection: $selectedTab) {
                Tab("Home", systemImage: "house.fill", value: 0) {
                    HomeView()
                }
                Tab("Camera", systemImage: "camera.fill", value: 1) {
                    CameraView()
                }
                Tab("Settings", systemImage: "gearshape.fill", value: 2) {
                    SettingsView()
                }
            }
            .toolbarVisibility(selectedTab == 1 ? .hidden : .visible, for: .tabBar)
        } else {
            OnboardingView(isOnboardingComplete: $isOnboardingComplete)
        }
    }
}

#Preview {
    ContentView()
}
