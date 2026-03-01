//
//  ArtifactWebView.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import SwiftUI
import WebKit
import UIKit
import AVFoundation
import AudioToolbox

enum ArtifactAction {
    case stepDone(String)        // stepId
    case stepFailed(String, String)  // stepId, reason
    case allDone
    case whyTapped               // user tapped "Why?"
    case dialogueReply(String)   // user picked a dialogue option
}

struct ArtifactWebView: UIViewRepresentable {
    let html: String
    let goal: String
    var confidence: Double = 0.5
    var riskLevel: String = "low"
    var onAction: ((ArtifactAction) -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(context.coordinator, name: "artifact")

        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.webView = webView
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = true
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.lastHTML = html
        context.coordinator.lastGoal = goal
        webView.loadHTMLString(Self.wrapHTML(html, goal: goal, confidence: confidence, riskLevel: riskLevel), baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastHTML != html || context.coordinator.lastGoal != goal {
            context.coordinator.lastHTML = html
            context.coordinator.lastGoal = goal
            webView.loadHTMLString(Self.wrapHTML(html, goal: goal, confidence: confidence, riskLevel: riskLevel), baseURL: nil)
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "artifact")
        coordinator.stopSpeaking()
    }

    // MARK: - Artifact Safety Gate

    /// Validates generated HTML for dangerous patterns before rendering.
    /// Returns a sanitized version or a fallback if the HTML is unsafe.
    static func validateArtifactHTML(_ html: String, goal: String) -> String {
        let lower = html.lowercased()

        // Block dangerous JS patterns
        let dangerousPatterns = [
            "eval(", "new function(", "fetch(", "xmlhttprequest",
            "websocket(", "importscripts(", "document.cookie",
            "localstorage", "sessionstorage", "indexeddb"
        ]

        var blocked: [String] = []
        for pattern in dangerousPatterns {
            if lower.contains(pattern) {
                blocked.append(pattern)
            }
        }

        // Block external URLs (except data: and blob: which are safe)
        let externalURLPattern = try? NSRegularExpression(
            pattern: #"(https?://[^\s\"'<>]+)"#,
            options: .caseInsensitive
        )
        let urlMatches = externalURLPattern?.numberOfMatches(
            in: html,
            range: NSRange(html.startIndex..., in: html)
        ) ?? 0

        if urlMatches > 5 {
            blocked.append("excessive external URLs (\(urlMatches))")
        }

        // Check for excessive size (could slow rendering)
        if html.count > 15000 {
            blocked.append("excessive size (\(html.count) chars)")
        }

        if !blocked.isEmpty {
            print("[ArtifactSafety] Blocked patterns in artifact: \(blocked.joined(separator: ", "))")
            return safetyFallbackHTML(goal: goal, reason: blocked.joined(separator: ", "))
        }

        return html
    }

    /// Fallback HTML shown when artifact fails validation
    private static func safetyFallbackHTML(goal: String, reason: String) -> String {
        let safeGoal = goal
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;background:transparent;color:#fff;font-family:-apple-system,sans-serif}
        .card{background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.18);backdrop-filter:blur(16px);border-radius:16px;padding:20px;text-align:center;margin:20px}
        .icon{font-size:32px;margin-bottom:8px}.title{font-weight:700;margin-bottom:6px}
        .sub{font-size:12px;color:rgba(255,255,255,.6);margin-bottom:12px}
        button{min-height:44px;border:0;border-radius:10px;padding:8px 16px;background:#22c55e;color:#062b12;font-weight:700;cursor:pointer}
        </style></head><body>
        <div class="card">
        <div class="icon">🛡️</div>
        <div class="title">Safety Check Failed</div>
        <div class="sub">The generated artifact contained patterns that were blocked for security: \(safeGoal)</div>
        <button onclick="try{AGI.haptic('light');AGI.reply('Retry with simpler output')}catch(e){}">Try Again</button>
        </div></body></html>
        """
    }

    /// Injects style overrides + a JS bridge so generated HTML can access native capabilities.
    private static func wrapHTML(_ html: String, goal: String, confidence: Double = 0.5, riskLevel: String = "low") -> String {
        // Compute CSS variable values from vibe metadata
        let riskHue: Int
        let riskGlow: String
        switch riskLevel {
        case "high":
            riskHue = 5        // red
            riskGlow = "rgba(255,80,50,0.35)"
        case "medium":
            riskHue = 35       // amber
            riskGlow = "rgba(255,165,25,0.3)"
        default:
            riskHue = 210      // cool blue
            riskGlow = "rgba(80,170,255,0.25)"
        }

        let confidenceGlow: String
        if confidence > 0.7 {
            confidenceGlow = "rgba(100,80,255,0.3)"   // violet
        } else if confidence > 0.4 {
            confidenceGlow = "rgba(80,150,255,0.25)"   // calm blue
        } else {
            confidenceGlow = "rgba(255,180,50,0.35)"   // amber warning
        }

        let injected = """
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:;">
        <style>
        :root {
            --agi-confidence: \(String(format: "%.2f", confidence));
            --agi-risk-hue: \(riskHue);
            --agi-risk-glow: \(riskGlow);
            --agi-confidence-glow: \(confidenceGlow);
            --agi-accent: hsl(\(riskHue), 75%, 55%);
        }
        html, body {
            margin: 0; padding: 0;
            padding-top: 44px !important;
            background: transparent !important;
            background-color: transparent !important;
            width: 100%;
            min-height: 100%;
            box-sizing: border-box;
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 16px;
            color: #fff;
            -webkit-text-size-adjust: 100%;
        }
        </style>
        \(bridgeScript(goal: goal))
        """

        if let headRange = html.range(of: "<head>", options: .caseInsensitive) {
            var modified = html
            modified.insert(contentsOf: injected, at: headRange.upperBound)
            return modified
        } else if let htmlRange = html.range(of: "<html", options: .caseInsensitive) {
            if let closeRange = html[htmlRange.upperBound...].range(of: ">") {
                var modified = html
                modified.insert(contentsOf: "<head>\(injected)</head>", at: closeRange.upperBound)
                return modified
            }
        }
        return injected + html
    }

    private static func jsStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "'\(escaped)'"
    }

    private static func bridgeScript(goal: String) -> String {
        let goalLiteral = jsStringLiteral(goal)
        return """
        <script>
        (function() {
            'use strict';
            if (window.AGI) { return; }

            var pending = {};

            function post(payload) {
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.artifact) {
                        window.webkit.messageHandlers.artifact.postMessage(payload);
                    }
                } catch (e) {}
            }

            window.__agiReceive = function(payload) {
                try {
                    if (typeof payload === 'string') {
                        payload = JSON.parse(payload);
                    }
                    if (!payload || !payload.requestId) return;

                    var callbacks = pending[payload.requestId];
                    if (!callbacks) return;
                    delete pending[payload.requestId];

                    if (payload.ok) {
                        callbacks.resolve(payload.imageUrl || payload.dataUrl || payload);
                    } else {
                        callbacks.reject(new Error(payload.error || 'Native request failed'));
                    }
                } catch (e) {}
            };

            function call(action, data) {
                var payload = Object.assign({ action: action }, data || {});
                post(payload);
            }

            window.AGI = {
                goal: \(goalLiteral),
                confidence: parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--agi-confidence')) || 0.5,
                riskLevel: (function() { var h = parseInt(getComputedStyle(document.documentElement).getPropertyValue('--agi-risk-hue')); return h <= 10 ? 'high' : h <= 40 ? 'medium' : 'low'; })(),
                haptic: function(style) {
                    call('haptic', { style: style || 'light' });
                },
                sound: function(kind) {
                    call('sound', { kind: kind || 'tap' });
                },
                speak: function(text) {
                    call('speak', { text: text || '' });
                },
                stopSpeak: function() {
                    call('stopSpeak', {});
                },
                copy: function(text) {
                    call('copy', { text: text || '' });
                },
                openURL: function(url) {
                    call('openURL', { url: url || '' });
                },
                done: function(stepId) {
                    call('done', { stepId: stepId || 'all' });
                },
                failed: function(stepId, reason) {
                    call('failed', { stepId: stepId || '', reason: reason || '' });
                },
                why: function() {
                    call('why', {});
                },
                reply: function(text) {
                    call('reply', { text: text || '' });
                },
                generateImage: function(prompt, options) {
                    options = options || {};
                    var requestId = 'agi_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 8);
                    return new Promise(function(resolve, reject) {
                        pending[requestId] = { resolve: resolve, reject: reject };
                        call('generateImage', {
                            requestId: requestId,
                            prompt: prompt || window.AGI.goal || 'Futuristic UI concept',
                            size: options.size || '512x512',
                            quality: options.quality || 'low'
                        });
                        setTimeout(function() {
                            if (pending[requestId]) {
                                delete pending[requestId];
                                reject(new Error('Image generation timeout'));
                            }
                        }, 30000);
                    });
                }
            };

            // Error handler: silently suppress JS errors from generated content.
            // Only show error UI if the page has no visible content at all.
            var _agiErrorCount = 0;
            window.onerror = function(msg, url, line, col, error) {
                _agiErrorCount++;
                console.error('AGI Artifact Error:', msg, 'at line', line);
                // Only show error overlay if there's nothing visible on page (blank screen prevention)
                if (_agiErrorCount >= 3 && document.body && document.body.innerText.trim().length < 10) {
                    var errorDiv = document.createElement('div');
                    errorDiv.style.cssText = 'position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);background:rgba(255,50,50,0.15);backdrop-filter:blur(16px);border:1px solid rgba(255,100,100,0.3);border-radius:16px;padding:20px;color:#fff;font-family:-apple-system,sans-serif;text-align:center;max-width:280px;z-index:9999';
                    errorDiv.innerHTML = '<div style="font-size:24px;margin-bottom:8px">⚠️</div><div style="font-weight:700;margin-bottom:6px">Artifact Error</div><div style="font-size:12px;color:rgba(255,255,255,0.7)">Try a different prompt.</div>';
                    document.body.appendChild(errorDiv);
                }
                return true;
            };

            // Unhandled promise rejection handler — suppress silently
            window.onunhandledrejection = function(event) {
                console.error('AGI Unhandled Promise:', event.reason);
                event.preventDefault();
            };

            document.addEventListener('click', function(event) {
                var target = event.target && event.target.closest('button,a,[role="button"],[data-agi-action]');
                if (!target) return;
                window.AGI.haptic('light');
            }, true);
        })();
        </script>
        """
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: ArtifactWebView
        weak var webView: WKWebView?
        var lastHTML: String?
        var lastGoal: String?
        private let speechSynth = AVSpeechSynthesizer()
        private var imageRequestInFlight = false
        private var lastImageRequestAt = Date.distantPast

        init(parent: ArtifactWebView) {
            self.parent = parent
            super.init()
        }

        func stopSpeaking() {
            Task { @MainActor in
                if speechSynth.isSpeaking {
                    speechSynth.stopSpeaking(at: .immediate)
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "artifact",
                  let payload = parsePayload(message.body),
                  let action = payload["action"] as? String else {
                return
            }

            switch action {
            case "haptic":
                triggerHaptic(style: payload["style"] as? String ?? "light")
            case "sound":
                playSound(kind: payload["kind"] as? String ?? "tap")
            case "speak":
                speak(text: payload["text"] as? String ?? parent.goal)
            case "stopSpeak":
                stopSpeaking()
            case "copy":
                copy(text: payload["text"] as? String ?? "")
            case "openURL":
                openURL(string: payload["url"] as? String ?? "")
            case "done":
                let stepId = payload["stepId"] as? String ?? "all"
                Task { @MainActor in
                    if stepId == "all" {
                        parent.onAction?(.allDone)
                    } else {
                        parent.onAction?(.stepDone(stepId))
                    }
                }
            case "failed":
                let stepId = payload["stepId"] as? String ?? ""
                let reason = payload["reason"] as? String ?? ""
                Task { @MainActor in
                    parent.onAction?(.stepFailed(stepId, reason))
                }
            case "why":
                Task { @MainActor in
                    parent.onAction?(.whyTapped)
                }
            case "reply":
                let text = payload["text"] as? String ?? ""
                if !text.isEmpty {
                    Task { @MainActor in
                        parent.onAction?(.dialogueReply(text))
                    }
                }
            case "generateImage":
                Task { @MainActor in
                    generateImage(with: payload)
                }
            default:
                break
            }
        }

        private func parsePayload(_ body: Any) -> [String: Any]? {
            if let dict = body as? [String: Any] { return dict }
            if let text = body as? String,
               let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
            return nil
        }

        private func triggerHaptic(style: String) {
            Task { @MainActor in
                switch style {
                case "selection":
                    UISelectionFeedbackGenerator().selectionChanged()
                case "medium":
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                case "heavy":
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                case "success":
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                case "warning":
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                case "error":
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                default:
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }

        private func playSound(kind: String) {
            switch kind {
            case "success":
                SoundManager.shared.play(.successChime, volume: 0.3)
            case "failure", "warning":
                SoundManager.shared.play(.errorSound, volume: 0.2)
            default:
                SoundManager.shared.play(.thinkingTick, volume: 0.2)
            }
        }

        private func speak(text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            Task { @MainActor in
                speechSynth.stopSpeaking(at: .immediate)
                let utterance = AVSpeechUtterance(string: trimmed)
                utterance.rate = 0.48
                speechSynth.speak(utterance)
            }
        }

        private func copy(text: String) {
            guard !text.isEmpty else { return }
            Task { @MainActor in
                UIPasteboard.general.string = text
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }

        private func openURL(string: String) {
            guard let url = URL(string: string),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" else {
                return
            }

            Task { @MainActor in
                UIApplication.shared.open(url)
            }
        }

        @MainActor
        private func generateImage(with payload: [String: Any]) {
            guard let requestId = payload["requestId"] as? String, !requestId.isEmpty else { return }
            let prompt = (payload["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedPrompt = (prompt?.isEmpty == false ? prompt! : parent.goal)
            let size = (payload["size"] as? String) ?? "512x512"
            let quality = (payload["quality"] as? String) ?? "low"
            let now = Date()

            if imageRequestInFlight {
                sendBridgeResponse(
                    requestId: requestId,
                    ok: false,
                    imageURL: nil,
                    error: "Image generation already in progress"
                )
                return
            }
            if now.timeIntervalSince(lastImageRequestAt) < 0.9 {
                sendBridgeResponse(
                    requestId: requestId,
                    ok: false,
                    imageURL: nil,
                    error: "Image generation throttled"
                )
                return
            }

            imageRequestInFlight = true
            lastImageRequestAt = now

            Task {
                do {
                    let imageURL = try await MistralAPI.shared.generateArtifactImage(
                        prompt: resolvedPrompt,
                        size: size,
                        quality: quality
                    )
                    await MainActor.run {
                        self.imageRequestInFlight = false
                        self.sendBridgeResponse(requestId: requestId, ok: true, imageURL: imageURL, error: nil)
                    }
                } catch {
                    await MainActor.run {
                        self.imageRequestInFlight = false
                        self.sendBridgeResponse(requestId: requestId, ok: false, imageURL: nil, error: error.localizedDescription)
                    }
                }
            }
        }

        // Handle WKWebView process termination (prevents white screen)
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            print("[ArtifactWebView] Web content process terminated — reloading with fallback")
            let fallback = ArtifactWebView.safetyFallbackHTML(goal: parent.goal, reason: "render process crashed")
            webView.loadHTMLString(ArtifactWebView.wrapHTML(fallback, goal: parent.goal, confidence: parent.confidence, riskLevel: parent.riskLevel), baseURL: nil)
        }

        // Block navigation to external URLs — only allow about:blank and data:
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let scheme = url.scheme?.lowercased() ?? ""
                if scheme == "about" || scheme == "data" || navigationAction.navigationType == .other {
                    decisionHandler(.allow)
                    return
                }
            }
            decisionHandler(.cancel)
        }

        @MainActor
        private func sendBridgeResponse(requestId: String, ok: Bool, imageURL: String?, error: String?) {
            guard let webView else { return }
            var payload: [String: Any] = [
                "requestId": requestId,
                "ok": ok
            ]
            if let imageURL { payload["imageUrl"] = imageURL }
            if let error { payload["error"] = error }

            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let jsonString = String(data: data, encoding: .utf8) else {
                return
            }

            webView.evaluateJavaScript("window.__agiReceive && window.__agiReceive(\(jsonString));")
        }
    }
}
