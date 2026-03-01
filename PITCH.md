# AGI — Agentic Generative Interface

## Pitch

We wanted to imagine what agentic generative UI actually looks like when you take it off the screen and into the real world. So we built a game around it.

AGI is a native iOS app where you point your phone camera at any object and an AI companion — a literary narrator with a Disco Elysium-inspired personality — observes the scene, comments on it, and generates a disposable interactive interface on the fly. Not a pre-built screen. A full HTML/CSS/JS artifact — a collectible card, a spec sheet, a quiz, a tier list, a blueprint, a dialogue tree — rendered right on top of your camera feed. Every object becomes a unique encounter. Every interface is generated once, for this moment, for this thing.

By default, these artifacts are ephemeral. You see them, you interact, they're gone. But when one is useful or delightful, you save it. It becomes a **Skill** — a reusable mini-app in your personal Skillbook. Point the camera at a different object and recall a saved skill: AGI re-generates it for the new context, keeping the format but adapting the content. Over time, you and the AI co-create a personalized toolkit of micro-interfaces that help you in everyday life.

Meanwhile, your companion grows with you. It has 8 perception stats (Inland Empire, Encyclopedia, Empathy, Visual Calculus, Electrochemistry, Rhetoric, Shivers, Conceptualization) that level up based on what you scan and how you interact. A user who reads a lot of text levels up Encyclopedia; someone drawn to art grows Conceptualization. As stats rise, the companion's personality shifts — its observations change tone, its voice changes cadence, and when two stats compete, they argue about the same object. Your companion becomes a reflection of how you see the world.

The core thesis: **agentic AI should build things _for_ you, not just answer questions.** Through a game loop of explore → generate → save → recall, we turn generative UI from a tech demo into a personal tool that learns what interfaces you need and creates them on demand.

## Technical Stack

- **Mistral API** — three models, zero backend, all calls direct from device:
  - `mistral-small-latest` — vision analysis, companion observations, OCR, artifact generation
  - `mistral-large-latest` — deep dive research with `web_search` tool calling
  - `ministral-8b-latest` — streaming dialogue
  - 8+ JSON schemas with `response_format: json_schema` (strict mode) for deterministic structured output
- **ElevenLabs API** — `eleven_flash_v2_5` TTS with stat-specific voice profiles and BGM ducking
- **Native Swift/SwiftUI** — no React Native, no Flutter, no web wrapper
- **Self-improving agent swarm** — 4 specialist Swift actors (detector, translator, wizard, evaluator) with parallel execution, prompt optimization, and a cumulative knowledge base
- **WKWebView** with CSP hardening and a JS bridge (haptics, sound, speech, clipboard, image generation) for generated artifacts
- **17+ generative UI formats** from a single prompt engine — collectible cards, dialogues, visual maps, spec sheets, timelines, quizzes, tier lists, blueprints, VS battles, mini simulations, poems, recipes, and more
- **Saved Skills** — max 30 bookmarked artifacts with keyword relevance scoring, scene-aware re-generation, and zero-API-call instant recall when the scene hasn't changed
- **Perceptual hash scene gating**, iOS Keychain for API keys, demo mode with pre-baked responses for stage reliability

## What Makes It Different

1. **Generative UI in the real world** — the AI doesn't just describe what it sees, it builds an interface for it
2. **Disposable by default, saveable by choice** — every artifact is ephemeral until you decide it's worth keeping
3. **The companion grows** — 8 stats shape personality, voice, and observations based on your behavior
4. **A Skillbook, not a chat history** — you accumulate useful micro-apps, not a transcript
5. **Zero backend** — everything runs from the phone, API keys in Keychain, no server to maintain

## Hackathon Context

- **Event:** Mistral Worldwide Hackathon, Tokyo 2026 (Feb 28 – Mar 1)
- **Track:** API (Bektur's AGI team)
- **Build time:** 24 hours
