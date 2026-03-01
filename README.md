<p align="center">
  <img src="logo.png" width="128" height="128" alt="AGI Logo">
</p>

<h1 align="center">AGI: Agentic Generative Interface</h1>

<p align="center">
  A native iOS app that turns your phone camera into a literary AI companion.<br>
  Point at any object — an AI narrator with a Disco Elysium-inspired personality observes, comments,<br>
  and generates interactive HTML artifacts overlaid on your camera feed.
</p>

<p align="center">
  Built for the <strong>Mistral Worldwide Hackathon</strong> (Feb 28 – Mar 1, 2026, Tokyo, API track) by Bektur's AGI team. 24-hour build.
</p>

## What It Does

**Three interaction modes on a live camera feed:**

1. **Companion Mode** — A literary narrator AI watches through your camera in real-time. Every 6 seconds it analyzes the frame via Mistral vision API and decides whether to speak. When it does, it drops a color-coded chat bubble with a vivid micro-narrative plus creative, scene-specific suggestion chips. Tap anywhere on the camera feed to force a fresh observation.

2. **Generative UI Artifacts** — Tapping a chip generates a full interactive HTML artifact overlaid on the camera: collectible trading cards, spec sheets, narrative cards, comparison charts, visual maps, timelines, RPG bestiary entries, or inner-voice dialogues with objects. Each artifact is a self-contained HTML/CSS/JS page rendered in a WKWebView with a native JS bridge. Every object you point at becomes a unique collectible worth exploring. Artifacts can be saved as **reusable skills** — saved artifacts resurface as suggestion chips in future sessions, rendering instantly with zero API calls.

3. **Voice Narration** — ElevenLabs TTS narrates every observation with stat-specific voice parameters (dreamy/slow for Inland Empire, fast/precise for Encyclopedia). Skill tags are stripped from narration so TTS reads only the prose. BGM automatically ducks during narration and restores afterward.

## The Disco Elysium Flavor

The companion has **8 perception stats** inspired by Disco Elysium's skill system:

| Stat | Effect When Dominant (level 4+) |
|---|---|
| Inland Empire | Projects inner life onto objects, personifies the inanimate |
| Encyclopedia | Drops specs, patents, model numbers, manufacturing dates |
| Empathy | Reads human traces — wear patterns, usage habits, emotional residue |
| Visual Calculus | Analyzes spatial relationships, angles, layouts, ergonomics |
| Electrochemistry | Drawn to textures, colors, sensory details, material qualities |
| Rhetoric | Argues both sides, plays devil's advocate, multiple interpretations |
| Shivers | Senses broader context — neighborhood, time of day, what's beyond the frame |
| Conceptualization | Sees everything as art and design, critiques composition |

**Key mechanics:**
- **Inner voice interjections** — Messages color-coded by the speaking stat (purple for Inland Empire, cyan for Encyclopedia, etc.) with colored border and tinted text
- **Skill check badges** on chips with pass/fail rolls and modifier breakdowns
- **Stat conflicts** — When two stats are both high, they argue about the same object with competing interpretations
- **Environmental auto-leveling** — See text → Encyclopedia grows. See art → Conceptualization grows.
- **Stat-specific voice profiles** — Each stat has unique ElevenLabs TTS parameters
- **Clean TTS** — Skill bracket tags stripped from narration so voice reads only the literary prose

## Three Companion Modes

1. **Literary** (default) — Full Disco Elysium narrator with inner voices, skill checks, and poetic observations
2. **Practical** — Direct, factual assistant. No metaphors, just useful information and actionable chips
3. **Accessibility** — Spatial description mode for visually impaired users. Clock-face positions, thorough element naming, auto-enabled TTS

## Architecture

