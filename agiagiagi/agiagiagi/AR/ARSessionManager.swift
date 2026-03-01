//
//  ARSessionManager.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation
import ARKit
import RealityKit
import UIKit
import Combine

@MainActor
class ARSessionManager: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var planeDetected = false
    @Published var currentAnalysis: PanelAnalysis?
    @Published var capturedImage: UIImage?
    @Published var capturedImageData: Data?
    @Published var statusMessage = "Point at a control panel"
    @Published var isFrozen = false

    var frameInterval: TimeInterval = 4.0

    private var analysisTimer: Timer?
    private var isAnalyzing = false
    private weak var arView: ARView?
    private var lastFrameBuffer: CVPixelBuffer?

    func attach(arView: ARView) {
        self.arView = arView
    }

    func startSession() {
        guard let arView else { return }

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.vertical, .horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        arView.session.delegate = self

        isScanning = true
        planeDetected = false
        currentAnalysis = nil
        capturedImage = nil
        capturedImageData = nil
        isFrozen = false
        statusMessage = "Scanning for surfaces..."

        startPeriodicCapture()
    }

    func stopSession() {
        guard let arView else { return }
        arView.session.pause()
        isScanning = false
        stopPeriodicCapture()
    }

    func freezeAndAnalyze() {
        guard let arView else { return }
        stopPeriodicCapture()
        isFrozen = true
        statusMessage = "Capturing..."

        guard let frame = arView.session.currentFrame else {
            statusMessage = "No frame available"
            isFrozen = false
            return
        }

        let uiImage = imageFromPixelBuffer(frame.capturedImage)
        capturedImage = uiImage

        if let jpegData = uiImage.jpegData(compressionQuality: 0.85) {
            capturedImageData = jpegData
            statusMessage = "Analyzing full resolution..."
            Task {
                await analyzeImage(jpegData)
            }
        }
    }

    // MARK: - Periodic Capture

    private func startPeriodicCapture() {
        stopPeriodicCapture()
        analysisTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureAndAnalyzeFrame()
            }
        }
    }

    private func stopPeriodicCapture() {
        analysisTimer?.invalidate()
        analysisTimer = nil
    }

    private func captureAndAnalyzeFrame() {
        guard !isAnalyzing, !isFrozen, let arView else { return }
        guard let frame = arView.session.currentFrame else { return }

        let uiImage = imageFromPixelBuffer(frame.capturedImage)

        // Use lower quality for periodic scans to reduce latency
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.5) else { return }

        Task {
            await analyzeImage(jpegData)
        }
    }

    private func analyzeImage(_ imageData: Data) async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let analysis = try await MistralAPI.shared.analyzePanel(imageData: imageData)
            self.currentAnalysis = analysis
            if !isFrozen {
                let count = analysis.elements.count
                statusMessage = "\(count) element\(count == 1 ? "" : "s") detected"
            }
        } catch {
            print("[ARSessionManager] analysis error: \(error)")
            if !isFrozen {
                statusMessage = "Analysis failed, retrying..."
            }
        }
    }

    // MARK: - Image Conversion

    private func imageFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: width, height: height)) else {
            return UIImage()
        }
        // ARKit frames come in landscape orientation
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
    }
}

// MARK: - ARSessionDelegate

extension ARSessionManager: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let hasPlane = anchors.contains { $0 is ARPlaneAnchor }
        if hasPlane {
            Task { @MainActor in
                if !self.planeDetected {
                    self.planeDetected = true
                    self.statusMessage = "Surface found. Analyzing..."
                }
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Keep a reference to the latest frame buffer for on-demand capture
        Task { @MainActor in
            self.lastFrameBuffer = frame.capturedImage
        }
    }
}
