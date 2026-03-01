//
//  PanelOverlayView.swift
//  agiagiagi
//
//  Created by Bektur Ryskeldiev on 2026/02/28.
//

import SwiftUI

struct PanelOverlayView: View {
    let image: UIImage
    let analysis: PanelAnalysis
    @Binding var selectedElement: PanelElement?

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    let viewWidth = geometry.size.width
                    let viewHeight = geometry.size.height

                    ForEach(analysis.elements) { element in
                        let bbox = element.bbox
                        let x = bbox.x * viewWidth
                        let y = bbox.y * viewHeight
                        let w = bbox.width * viewWidth
                        let h = bbox.height * viewHeight

                        ZStack(alignment: .topLeading) {
                            // Bounding box
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(colorForElement(element), lineWidth: 2)
                                .frame(width: w, height: h)

                            // Label above the box
                            if !displayText(for: element).isEmpty {
                                Text(displayText(for: element))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(colorForElement(element).opacity(0.85))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .offset(y: -20)
                            }
                        }
                        .position(x: x + w / 2, y: y + h / 2)
                        .onTapGesture {
                            selectedElement = element
                        }
                    }
                }
            }
    }

    private func displayText(for element: PanelElement) -> String {
        // Prefer translation, fall back to label, fall back to displayLabel
        if let translation = element.translations.first, !translation.text.isEmpty {
            return translation.text
        }
        if let label = element.label {
            if !label.normalizedText.isEmpty { return label.normalizedText }
            if !label.rawText.isEmpty { return label.rawText }
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