```
Native iOS (Swift/SwiftUI, iOS 26.2)
├── Mistral API (direct URLSession, no backend)
│   ├── mistral-small-latest — vision analysis (companion observe + OCR)
│   ├── mistral-large-latest — artifact generation + deep dive with web_search tool
│   └── ministral-8b-latest — dialogue streaming
├── Structured Output — 8+ JSON schemas with strict mode
│   ├── companion_observation (11 fields incl. inner_voice, chip_checks)
│   ├── ocr_extraction (regions with text/translation/type/confidence)
│   ├── object_detection (bbox + notes + risk)
│   ├── artifact generation (self-contained HTML)
│   └── 4 more schemas (panel_analysis, suggestions, wizard, interview)
├── ElevenLabs TTS — Flash v2.5, HTTP streaming narration
│   ├── Stat-specific voice profiles (stability, speed, similarity per stat)
│   ├── BGM ducking during narration
│   └── Auto-speak first observation (voice-first demo opening)
├── Hybrid UI — Native SwiftUI overlays + WKWebView artifacts
│   ├── CSP security hardening (blocks external scripts/resources)
│   ├── Artifact safety gate (validates HTML before rendering, blocks dangerous patterns)
│   ├── Viewport + base CSS injection (prevents tiny/broken rendering)
│   ├── Graceful JS error handling (suppresses minor errors, only shows overlay on blank screen)
│   ├── WKWebView process crash recovery with auto-reload
│   ├── Navigation blocking (no external URL loads)
│   ├── Tap-to-observe (tap camera feed → instant fresh observation)
│   └── Swipe-to-dismiss gesture on artifact cards
├── JS Bridge — AGI.haptic(), AGI.sound(), AGI.speak(), AGI.reply()
├── Agent Swarm — 4 specialist Swift actors (detector, translator, wizard, evaluator)
│   ├── Parallel execution via TaskGroup
│   ├── PromptOptimizer — self-improving prompts (JSON persistence, scored by quality)
│   ├── KnowledgeBase — cumulative learning store (max 100 entries)
│   └── Agent Trace Overlay — real-time visualization of all API calls, latencies, models
├── Sound Design — 16 custom audio files (4 BGM loops + 11 SFX + narrator voice)
│   └── State-driven BGM that changes with app state
├── Saved Skills + Artifact Catalog
│   ├── Artifact catalog — 20 browsable artifact formats with emoji, description, one-tap generation
│   ├── SkillStore — JSON persistence (max 30 skills, scored relevance matching)
│   ├── Save artifacts as reusable skills (bookmark button on artifact overlay)
│   ├── Skill browser modal — catalog + saved skills, emoji icons, timestamps, swipe-to-delete
│   ├── Contextual recall — saved skills resurface as yellow chips when scene matches
│   ├── Scene-aware re-generation — recalling a skill on a new object re-generates it
│   └── Same-scene instant rendering — zero API calls when scene hasn't changed
├── Scene Intelligence
│   ├── Perceptual hash scene gating (8×8 grayscale → similarity threshold)
│   ├── Proactive policy engine (rate limiting, safety gating)
│   └── Scene session memory + conversation history management
├── Generative UI Formats — 17+ artifact types from a single prompt engine
│   ├── Collectible trading cards (rarity, stat bars, emoji visuals, flavor text)
│   ├── Inner-voice dialogues (branching conversation trees, 2-3 levels deep)
│   ├── Visual maps and CSS diagrams (spatial layouts, heatmaps)
│   ├── Spec sheets and identification cards
│   ├── Literary narrative cards and RPG bestiary entries
│   ├── Comparison charts with rating bars
│   ├── Timelines and history entries
│   ├── Quizzes and interactive flashcards
│   ├── Mood palettes and aesthetic analysis
│   ├── Reviews and roasts (star ratings, pros/cons, verdict)
│   ├── Tier lists (S/A/B/C/D ranking with justification)
│   ├── Blueprints and technical schematics
│   ├── VS battle cards (side-by-side stat comparison)
│   ├── Mini simulations (CSS animations, click-driven demos)
│   ├── Poems and haiku (formatted literary pieces)
│   ├── Recipes and ingredient breakdowns
│   └── Step-by-step visual guides
├── Dedicated Flows
│   ├── OCR Extraction — structured text reading with per-region translation
│   ├── Deep Dive — mistral-large + web_search tool for evidence-backed research
│   ├── Object Dialogue — inner-voice conversations with inanimate objects
│   └── Crowd Notes — live object detection with anchored label chips
├── Security & Reliability
│   ├── iOS Keychain storage for API keys
│   ├── Demo Mode — pre-baked cached responses for stage reliability
│   ├── Artifact fallback cache — serves last successful artifact on failure
│   ├── Artifact safety gate — blocks eval/fetch/external URLs/excessive size
│   ├── Sanitized share filenames (strips illegal filesystem characters)
│   └── WKWebView CSP + navigation lockdown + process crash recovery
├── Wellbeing Layer — Lens Ledger, Poetry Log, Mirror, Curiosity Catcher
│   └── Journal export (shareable text summary)
└── Character System
    ├── 8 perception stats with prompt injection + environmental auto-leveling
    ├── Stat conflict system — two high stats argue about the same object
    ├── Stat-colored message bubbles (each stat has a unique color)
    ├── Clean TTS narration — skill tags stripped, only prose is spoken
    ├── Stat-specific voice parameters for TTS
    ├── Onboarding interview (4-step user profiling)
    ├── Learning from user behavior (practical vs creative weight)
    ├── Character card with personality bio, AI system stats, session summary
    └── Haptic feedback throughout
```

