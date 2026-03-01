//
//  CameraResultView.swift
//  agiagiagi
//
//  Created by Bektur Ryskeldiev on 2026/02/28.
//

import SwiftUI

struct CameraResultView: View {
    let image: UIImage
    let analysis: PanelAnalysis
    let wizard: ActionWizard

    @State private var selectedElement: PanelElement?
    @State private var showElementDetail = false

    var body: some View {
        VStack(spacing: 0) {
            // Top half: panel image with bounding box overlay
            PanelOverlayView(
                image: image,
                analysis: analysis,
                selectedElement: $selectedElement
            )
            .frame(maxHeight: .infinity)
            .clipped()

            Divider()

            // Bottom half: wizard WebView
            WizardWebView(wizard: wizard) { message in
                print("[CameraResultView] wizard message: \(message)")
            }
            .frame(maxHeight: .infinity)
        }
        .navigationTitle(wizard.goal.replacingOccurrences(of: "_", with: " ").capitalized)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedElement?.id) { _, _ in
            if selectedElement != nil {
                showElementDetail = true
            }
        }
        .sheet(isPresented: $showElementDetail, onDismiss: { selectedElement = nil }) {
            if let element = selectedElement {
                ElementDetailSheet(element: element)
                    .presentationDetents([.medium])
            }
        }
    }
}

// MARK: - Element Detail Sheet

private struct ElementDetailSheet: View {
    let element: PanelElement

    var body: some View {
        NavigationStack {
            List {
                Section("Element") {
                    LabeledContent("ID", value: element.elementId)
                    LabeledContent("Type", value: element.kind)
                    LabeledContent("Confidence", value: "\(Int(element.confidence * 100))%")
                }

                Section("Label") {
                    if let label = element.label {
                        if !label.rawText.isEmpty {
                            LabeledContent("Original", value: label.rawText)
                        }
                        if !label.normalizedText.isEmpty {
                            LabeledContent("Normalized", value: label.normalizedText)
                        }
                    }
                    if let original = element.originalText, !original.isEmpty {
                        LabeledContent("Text", value: original)
                    }
                    if let translated = element.translatedText, !translated.isEmpty {
                        LabeledContent("Translated", value: translated)
                    }
                }

                if !element.translations.isEmpty {
                    Section("Translations") {
                        ForEach(element.translations, id: \.language) { translation in
                            LabeledContent(translation.language.uppercased(), value: translation.text)
                        }
                    }
                }

                Section("Bounding Box") {
                    LabeledContent("X", value: String(format: "%.3f", element.bbox.x))
                    LabeledContent("Y", value: String(format: "%.3f", element.bbox.y))
                    LabeledContent("Width", value: String(format: "%.3f", element.bbox.width))
                    LabeledContent("Height", value: String(format: "%.3f", element.bbox.height))
                }

                if !element.evidence.isEmpty {
                    Section("Evidence") {
                        ForEach(element.evidence, id: \.rawValue) { ev in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ev.type)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                Text(ev.rawValue)
                                    .font(.body)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Element Detail")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
