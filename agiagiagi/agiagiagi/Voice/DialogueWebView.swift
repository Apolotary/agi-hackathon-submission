//
//  DialogueWebView.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import SwiftUI
import WebKit

struct DialogueWebView: UIViewRepresentable {
    let bridge: DialogueBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "dialogue")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        bridge.webView = webView

        // Load the dialogue template from bundle
        if let htmlURL = Bundle.main.url(forResource: "dialogue-template", withExtension: "html") {
            let cssURL = Bundle.main.url(forResource: "styles", withExtension: "css")
            let baseURL = cssURL?.deletingLastPathComponent() ?? htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: baseURL)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "dialogue")
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler {
        let bridge: DialogueBridge

        init(bridge: DialogueBridge) {
            self.bridge = bridge
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "dialogue",
                  let body = message.body as? String,
                  let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let action = json["action"] as? String else {
                return
            }

            switch action {
            case "select":
                if let optionId = json["optionId"] as? String {
                    self.bridge.onAction?(.selectOption(optionId))
                }
            case "text":
                if let content = json["content"] as? String {
                    self.bridge.onAction?(.sendText(content))
                }
            default:
                break
            }
        }
    }
}

// MARK: - DialogueBridge

/// Bridge object that allows DialogueView to call JS methods on the WKWebView.
@Observable
final class DialogueBridge {
    weak var webView: WKWebView?
    var onAction: ((DialogueAction) -> Void)?

    func addMessage(role: String, content: String) {
        let escaped = escapeForJS(content)
        let js = "addMessage('{\"role\":\"\(role)\",\"content\":\"\(escaped)\"}')"
        webView?.evaluateJavaScript(js)
    }

    func setOptions(_ options: [(id: String, text: String)]) {
        if options.isEmpty {
            showTextInput()
            return
        }
        let optionsJSON = options.map { "{\"id\":\"\(escapeForJS($0.id))\",\"text\":\"\(escapeForJS($0.text))\"}" }
        let arrayStr = "[\(optionsJSON.joined(separator: ","))]"
        let js = "setOptions('\(arrayStr)')"
        webView?.evaluateJavaScript(js)
    }

    func setState(_ state: String) {
        let js = "setState('\(state)')"
        webView?.evaluateJavaScript(js)
    }

    func showTextInput() {
        webView?.evaluateJavaScript("showTextInput()")
    }

    private func escapeForJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

enum DialogueAction {
    case selectOption(String)
    case sendText(String)
}