## Setup

### Requirements

- Xcode 16+ with iOS 26.2 SDK
- iPhone with camera (or Simulator for UI testing)

### Build

```bash
cd agiagiagi
xcodebuild -scheme agiagiagi -destination 'generic/platform=iOS Simulator' build

# Or open in Xcode
open agiagiagi.xcodeproj
```

### API Keys

Configure in the app's Settings tab:

| Key | Source | Used For |
|-----|--------|----------|
| **Mistral API Key** | [console.mistral.ai](https://console.mistral.ai/) | Vision, artifacts, dialogue, OCR, deep dive + web search |
| **ElevenLabs API Key** | [elevenlabs.io](https://elevenlabs.io/) | Text-to-speech narration |

## Key Technical Decisions

- **Zero backend** — all API calls direct from device via URLSession
- **8+ structured JSON schemas** with strict mode for every Mistral call
- **Generative UI** — the AI writes entire HTML artifacts including interactive JS; 17+ formats (collectible cards, dialogues, maps, specs, narratives, comparisons, timelines, bestiary entries, quizzes, mood palettes, reviews, tier lists, blueprints, VS battles, simulations, poems, recipes)
- **Collectible card system** — each object becomes a trading card with rarity, stat bars, emoji visual, and flavor text
- **Mistral web_search tool** — Deep Dive uses tool calling for evidence-backed research
- **Artifact safety gate** — validates generated HTML before rendering, blocks dangerous patterns
- **Viewport injection** — forces proper mobile rendering scale on all generated artifacts
- **Graceful error handling** — JS errors suppressed silently; error overlay only on truly blank screens
- **Tap-to-observe** — tap the camera feed for an instant fresh observation (bypasses scene hash + cooldown)
- **Stat-colored bubbles** — inner voice messages tinted with the speaking stat's color
- **Clean TTS** — skill bracket tags stripped from narration so voice reads only prose
- **Perceptual hash scene detection** (8×8 grayscale average) prevents spam from camera shake
- **Three companion modes** with distinct system prompts from the same engine
- **iOS Keychain** for API key security, CSP headers for WebView security
- **Demo mode** with pre-baked responses guarantees smooth stage demo without network
- **Self-improving agent swarm** — agents evaluate each other, optimize prompts, build knowledge
- **Artifact catalog + saved skills** — 20 browsable artifact formats in a dedicated modal; any artifact can be bookmarked and recalled; recalling on a new object re-generates contextually

## Hackathon Context

- **Event:** Mistral Worldwide Hackathon, Tokyo 2026
- **Track:** API (Bektur's AGI team)
- **Target device:** iPhone Air
- **Prize targets:** ElevenLabs Best Voice, Mistral Best Vibe Coder, HuggingFace Best Agent Skills
- **Judging:** Technicity / Creativity / Usefulness / Demo Quality / Track Alignment (20% each)

## License

MIT License. See [LICENSE](LICENSE) for details.
