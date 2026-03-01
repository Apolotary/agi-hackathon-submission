//
//  WizardWebView.swift
//  agiagiagi
//
//  Created by Bektur Ryskeldiev on 2026/02/28.
//

import SwiftUI
import WebKit

struct WizardWebView: UIViewRepresentable {
    let wizard: ActionWizard
    var onMessage: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onMessage: onMessage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "wizard")
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // Load the template from bundle
        if let htmlURL = Bundle.main.url(forResource: "wizard-template", withExtension: "html") {
            let cssURL = Bundle.main.url(forResource: "styles", withExtension: "css")
            let baseURL = cssURL?.deletingLastPathComponent() ?? htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: baseURL)
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.pendingWizard = wizard
        context.coordinator.injectWizardIfReady()
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var webView: WKWebView?
        var onMessage: ((String) -> Void)?
        var isPageLoaded = false
        var pendingWizard: ActionWizard?

        init(onMessage: ((String) -> Void)?) {
            self.onMessage = onMessage
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? String {
                onMessage?(body)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageLoaded = true
            injectWizardIfReady()
        }

        func injectWizardIfReady() {
            guard isPageLoaded, let wizard = pendingWizard, let webView else { return }

            do {
                let data = try JSONEncoder().encode(wizard)
                guard let jsonString = String(data: data, encoding: .utf8) else { return }
                // Escape for JS single-quoted string
                let escaped = jsonString
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'")
                    .replacingOccurrences(of: "\n", with: "\\n")
                webView.evaluateJavaScript("updateWizard('\(escaped)')") { _, error in
                    if let error {
                        print("[WizardWebView] JS injection error: \(error)")
                    }
                }
                pendingWizard = nil
            } catch {
                print("[WizardWebView] encoding error: \(error)")
            }
        }
    }
}
