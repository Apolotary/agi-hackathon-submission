//
//  AROverlayManager.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation
import RealityKit
import ARKit
import UIKit

class AROverlayManager {

    private var overlayAnchor: AnchorEntity?
    private var overlayEntities: [Entity] = []

    /// Update overlays in the AR scene based on PanelAnalysis.
    /// Uses a simple screen-space approach: creates a plane at the detected AR anchor
    /// and maps normalized bounding boxes onto it.
    func updateOverlays(analysis: PanelAnalysis, in arView: ARView) {
        clearOverlays(in: arView)

        // Find the largest detected plane anchor to use as our panel surface
        guard let planeAnchor = arView.session.currentFrame?.anchors
            .compactMap({ $0 as? ARPlaneAnchor })
            .max(by: { $0.extent.x * $0.extent.z < $1.extent.x * $1.extent.z })
        else {
            // No plane found - use a world anchor 0.5m in front of camera
            updateOverlaysScreenSpace(analysis: analysis, in: arView)
            return
        }

        let anchor = AnchorEntity(anchor: planeAnchor)
        overlayAnchor = anchor

        let planeWidth = planeAnchor.extent.x
        let planeHeight = planeAnchor.extent.z

        for element in analysis.elements {
            let bbox = element.bbox

            // Map normalized coords to plane coords (centered on anchor)
            let x = (Float(bbox.x) + Float(bbox.width) / 2.0 - 0.5) * planeWidth
            let z = (Float(bbox.y) + Float(bbox.height) / 2.0 - 0.5) * planeHeight
            let boxWidth = Float(bbox.width) * planeWidth
            let boxHeight = Float(bbox.height) * planeHeight

            // Create wireframe box
            let boxMesh = MeshResource.generateBox(
                width: boxWidth,
                height: 0.002,
                depth: boxHeight,
                cornerRadius: 0.001
            )
            let color = uiColorForElement(element)
            var material = UnlitMaterial(color: color.withAlphaComponent(0.4))
            material.color.tint = color.withAlphaComponent(0.4)

            let boxEntity = ModelEntity(mesh: boxMesh, materials: [material])
            boxEntity.position = SIMD3<Float>(x, 0.002, z)

            anchor.addChild(boxEntity)
            overlayEntities.append(boxEntity)

            // Create text label
            let labelText = displayText(for: element)
            if !labelText.isEmpty {
                let textMesh = MeshResource.generateText(
                    labelText,
                    extrusionDepth: 0.001,
                    font: .systemFont(ofSize: 0.015, weight: .bold),
                    containerFrame: .zero,
                    alignment: .center,
                    lineBreakMode: .byTruncatingTail
                )
                var textMaterial = UnlitMaterial(color: .white)
                textMaterial.color.tint = .white

                let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
                // Position label slightly above the box
                textEntity.position = SIMD3<Float>(x - boxWidth / 2, 0.005, z - boxHeight / 2 - 0.01)

                anchor.addChild(textEntity)
                overlayEntities.append(textEntity)
            }
        }

        arView.scene.addAnchor(anchor)
    }

    /// Fallback: place overlays in screen space using a fixed anchor in front of camera
    private func updateOverlaysScreenSpace(analysis: PanelAnalysis, in arView: ARView) {
        guard let cameraTransform = arView.session.currentFrame?.camera.transform else { return }

        // Place anchor 0.5m in front of camera
        var translation = matrix_identity_float4x4
        translation.columns.3.z = -0.5

        let anchorTransform = cameraTransform * translation
        let worldAnchor = ARAnchor(transform: anchorTransform)
        arView.session.add(anchor: worldAnchor)

        let anchor = AnchorEntity(anchor: worldAnchor)
        overlayAnchor = anchor

        let panelWidth: Float = 0.3
        let panelHeight: Float = 0.4

        for element in analysis.elements {
            let bbox = element.bbox

            let x = (Float(bbox.x) + Float(bbox.width) / 2.0 - 0.5) * panelWidth
            let y = -(Float(bbox.y) + Float(bbox.height) / 2.0 - 0.5) * panelHeight
            let boxWidth = Float(bbox.width) * panelWidth
            let boxHeight = Float(bbox.height) * panelHeight

            let boxMesh = MeshResource.generateBox(
                width: boxWidth,
                height: boxHeight,
                depth: 0.001,
                cornerRadius: 0.001
            )
            let color = uiColorForElement(element)
            var material = UnlitMaterial(color: color.withAlphaComponent(0.35))
            material.color.tint = color.withAlphaComponent(0.35)

            let boxEntity = ModelEntity(mesh: boxMesh, materials: [material])
            boxEntity.position = SIMD3<Float>(x, y, 0)

            anchor.addChild(boxEntity)
            overlayEntities.append(boxEntity)

            let labelText = displayText(for: element)
            if !labelText.isEmpty {
                let textMesh = MeshResource.generateText(
                    labelText,
                    extrusionDepth: 0.0005,
                    font: .systemFont(ofSize: 0.008, weight: .bold),
                    containerFrame: .zero,
                    alignment: .center,
                    lineBreakMode: .byTruncatingTail
                )
                var textMaterial = UnlitMaterial(color: .white)
                textMaterial.color.tint = .white

                let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
                textEntity.position = SIMD3<Float>(x - boxWidth / 2, y + boxHeight / 2 + 0.005, 0.001)

                anchor.addChild(textEntity)
                overlayEntities.append(textEntity)
            }
        }

        arView.scene.addAnchor(anchor)
    }

    func clearOverlays(in arView: ARView) {
        if let anchor = overlayAnchor {
            arView.scene.removeAnchor(anchor)
        }
        overlayAnchor = nil
        overlayEntities.removeAll()
    }

    // MARK: - Helpers

    private func displayText(for element: PanelElement) -> String {
        if let translation = element.translations.first, !translation.text.isEmpty {
            return translation.text
        }
        return element.displayLabel
    }

    private func uiColorForElement(_ element: PanelElement) -> UIColor {
        switch element.kind {
        case "button": return .systemBlue
        case "display": return .systemPurple
        case "led": return .systemGreen
        case "switch": return .systemOrange
        case "camera": return .systemRed
        case "microphone", "speaker": return .systemCyan
        default: return .systemYellow
        }
    }
}
