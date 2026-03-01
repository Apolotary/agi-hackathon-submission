//
//  DemoModeCache.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation

struct DemoModeCache {
    static let shared = DemoModeCache()

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "demo_mode")
    }

    // Pre-baked companion observations for demo reliability
    private let observations: [MistralAPI.CompanionObservation] = [
        MistralAPI.CompanionObservation(
            shouldSpeak: true,
            sceneDescription: "Mechanical keyboard on desk",
            message: "That keyboard has seen things. The shine on WASD tells a story the owner won't — late nights, missed deadlines, and one legendary clutch in overtime.",
            chips: ["Talk to this object", "Show specs chart", "Narrate its story", "Rate this setup"],
            qualityConfidence: 0.85,
            safetyConfidence: 0.95,
            riskLevel: "low",
            innerVoiceStat: "inland_empire",
            innerVoiceDifficulty: "medium",
            chipChecks: [MistralAPI.ChipCheckDTO(chipIndex: 0, stat: "inland_empire", difficulty: "medium", chance: 62)]
        ),
        MistralAPI.CompanionObservation(
            shouldSpeak: true,
            sceneDescription: "Coffee mug on table",
            message: "A mug that refuses to be washed. The ring stain inside is a geological record — each layer a different brew, a different morning, a different version of you.",
            chips: ["Talk to this object", "Build a lore card", "Identify the maker", "What should I make?"],
            qualityConfidence: 0.78,
            safetyConfidence: 1.0,
            riskLevel: "low",
            innerVoiceStat: "empathy",
            innerVoiceDifficulty: "easy",
            chipChecks: []
        ),
        MistralAPI.CompanionObservation(
            shouldSpeak: true,
            sceneDescription: "Japanese text on panel",
            message: "Japanese characters arranged with the precision of someone who takes signage personally. The typography choice alone tells you this building has standards.",
            chips: ["Translate that text", "Talk to this object", "Create visual guide", "Narrate its story"],
            qualityConfidence: 0.82,
            safetyConfidence: 0.9,
            riskLevel: "low",
            innerVoiceStat: "encyclopedia",
            innerVoiceDifficulty: "trivial",
            chipChecks: [MistralAPI.ChipCheckDTO(chipIndex: 0, stat: "encyclopedia", difficulty: "trivial", chance: 88)]
        )
    ]

    private var observationIndex = 0

    mutating func nextObservation() -> MistralAPI.CompanionObservation {
        let obs = observations[observationIndex % observations.count]
        observationIndex += 1
        return obs
    }

    // Pre-baked artifact HTML for demo reliability
    func fallbackArtifact(goal: String) -> String {
        let lower = goal.lowercased()
        if lower.contains("talk") || lower.contains("dialogue") || lower.contains("conversation") {
            return dialogueArtifact
        } else if lower.contains("spec") || lower.contains("identify") || lower.contains("model") {
            return specSheetArtifact
        } else if lower.contains("story") || lower.contains("narrate") || lower.contains("lore") {
            return narrativeArtifact
        }
        return narrativeArtifact
    }

    private var dialogueArtifact: String {
        """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>*{margin:0;box-sizing:border-box}body{font-family:-apple-system,sans-serif;color:#fff;background:transparent;padding:16px}
        .card{background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.18);backdrop-filter:blur(20px);border-radius:16px;padding:18px;max-width:340px;margin:0 auto}
        h2{font-size:17px;margin-bottom:12px;color:#c4b5fd}.stat{font-size:11px;color:#a78bfa;font-style:italic;margin-bottom:10px}
        p{font-size:14px;line-height:1.5;margin-bottom:14px;color:rgba(255,255,255,.85)}
        .material{border-left:2px solid #60a5fa;padding-left:10px;margin-bottom:12px;font-size:13px;color:rgba(255,255,255,.7)}
        button{display:block;width:100%;padding:12px;margin:6px 0;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.15);border-radius:10px;color:#fff;font-size:14px;cursor:pointer;text-align:left}
        button:active{background:rgba(255,255,255,.15)}.hidden{display:none}
        </style></head><body><div class="card">
        <div class="stat">[INLAND EMPIRE — Medium: 4]</div>
        <h2>Inner Voice Dialogue</h2>
        <div class="material">A well-used object. The wear patterns speak of routine, of comfort, of someone who has made peace with their choices.</div>
        <p>It doesn't judge you. It never has. Every scratch is a conversation you've already forgotten, but it remembers.</p>
        <div id="opts1">
        <button onclick="this.parentElement.classList.add('hidden');document.getElementById('r1').classList.remove('hidden');AGI.haptic('light');AGI.reply('What does it remember?')">What does it remember?</button>
        <button onclick="this.parentElement.classList.add('hidden');document.getElementById('r2').classList.remove('hidden');AGI.haptic('light');AGI.reply('That sounds like projection')">That sounds like projection</button>
        </div>
        <div id="r1" class="hidden"><p><em>[EMPATHY]</em> The weight of your hand. The temperature of the room at 2 AM. The particular silence that follows a decision.</p>
        <button onclick="this.parentElement.classList.add('hidden');document.getElementById('r3').classList.remove('hidden');AGI.haptic('light');AGI.reply('Go deeper')">Go deeper</button></div>
        <div id="r2" class="hidden"><p><em>[RHETORIC]</em> Is it projection? Or is noticing the same as caring? You looked at this object. That's already a relationship.</p>
        <button onclick="this.parentElement.classList.add('hidden');document.getElementById('r3').classList.remove('hidden');AGI.haptic('light');AGI.reply('Fair point')">Fair point</button></div>
        <div id="r3" class="hidden"><p><em>[SHIVERS]</em> Somewhere in this room, right now, dust is settling on something you haven't looked at in months. It's still waiting.</p></div>
        </div></body></html>
        """
    }

    private var specSheetArtifact: String {
        """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>*{margin:0;box-sizing:border-box}body{font-family:-apple-system,sans-serif;color:#fff;background:transparent;padding:16px}
        .card{background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.18);backdrop-filter:blur(20px);border-radius:16px;padding:18px;max-width:340px;margin:0 auto}
        h2{font-size:17px;margin-bottom:4px}
        .sub{font-size:12px;color:rgba(255,255,255,.5);margin-bottom:14px}
        table{width:100%;border-collapse:collapse;margin:10px 0}
        td{padding:8px 6px;border-bottom:1px solid rgba(255,255,255,.1);font-size:13px}
        td:first-child{color:rgba(255,255,255,.5);width:40%}
        .badge{display:inline-block;padding:2px 8px;border-radius:6px;font-size:11px;font-weight:600}
        .green{background:rgba(34,197,94,.2);color:#22c55e}
        </style></head><body><div class="card">
        <h2>Object Identification</h2>
        <div class="sub">Detected via Mistral Vision API</div>
        <table>
        <tr><td>Type</td><td>Consumer electronics</td></tr>
        <tr><td>Condition</td><td><span class="badge green">Good</span></td></tr>
        <tr><td>Confidence</td><td>85%</td></tr>
        <tr><td>Details</td><td>Well-maintained, regular use patterns visible</td></tr>
        </table>
        </div></body></html>
        """
    }

    private var narrativeArtifact: String {
        """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>*{margin:0;box-sizing:border-box}body{font-family:-apple-system,sans-serif;color:#fff;background:transparent;padding:16px}
        .card{background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.18);backdrop-filter:blur(20px);border-radius:16px;padding:18px;max-width:340px;margin:0 auto}
        h2{font-size:17px;margin-bottom:12px;color:#fbbf24}
        p{font-size:14px;line-height:1.6;margin-bottom:12px;color:rgba(255,255,255,.85)}
        .divider{height:1px;background:rgba(255,255,255,.1);margin:14px 0}
        .footer{font-size:11px;color:rgba(255,255,255,.4);font-style:italic}
        </style></head><body><div class="card">
        <h2>The Story of This Object</h2>
        <p>Every object in a room is a fossil of a decision. Someone chose this. Someone carried it home. Someone set it down right here, in this exact spot, and then forgot they'd made a choice at all.</p>
        <div class="divider"></div>
        <p>The wear pattern tells you everything: which side faces the light, which edge gets touched most often, where the dust collects undisturbed — a map of human attention rendered in fingerprints and fading.</p>
        <div class="divider"></div>
        <p class="footer">Narrated by your inner voices — Inland Empire, with support from Empathy</p>
        </div></body></html>
        """
    }
}
