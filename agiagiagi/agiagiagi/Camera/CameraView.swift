//
//  CameraView.swift
//  agiagiagi
//
//  Created by Bektur Ryskeldiev on 2026/02/28.
//

import SwiftUI

struct CameraView: View {
    var body: some View {
        NavigationStack {
            LiveCameraView()
                .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    CameraView()
}
