//
//  ARCameraView.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import SwiftUI
import ARKit
import RealityKit
import Combine

struct ARCameraView: View {
    @StateObject private var sessionManager = ARSessionManager()
    @Binding var frozenAnalysis: PanelAnalysis?
    @Binding var frozenImage: UIImage?
    @Binding var frozenImageData: Data?
    @Binding var didFreeze: Bool

    @State private var showScanAnimation = true
    @State private var scanPulse = false

    var body: some View {
        ZStack {
            // AR View
            ARViewContainer(sessionManager: sessionManager)
                .ignoresSafeArea()

            // 2D overlay when we have analysis results
            if let analysis = sessionManager.currentAnalysis {
                GeometryReader { geometry in
                    ForEach(analysis.elements) { element in
                        let bbox = element.bbox
                        let x = bbox.x * geometry.size.width
                        let y = bbox.y * geometry.size.height
                        let w = bbox.width * geometry.size.width
                        let h = bbox.height * geometry.size.height

                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(colorForElement(element), lineWidth: 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(colorForElement(element).opacity(0.12))
                                )
                                .frame(width: w, height: h)

                            if !displayText(for: element).isEmpty {
                                Text(displayText(for: element))
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(colorForElement(element).opacity(0.85))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .offset(y: -20)
                            }
                        }
                        .position(x: x + w / 2, y: y + h / 2)
                    }
                }
                .allowsHitTesting(false)
            }

            // Scanning animation overlay
            if showScanAnimation && sessionManager.currentAnalysis == nil && !sessionManager.isFrozen {
                ScanningOverlay(isAnimating: $scanPulse)
                    .allowsHitTesting(false)
            }

            // Bottom controls
            VStack {
                Spacer()

                // Status bar
                HStack {
                    // Plane detection indicator
                    Circle()
                        .fill(sessionManager.planeDetected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Text(sessionManager.statusMessage)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)

                    Spacer()

                    if let analysis = sessionManager.currentAnalysis {
                        Text("\(analysis.elements.count) elements")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)

                // Freeze button
                Button {
                    freezeAndCapture()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.circle.fill")
                            .font(.title2)
                        Text("Freeze & Analyze")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
            }
            .padding(.bottom, 16)
        }
        .onAppear {
            scanPulse = true
        }
        .onDisappear {
            sessionManager.stopSession()
        }
    }

    private func freezeAndCapture() {
        sessionManager.freezeAndAnalyze()

        // Wait briefly for the analysis to come back, then pass data up
        Task {
            // Give the freeze analysis a moment
            try? await Task.sleep(for: .milliseconds(500))

            // Pass whatever we have
            frozenAnalysis = sessionManager.currentAnalysis
            frozenImage = sessionManager.capturedImage
            frozenImageData = sessionManager.capturedImageData
            didFreeze = true
        }
    }

    private func displayText(for element: PanelElement) -> String {
        if let translation = element.translations.first, !translation.text.isEmpty {
            return translation.text
        }
        return element.displayLabel
    }

    private func colorForElement(_ element: PanelElement) -> Color {
        switch element.kind {
        case "button": return .blue
        case "display": return .purple
        case "led": return .green
        case "switch": return .orange
        case "camera": return .red
        case "microphone", "speaker": return .cyan
        default: return .yellow
        }
    }
}

// MARK: - AR View Container

struct ARViewContainer: UIViewRepresentable {
    let sessionManager: ARSessionManager

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        // Attach and start
        sessionManager.attach(arView: arView)
        sessionManager.startSession()

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Overlay updates happen via the 2D SwiftUI overlay, not RealityKit entities
    }
}

// MARK: - Scanning Overlay

struct ScanningOverlay: View {
    @Binding var isAnimating: Bool
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Corner brackets
            VStack {
                HStack {
                    ScanCorner(rotation: 0)
                    Spacer()
                    ScanCorner(rotation: 90)
                }
                Spacer()
                HStack {
                    ScanCorner(rotation: 270)
                    Spacer()
                    ScanCorner(rotation: 180)
                }
            }
            .padding(40)
            .opacity(isAnimating ? 0.8 : 0.3)
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)

            // Scanning line
            GeometryReader { scanGeo in
                VStack {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .blue.opacity(0.5), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 2)
                        .offset(y: isAnimating ? scanGeo.size.height * 0.3 : -scanGeo.size.height * 0.3)
                        .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isAnimating)
                }
            }
            .clipped()
            .padding(40)

            // Center crosshair
            Image(systemName: "viewfinder")
                .font(.system(size: 60, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.4))
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
        }
    }
}

struct ScanCorner: View {
    let rotation: Double

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 20, y: 0))
            context.stroke(path, with: .color(.white), lineWidth: 3)
        }
        .frame(width: 24, height: 24)
        .rotationEffect(.degrees(rotation))
    }
}
