//
//  LiveCameraView.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import SwiftUI
import AVFoundation
import Combine

// MARK: - Camera Preview UIView (proper layer resizing)

class CameraPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        self.previewLayer = layer
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

// MARK: - Camera Preview Manager

class CameraPreviewManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.frame", qos: .userInteractive)
    private let ciContext = CIContext()

    @Published var lastFrame: UIImage?
    @Published var isRunning = false

    private var frameCounter = 0
    private var frameProcessingPaused = false

    override init() {
        super.init()
        configure()
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) { session.addInput(input) }

        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) { session.addOutput(output) }

        if let connection = output.connection(with: .video) {
            connection.videoRotationAngle = 90
        }

        session.commitConfiguration()
    }

    func start() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async { self?.isRunning = true }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
        DispatchQueue.main.async { self.isRunning = false }
    }

    func pauseFrameProcessing() {
        queue.async { self.frameProcessingPaused = true }
    }

    func resumeFrameProcessing() {
        queue.async { self.frameProcessingPaused = false }
    }

    func captureSnapshot() -> (image: UIImage, data: Data)? {
        guard let frame = lastFrame,
              let data = frame.jpegData(compressionQuality: 0.7) else { return nil }
        return (frame, data)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !frameProcessingPaused else { return }
        frameCounter += 1
        guard frameCounter % 10 == 0 else { return }

        autoreleasepool {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
            let uiImage = UIImage(cgImage: cgImage)

            DispatchQueue.main.async {
                self.lastFrame = uiImage
            }
        }
    }
}

// MARK: - UIViewRepresentable

struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        CameraPreviewUIView(session: session)
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

// MARK: - Live Camera View

struct LiveCameraView: View {
    @StateObject private var camera = CameraPreviewManager()

    // Runtime state machine
    @State private var runtimeState: AppRuntimeState = .idle

    // Companion state
    @State private var messages: [CompanionMessage] = []
    @State private var analysisTimer: Timer?
    @State private var lastSceneHash: [UInt8] = []
    @State private var lastAnalysisTime: Date = .distantPast
    @State private var lastSceneDescription: String = ""
    @State private var conversationHistory: [ChatMessage] = []
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    // Policy engine
    @State private var policyEngine = ProactivePolicyEngine()

    // Artifact state
    @State private var isGenerating = false
    @State private var artifactHTML: String?
    @State private var artifactGoal = ""
    @State private var showArtifact = false
    @State private var artifactDragOffset: CGFloat = 0

    // Scene session memory
    @State private var sceneSession = SceneSession()

    // Vibe metadata for theming (split confidence)
    @State private var currentQualityConfidence: Double = 0.5
    @State private var currentSafetyConfidence: Double = 0.8
    @State private var currentRiskLevel: String = "low"

    // Concurrency guards
    @State private var isAnalysisInFlight = false
    @State private var currentAnalysisTask: Task<Void, Never>?
    @State private var currentGenerationTask: Task<Void, Never>?

    // Crowd Notes mode
    @State private var crowdNotesMode = false
    @State private var crowdNotes: [CrowdNote] = []
    @State private var crowdNotesTimer: Timer?
    @State private var isDetectionInFlight = false
    @State private var nextTrackId = 1
    @State private var selectedNoteId: UUID?

    // World object labels (shared with crowd notes, runs in background in main mode)
    @State private var worldObjectTimer: Timer?

    // Error
    @State private var errorMessage: String?
    @State private var showError = false

    // Settings-driven pauses
    @AppStorage("sensing_paused") private var sensingPaused = false
    @AppStorage("proactive_prompts_paused") private var proactivePromptsPaused = false

    // TTS narration
    @State private var ttsEnabled = false
    @State private var ttsTask: Task<Void, Never>?

    // Companion mode (literary vs practical)
    @State private var companionMode: CompanionMode = .literary

    // Artifact cache (goal → HTML)
    @State private var artifactCache: [String: String] = [:]

    // Voice-first opening: auto-speak the first observation
    @State private var isFirstObservation = true
    @AppStorage("demo_mode") private var demoMode = false

    // Tap-to-observe: force a new observation ignoring scene hash
    @State private var forceNextObservation = false

    // Saved skills browser
    @State private var showSkillBrowser = false

    // Companion config
    private let analysisInterval: TimeInterval = 6.0
    private let maxMessages = 50
    private let maxHistoryForAPI = 8

    var body: some View {
        ZStack {
            // Layer 1: Full-screen live camera (tap to trigger fresh observation)
            CameraPreviewRepresentable(session: camera.session)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isGenerating && !showArtifact && runtimeState != .paused else { return }
                    forceNextObservation = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    // Only fire immediately if no analysis is already in flight
                    // (otherwise the force flag will be picked up by the next timer tick)
                    if !isAnalysisInFlight {
                        currentAnalysisTask = Task {
                            await companionTick()
                        }
                    }
                }

            // Layer 2: Bottom gradient scrim (adaptive to screen height)
            GeometryReader { scrimProxy in
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: showArtifact
                            ? [.clear, .black.opacity(0.3), .black.opacity(0.5)]
                            : [.clear, .black.opacity(0.5), .black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: showArtifact ? scrimProxy.size.height : scrimProxy.size.height * 0.45)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Layer 3: Artifact overlay
            if showArtifact, let html = artifactHTML {
                artifactOverlay(html: html)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Layer 4: Crowd Notes anchored chips (when in crowd notes mode)
            if crowdNotesMode && !showArtifact {
                crowdNotesOverlay
            }

            // Layer 4a: World object labels in companion mode (tappable → feeds into conversation)
            if !crowdNotesMode && !showArtifact && !crowdNotes.isEmpty && runtimeState != .paused {
                worldObjectLabels
            }

            // Layer 4b: Chat bubbles + chips + input (companion mode, hidden when artifact showing or paused)
            if !crowdNotesMode && !showArtifact && runtimeState != .paused {
                VStack(spacing: 0) {
                    Spacer()
                    chatBubbleList
                    chipBar
                    inputBar
                }
            } else if runtimeState == .paused && !showArtifact {
                VStack {
                    Spacer()
                    Text("Companion paused")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 80)
                        .safeAreaPadding(.bottom)
                }
            }

            // Layer 5: Top bar — companion orb (left) + controls (right)
            VStack {
                HStack(alignment: .top) {
                    companionOrb
                        .padding(.leading, 20)

                    Spacer()

                    // Mode toggle + Pause / Kill switch
                    HStack(spacing: 12) {
                        // Companion mode toggle (literary / practical / accessibility)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                companionMode = companionMode.next
                            }
                            SoundManager.shared.play(.modeSwitch, volume: 0.2)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            // Auto-enable TTS in accessibility mode
                            if companionMode == .accessibility && !ttsEnabled {
                                ttsEnabled = true
                            }
                        } label: {
                            Image(systemName: companionMode.icon)
                                .font(.title2)
                                .foregroundStyle(companionMode == .literary ? .white.opacity(0.6) : (companionMode == .practical ? .orange : .blue))
                        }

                        // TTS narration toggle
                        Button {
                            ttsEnabled.toggle()
                            SoundManager.shared.play(.modeSwitch, volume: 0.2)
                            if !ttsEnabled {
                                ttsTask?.cancel()
                                ElevenLabsTTS.shared.stop()
                            }
                        } label: {
                            Image(systemName: ttsEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.title2)
                                .foregroundStyle(ttsEnabled ? vibeGlowColor : .white.opacity(0.6))
                        }

                        // Saved skills browser
                        Button {
                            showSkillBrowser = true
                            SoundManager.shared.play(.modeSwitch, volume: 0.2)
                        } label: {
                            Image(systemName: SkillStore.shared.skills.isEmpty ? "bookmark.circle" : "bookmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(SkillStore.shared.skills.isEmpty ? .white.opacity(0.6) : .yellow)
                        }

                        // Crowd Notes toggle
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                crowdNotesMode.toggle()
                            }
                            SoundManager.shared.play(.modeSwitch)
                            if crowdNotesMode {
                                startCrowdNotesTimer()
                            } else {
                                stopCrowdNotesTimer()
                                crowdNotes.removeAll()
                                selectedNoteId = nil
                            }
                        } label: {
                            Image(systemName: crowdNotesMode ? "mappin.circle.fill" : "mappin.circle")
                                .font(.title2)
                                .foregroundStyle(crowdNotesMode ? vibeGlowColor : .white.opacity(0.6))
                        }

                        if runtimeState == .paused {
                            Button {
                                transitionTo(.cameraActive)
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        } else {
                            Button {
                                transitionTo(.paused)
                            } label: {
                                Image(systemName: "pause.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding(.trailing, 20)
                }
                .padding(.top, 8)
                Spacer()
            }

            // Layer 6: Agent trace overlay (toggle via double-tap on orb or state)
            if AgentTraceCollector.shared.isVisible {
                agentTraceOverlay
                    .transition(.opacity)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .sheet(isPresented: $showSkillBrowser) {
            skillBrowserSheet
        }
        .onAppear {
            camera.start()
            transitionTo(.cameraActive)
            startCompanionTimer()
            startWorldObjectTimer()
            TelemetryCollector.shared.recordSessionStart()
            SoundManager.shared.playBGM(.idle)
        }
        .onDisappear {
            camera.stop()
            stopCompanionTimer()
            stopCrowdNotesTimer()
            stopWorldObjectTimer()
            currentGenerationTask?.cancel()
            currentGenerationTask = nil
            ttsTask?.cancel()
            ElevenLabsTTS.shared.stop()
            SoundManager.shared.stopBGM()
            transitionTo(.idle)
        }
    }

    // MARK: - Companion Orb

    private var companionOrb: some View {
        HStack(spacing: 8) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(vibeGlowColor.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .blur(radius: 6)

                // Inner orb
                Circle()
                    .fill(runtimeState == .paused ? .gray : vibeGlowColor)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .opacity(orbOpacity)
            .scaleEffect(orbScale)
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: runtimeState)

            Text(isOffline ? "Offline" : (crowdNotesMode ? "Crowd Notes" : (companionMode != .literary ? companionMode.displayName : runtimeState.displayLabel)))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(isOffline ? .orange.opacity(0.7) : .white.opacity(0.5))
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: runtimeState)
        }
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                AgentTraceCollector.shared.isVisible.toggle()
            }
            SoundManager.shared.play(.thinkingTick, volume: 0.15)
        }
    }

    private var orbOpacity: Double {
        switch runtimeState {
        case .idle, .paused: return 0.5
        case .cameraActive, .learning: return 0.6
        case .perceiving: return 0.8
        case .prompting: return 0.9
        case .acting, .verifying: return 1.0
        case .errorSafe: return 0.7
        }
    }

    private var orbScale: Double {
        switch runtimeState {
        case .idle, .paused: return 0.85
        case .cameraActive: return 0.9
        case .perceiving: return 1.0
        case .prompting, .acting: return 1.05
        case .verifying: return 1.1
        case .learning, .errorSafe: return 0.95
        }
    }

    // MARK: - Agent Trace Overlay

    private var agentTraceOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.green)
                Text("Agent Trace")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
                Spacer()
                Text("\(AgentTraceCollector.shared.totalAPICalls) calls")
                    .font(.caption2)
                    .foregroundStyle(.green.opacity(0.6))
                // JSON toggle
                Button {
                    withAnimation { AgentTraceCollector.shared.showJSON.toggle() }
                } label: {
                    Text("{}")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(AgentTraceCollector.shared.showJSON ? .green : .white.opacity(0.4))
                }
                Button {
                    withAnimation { AgentTraceCollector.shared.isVisible = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().background(.green.opacity(0.3))

            if AgentTraceCollector.shared.showJSON {
                // JSON schema view
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Structured Output Schema")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)

                        Text("Models: mistral-small (vision) → mistral-large (artifacts) → ministral-8b (dialogue)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))

                        if let json = AgentTraceCollector.shared.lastObservationJSON {
                            Text("Last Observation:")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                            Text(json.prefix(500))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        Text("response_format: { type: \"json_schema\", strict: true }")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.7))

                        Text("Every API call enforces strict JSON schema validation")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 200)
            } else {
                // Events list
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(AgentTraceCollector.shared.events.suffix(15).reversed()) { event in
                            traceEventRow(event)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.green.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 60)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func traceEventRow(_ event: TraceEvent) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(traceStatusColor(event.status))
                .frame(width: 6, height: 6)

            Text(event.agent)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)
                .frame(width: 52, alignment: .leading)

            Text(event.action.replacingOccurrences(of: "companion", with: "").prefix(12))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 70, alignment: .leading)

            if let ms = event.durationMs {
                Text("\(ms)ms")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ms > 3000 ? .orange : .green.opacity(0.8))
                    .frame(width: 48, alignment: .trailing)
            } else {
                Text("...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.yellow)
                    .frame(width: 48, alignment: .trailing)
            }

            Text(event.detail.prefix(20))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private func traceStatusColor(_ status: TraceEvent.TraceStatus) -> Color {
        switch status {
        case .started: return .yellow
        case .completed: return .green
        case .failed: return .red
        }
    }

    // MARK: - Chat Bubble List

    private var chatBubbleList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { msg in
                        bubbleView(for: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 280)
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 30)
                    Color.black
                }
            )
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bubbleView(for msg: CompanionMessage) -> some View {
        switch msg.role {
        case .companion:
            VStack(alignment: .leading, spacing: 6) {
                // Inner voice label (DE skill check style)
                if let voice = msg.innerVoice {
                    let color = statColor(voice.stat)
                    Text("[\(voice.stat.displayName.uppercased()) – \(voice.difficulty.displayName): \(UserProfile.load()?.statLevel(voice.stat) ?? 3)]")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .italic()
                        .foregroundStyle(color)
                        .tracking(0.3)
                }

                // Scene label (if different from previous)
                if !msg.sceneDescription.isEmpty && msg.innerVoice == nil {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(vibeColorFor(msg))
                            .frame(width: 5, height: 5)
                        Text(msg.sceneDescription)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.4))
                            .textCase(.uppercase)
                            .tracking(0.4)
                    }
                }

                Text(msg.cleanedContent)
                    .font(.subheadline)
                    .foregroundStyle(msg.innerVoice != nil ? statColor(msg.innerVoice!.stat).opacity(0.95) : .white.opacity(0.9))
                    .italic(msg.innerVoice != nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        (msg.innerVoice != nil ? statColor(msg.innerVoice!.stat) : vibeColorFor(msg)).opacity(0.4),
                        lineWidth: msg.innerVoice != nil ? 1.5 : 1
                    )
            )
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .leading)
            .contextMenu {
                Button {
                    withAnimation {
                        messages.removeAll { $0.id == msg.id }
                        conversationHistory = conversationHistory.filter { history in
                            if case .text(let text) = history.content {
                                return !text.contains(msg.content)
                            }
                            return true
                        }
                    }
                } label: {
                    Label("Forget this", systemImage: "trash")
                }
                Button {
                    savePoetryEntry(text: msg.content)
                } label: {
                    Label("Save text", systemImage: "doc.text")
                }
            }

        case .user:
            HStack {
                Spacer()
                Text(msg.content)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.white.opacity(0.18))
                    )
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .trailing)
            }

        case .system:
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    if runtimeState == .acting {
                        ProgressView()
                            .tint(.white.opacity(0.5))
                            .scaleEffect(0.7)
                    }
                    if msg.content.hasPrefix("[") && msg.content.hasSuffix("]") {
                        // Check result system message — colored
                        let isSuccess = msg.content.contains("Success")
                        Text(msg.content)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(isSuccess ? Color.green : Color.red)
                            .italic()
                    } else {
                        Text(msg.content)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.45))
                            .italic()
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Disco Elysium Stat Colors

    private func statColor(_ stat: CompanionStat) -> Color {
        switch stat {
        case .inlandEmpire: return Color(red: 0.6, green: 0.3, blue: 0.9)     // purple
        case .encyclopedia: return Color(red: 0.2, green: 0.8, blue: 0.9)     // cyan
        case .empathy: return Color(red: 0.95, green: 0.4, blue: 0.6)         // pink
        case .visualCalculus: return Color(red: 0.3, green: 0.9, blue: 0.5)   // green
        case .electrochemistry: return Color(red: 1.0, green: 0.6, blue: 0.2) // orange
        case .rhetoric: return Color(red: 0.9, green: 0.85, blue: 0.3)        // gold
        case .shivers: return Color(red: 0.4, green: 0.5, blue: 0.95)         // blue
        case .conceptualization: return Color(red: 0.85, green: 0.3, blue: 0.8) // magenta
        }
    }

    private func vibeColorFor(_ msg: CompanionMessage) -> Color {
        if msg.safetyConfidence < 0.4 {
            return Color(red: 1.0, green: 0.3, blue: 0.2) // red safety warning
        }
        if msg.qualityConfidence < 0.4 {
            return Color(red: 1.0, green: 0.7, blue: 0.2) // amber uncertainty
        }
        switch msg.riskLevel {
        case "high": return Color(red: 1.0, green: 0.3, blue: 0.2)
        case "medium": return Color(red: 1.0, green: 0.65, blue: 0.1)
        default: return Color(red: 0.3, green: 0.7, blue: 1.0)
        }
    }

    // MARK: - Chip Bar

    @ViewBuilder
    private var chipBar: some View {
        let lastCompanion = messages.last(where: { $0.role == .companion })
        let hasChips = lastCompanion != nil && !lastCompanion!.chips.isEmpty
        let savedSkills = SkillStore.shared.relevantSkills(for: lastSceneDescription, limit: 2)
        let hasContent = hasChips || !savedSkills.isEmpty

        if hasContent && !isGenerating {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Regular chips from companion
                    if let lastCompanion, !lastCompanion.chips.isEmpty {
                        ForEach(lastCompanion.chips, id: \.self) { chip in
                            let check = lastCompanion.chipChecks[chip]
                            Button {
                                handleChipTap(chip, check: check)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(chip)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.white)

                                    if let check {
                                        let color = statColor(check.stat)
                                        HStack(spacing: 2) {
                                            Image(systemName: check.chance >= 50 ? "checkmark.circle.fill" : "xmark.circle.fill")
                                                .font(.caption2)
                                            Text("\(check.chance)%")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                        }
                                        .foregroundStyle(color)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    Group {
                                        if let check {
                                            statColor(check.stat).opacity(0.15)
                                        } else {
                                            Color.white.opacity(0.14)
                                        }
                                    }
                                )
                                .clipShape(Capsule())
                                .overlay(
                                    Group {
                                        if let check {
                                            Capsule()
                                                .stroke(statColor(check.stat).opacity(0.5), lineWidth: 1)
                                        }
                                    }
                                )
                            }
                            .contextMenu {
                                if let check {
                                    let profile = UserProfile.load() ?? UserProfile()
                                    let breakdown = check.modifierBreakdown(statLevel: profile.statLevel(check.stat))
                                    ForEach(breakdown, id: \.0) { item in
                                        Text("\(item.0): \(item.1 >= 0 ? "+" : "")\(item.1)")
                                    }
                                }
                            }
                        }
                    }

                    // Saved skill chips
                    ForEach(savedSkills) { skill in
                        Button {
                            handleSkillRecall(skill)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "bookmark.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                                Text(skill.goal)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.yellow.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
                            )
                        }
                        .contextMenu {
                            Text("Saved \(skill.timestamp.formatted(.relative(presentation: .named)))")
                            Text("Used \(skill.useCount) times")
                            Button(role: .destructive) {
                                SkillStore.shared.removeById(skill.id)
                            } label: {
                                Label("Remove skill", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about what you see...", text: $inputText)
                .font(.subheadline)
                .foregroundStyle(.white)
                .tint(.white)
                .focused($isInputFocused)
                .onSubmit { submitInput() }

            Button {
                submitInput()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? .white.opacity(0.3) : .white
                    )
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.6))
    }

    // MARK: - Artifact Overlay

    private func artifactOverlay(html: String) -> some View {
        GeometryReader { proxy in
            let maxCardWidth = proxy.size.width - 24.0
            let maxCardHeight = min(
                proxy.size.height * 0.74,
                proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom - 120.0
            )

            ArtifactWebView(
                html: html,
                goal: artifactGoal,
                confidence: currentQualityConfidence,
                riskLevel: currentRiskLevel
            ) { action in
                handleArtifactAction(action)
            }
            .frame(width: maxCardWidth, height: maxCardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    // Save as skill button
                    Button {
                        saveArtifactAsSkill(html: html, goal: artifactGoal)
                    } label: {
                        Image(systemName: isSkillSaved(goal: artifactGoal) ? "bookmark.fill" : "bookmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(isSkillSaved(goal: artifactGoal) ? .yellow : .white)
                    }
                    .frame(width: 32, height: 32)

                    // Share button
                    Button {
                        shareArtifact(html: html, goal: artifactGoal)
                    } label: {
                        Image(systemName: "square.and.arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 32, height: 32)

                    // Close button
                    Button {
                        SoundManager.shared.play(.artifactClose, volume: 0.25)
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showArtifact = false
                            artifactHTML = nil
                            policyEngine.recordDismissal()
                            TelemetryCollector.shared.recordPromptDismissed()
                            transitionTo(.cameraActive)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 32, height: 32)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
            }
            .shadow(color: vibeGlowColor.opacity(0.2), radius: 20, x: 0, y: 0)
            .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
            .offset(y: artifactDragOffset)
            .opacity(1.0 - Double(abs(artifactDragOffset)) / 400.0)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            artifactDragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 120 {
                            SoundManager.shared.play(.artifactClose, volume: 0.25)
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showArtifact = false
                                artifactHTML = nil
                                artifactDragOffset = 0
                                policyEngine.recordDismissal()
                                TelemetryCollector.shared.recordPromptDismissed()
                                transitionTo(.cameraActive)
                            }
                        } else {
                            withAnimation(.spring(duration: 0.3)) {
                                artifactDragOffset = 0
                            }
                        }
                    }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Vibe Theming

    private var vibeGlowColor: Color {
        // Safety confidence drives the primary color when low
        if currentSafetyConfidence < 0.4 {
            return Color(red: 1.0, green: 0.3, blue: 0.2) // red warning
        }
        if currentQualityConfidence < 0.4 {
            return Color(red: 1.0, green: 0.7, blue: 0.2) // amber uncertainty
        }
        switch currentRiskLevel {
        case "high": return Color(red: 1.0, green: 0.3, blue: 0.2)
        case "medium": return Color(red: 1.0, green: 0.65, blue: 0.1)
        default: return Color(red: 0.3, green: 0.7, blue: 1.0)
        }
    }

    // MARK: - State Machine

    private func transitionTo(_ next: AppRuntimeState) {
        if let newState = runtimeState.transition(to: next) {
            let from = runtimeState
            withAnimation(.easeInOut(duration: 0.2)) {
                runtimeState = newState
            }
            TelemetryCollector.shared.recordStateTransition(from: from.rawValue, to: newState.rawValue)

            // BGM follows state
            SoundManager.shared.updateBGMForState(newState, isGenerating: isGenerating)

            // Side effects
            if newState == .paused {
                stopCompanionTimer()
                SoundManager.shared.stopBGM()
            } else if from == .paused && newState == .cameraActive {
                startCompanionTimer()
            }
        }
    }

    // MARK: - Companion Timer

    private func startCompanionTimer() {
        analysisTimer = Timer.scheduledTimer(
            withTimeInterval: analysisInterval,
            repeats: true
        ) { _ in
            Task { @MainActor in
                // Skip if analysis already in flight (don't cancel — it kills URLSession requests)
                guard !self.isAnalysisInFlight else { return }
                self.currentAnalysisTask = Task {
                    await self.companionTick()
                }
            }
        }
        // Also fire immediately after a short delay for first observation
        currentAnalysisTask = Task {
            try? await Task.sleep(for: .seconds(2))
            await companionTick()
        }
    }

    private func stopCompanionTimer() {
        analysisTimer?.invalidate()
        analysisTimer = nil
        currentAnalysisTask?.cancel()
        currentAnalysisTask = nil
    }

    // MARK: - Companion Tick (Periodic Analysis)

    private var isOffline: Bool {
        !MistralAPI.shared.hasAPIKey
    }

    private func companionTick() async {
        // Settings-driven pause
        guard !sensingPaused else { return }

        // Offline: show stale label, don't call API
        if isOffline {
            if messages.isEmpty {
                let offlineMsg = CompanionMessage.companion(
                    content: "I'm offline right now — add an API key in Settings to wake me up.",
                    chips: [],
                    qualityConfidence: 0.0,
                    safetyConfidence: 1.0,
                    riskLevel: "low",
                    sceneDescription: "Offline"
                )
                withAnimation { messages.append(offlineMsg) }
            }
            return
        }

        // Single-flight guard: skip if analysis already running
        guard !isAnalysisInFlight else { return }

        // State machine guards
        guard runtimeState == .cameraActive || runtimeState == .prompting else { return }
        guard !showArtifact else { return }
        guard !isGenerating else { return }

        // Scene change detection via rough image hash
        guard let snapshot = camera.captureSnapshot() else { return }
        let currentHash = Self.perceptualHash(snapshot.image)
        let timeSinceLast = Date().timeIntervalSince(lastAnalysisTime)

        // Skip if scene visually similar AND less than 30s since last analysis
        // (unless user tapped to force a fresh observation)
        let forced = forceNextObservation
        if forced { forceNextObservation = false }
        let similarity = Self.hashSimilarity(currentHash, lastSceneHash)
        if !forced && similarity > 0.85 && timeSinceLast < 30 {
            return
        }

        isAnalysisInFlight = true
        defer { isAnalysisInFlight = false }

        // Transition to perceiving
        transitionTo(.perceiving)

        do {
            // Check for cancellation before network call
            try Task.checkCancellation()

            let traceStart = Date()
            AgentTraceCollector.shared.log(agent: "Vision", model: "mistral-small", action: "companionObserve", status: .started, detail: "mode: \(companionMode.rawValue)")

            let observation: MistralAPI.CompanionObservation
            if demoMode {
                // Demo mode: use pre-baked responses with fake latency
                try await Task.sleep(for: .milliseconds(800))
                var cache = DemoModeCache.shared
                observation = cache.nextObservation()
                AgentTraceCollector.shared.log(agent: "Vision", model: "demo-cache", action: "companionObserve", status: .completed, durationMs: 800, detail: "[DEMO] \(observation.sceneDescription)")
            } else {
                let profile = UserProfile.load() ?? UserProfile()
                observation = try await MistralAPI.shared.companionObserve(
                    imageData: snapshot.data,
                    conversationHistory: Array(conversationHistory.suffix(maxHistoryForAPI)),
                    userProfile: profile,
                    mode: companionMode,
                    recentArtifactFormats: sceneSession.recentArtifactFormats
                )

                let traceDuration = Int(Date().timeIntervalSince(traceStart) * 1000)
                AgentTraceCollector.shared.log(agent: "Vision", model: "mistral-small", action: "companionObserve", status: .completed, durationMs: traceDuration, detail: observation.sceneDescription)
            }

            // Store raw JSON for debug overlay
            if let jsonData = try? JSONEncoder().encode(observation),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                AgentTraceCollector.shared.lastObservationJSON = jsonString
            }

            // Check cancellation after network call
            try Task.checkCancellation()

            lastSceneHash = currentHash
            lastAnalysisTime = Date()

            guard forced || observation.shouldSpeak else {
                transitionTo(.cameraActive)
                return
            }

            // Settings + policy engine gate (bypassed on forced tap)
            guard forced || (!proactivePromptsPaused &&
                  policyEngine.shouldPrompt(
                safetyConfidence: observation.safetyConfidence,
                riskLevel: observation.riskLevel
            )) else {
                transitionTo(.cameraActive)
                return
            }

            // Scene changed significantly — reset session AND conversation history
            if observation.sceneDescription != lastSceneDescription && !lastSceneDescription.isEmpty {
                sceneSession.reset()
                conversationHistory.removeAll()
                print("[Companion] Scene changed: '\(lastSceneDescription)' -> '\(observation.sceneDescription)' — history cleared")
            }
            lastSceneDescription = observation.sceneDescription

            // Parse inner voice label from observation
            var innerVoice: InnerVoiceLabel? = nil
            if !observation.innerVoiceStat.isEmpty,
               !observation.innerVoiceDifficulty.isEmpty,
               let stat = CompanionStat(rawValue: observation.innerVoiceStat),
               let diff = CheckDifficulty(rawValue: observation.innerVoiceDifficulty) {
                innerVoice = InnerVoiceLabel(stat: stat, difficulty: diff)
            }

            // Parse chip checks from observation
            var chipChecks: [String: SkillCheck] = [:]
            for dto in observation.chipChecks {
                if dto.chipIndex < observation.chips.count,
                   let stat = CompanionStat(rawValue: dto.stat),
                   let diff = CheckDifficulty(rawValue: dto.difficulty) {
                    let chipText = observation.chips[dto.chipIndex]
                    chipChecks[chipText] = SkillCheck(
                        stat: stat,
                        difficulty: diff,
                        chance: max(1, min(99, dto.chance))
                    )
                }
            }

            // Add companion message
            let msg = CompanionMessage.companion(
                content: observation.message,
                chips: observation.chips,
                qualityConfidence: observation.qualityConfidence,
                safetyConfidence: observation.safetyConfidence,
                riskLevel: observation.riskLevel,
                sceneDescription: observation.sceneDescription,
                innerVoice: innerVoice,
                chipChecks: chipChecks
            )
            withAnimation(.easeInOut(duration: 0.3)) {
                messages.append(msg)
                currentQualityConfidence = observation.qualityConfidence
                currentSafetyConfidence = observation.safetyConfidence
                currentRiskLevel = observation.riskLevel
            }
            SoundManager.shared.play(.bubbleAppear, volume: 0.2)

            // Stat progression: record inner voice stat observation
            if let voice = innerVoice {
                if let leveledUp = UserProfile.recordStatObservation(voice.stat, quality: observation.qualityConfidence) {
                    let levelUpMsg = CompanionMessage.system(
                        "[\(leveledUp.displayName.uppercased()) leveled up! → \((UserProfile.load() ?? UserProfile()).statLevel(leveledUp))]"
                    )
                    withAnimation(.easeInOut(duration: 0.3)) {
                        messages.append(levelUpMsg)
                    }
                    SoundManager.shared.play(.successChime, volume: 0.4)
                }
            }

            // Environmental stat boosting: scan scene for stat-relevant keywords
            let sceneText = (observation.sceneDescription + " " + observation.message).lowercased()
            for (stat, keywords) in Self.statEnvironmentKeywords {
                if keywords.contains(where: { sceneText.contains($0) }) {
                    if let leveledUp = UserProfile.recordStatObservation(stat, quality: 0.5) {
                        let envMsg = CompanionMessage.system(
                            "[\(leveledUp.displayName.uppercased()) leveled up! → \((UserProfile.load() ?? UserProfile()).statLevel(leveledUp))]"
                        )
                        withAnimation(.easeInOut(duration: 0.3)) {
                            messages.append(envMsg)
                        }
                        SoundManager.shared.play(.successChime, volume: 0.4)
                    }
                }
            }

            // Voice-first: auto-speak first observation even if TTS toggle is off
            if isFirstObservation && !ttsEnabled && !observation.message.isEmpty {
                isFirstObservation = false
                ttsEnabled = true  // auto-enable for immersive demo opening
            }
            isFirstObservation = false

            // TTS narration with stat-specific voice (strip skill tags so TTS reads only prose)
            if ttsEnabled && !observation.message.isEmpty {
                ttsTask?.cancel()
                let voiceProfile: StatVoiceProfile? = innerVoice.map { StatVoiceProfile.forStat($0.stat) }
                let statName = innerVoice?.stat.displayName ?? "default"
                let ttsText = Self.stripStatTags(observation.message)
                SoundManager.shared.play(.thinkingTick, volume: 0.15) // fill TTS latency gap
                ttsTask = Task {
                    AgentTraceCollector.shared.log(agent: "TTS", model: "eleven-flash-v2.5", action: "speak", status: .started, detail: "voice: \(statName)")
                    SoundManager.shared.duckForNarration()
                    let ttsStart = Date()
                    do {
                        try await ElevenLabsTTS.shared.speak(text: ttsText, voiceProfile: voiceProfile)
                        let ttsDuration = Int(Date().timeIntervalSince(ttsStart) * 1000)
                        AgentTraceCollector.shared.log(agent: "TTS", model: "eleven-flash-v2.5", action: "speak", status: .completed, durationMs: ttsDuration, detail: "voice: \(statName)")
                    } catch {
                        AgentTraceCollector.shared.log(agent: "TTS", model: "eleven-flash-v2.5", action: "speak", status: .failed, detail: String(describing: error).prefix(40).description)
                    }
                    SoundManager.shared.unduckAfterNarration()
                }
            }

            // Trim messages if too many
            if messages.count > maxMessages {
                messages.removeFirst(messages.count - maxMessages)
            }

            // Update conversation history for context
            conversationHistory.append(
                .assistant("[\(observation.sceneDescription)] \(observation.message)")
            )
            // Trim conversation history
            if conversationHistory.count > maxHistoryForAPI * 2 {
                conversationHistory = Array(conversationHistory.suffix(maxHistoryForAPI))
            }

            // Record telemetry
            policyEngine.recordPromptShown()
            TelemetryCollector.shared.recordPromptShown()

            // Wellbeing: auto-log lens entry if saving is enabled
            if !WellbeingStore.shared.savingPaused {
                let lensEntry = LensLedgerEntry(
                    label: observation.sceneDescription,
                    confidence: observation.qualityConfidence,
                    scene: observation.sceneDescription
                )
                WellbeingStore.shared.addLensEntry(lensEntry)
            }

            // Transition to prompting
            transitionTo(.prompting)
        } catch is CancellationError {
            // Cancelled by newer tick — silently recover
            if runtimeState == .perceiving { transitionTo(.cameraActive) }
        } catch {
            print("[Companion] observation error: \(error)")
            AgentTraceCollector.shared.log(agent: "Vision", model: "mistral-small", action: "companionObserve", status: .failed, detail: String(describing: error).prefix(60).description)
            transitionTo(.errorSafe)
            // Auto-recover — bounded timeout
            Task {
                try? await Task.sleep(for: .seconds(3))
                if runtimeState == .errorSafe { transitionTo(.cameraActive) }
            }
        }
    }

    // MARK: - User Interaction

    private func handleChipTap(_ chip: String, check: SkillCheck? = nil) {
        guard !isGenerating else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Skill check result announcement
        if let check {
            let passed = check.rollResult()
            let resultText = passed ? "Success" : "Failure"
            let checkMsg = CompanionMessage.system(
                "[\(check.stat.displayName.uppercased()) – \(check.difficulty.displayName): \(resultText)]"
            )
            withAnimation(.easeInOut(duration: 0.2)) {
                messages.append(checkMsg)
            }
            SoundManager.shared.play(passed ? .successChime : .errorSound, volume: 0.3)
        }

        let userMsg = CompanionMessage.user(chip)
        withAnimation(.easeInOut(duration: 0.2)) {
            messages.append(userMsg)
        }
        conversationHistory.append(.user(chip))
        UserProfile.recordSuggestionTap(chip, index: nil)

        policyEngine.recordAcceptance()
        TelemetryCollector.shared.recordPromptAccepted(goal: chip)

        let lower = chip.lowercased()

        // Wellbeing: detect curiosity-type chips
        if lower.contains("wonder") || lower.contains("curious") {
            saveCuriosityEntry(
                object: lastSceneDescription,
                wonder: chip,
                followUp: "Tap to explore further"
            )
        }

        // Wellbeing: detect text-save chips
        if lower.contains("save text") || lower.contains("keep this") || lower.contains("remember text") {
            if let lastCompanion = messages.last(where: { $0.role == .companion }) {
                savePoetryEntry(text: lastCompanion.content)
            }
        }

        // Wellbeing: detect mirror/reflect chips
        if lower.contains("reflect") || lower.contains("mirror") || lower.contains("how am i") {
            showMirrorArtifact()
            return
        }

        // OCR: detect translate/read text chips → use structured OCR
        if lower.contains("translate") || lower.contains("read all text") || lower.contains("ocr") || lower.contains("read text") {
            currentAnalysisTask?.cancel()
            currentGenerationTask?.cancel()
            currentGenerationTask = Task { await runOCRAndBuildArtifact(goal: chip) }
            return
        }

        // Object dialogue: enrich with scene context (detect various dialogue-style chips)
        let dialogueKeywords = ["talk to", "interrogate", "interview", "ask the", "converse", "speak to", "confess", "whisper to", "question the"]
        if dialogueKeywords.contains(where: { lower.contains($0) }) {
            let enrichedGoal = lastSceneDescription.isEmpty ? chip : "\(chip) — the object is: \(lastSceneDescription)"
            currentAnalysisTask?.cancel()
            currentGenerationTask?.cancel()
            currentGenerationTask = Task { await generateArtifact(goal: enrichedGoal) }
            return
        }

        // Deep dive: uses larger model for comprehensive analysis
        if lower.contains("deep dive") || lower.contains("learn more") || lower.contains("tell me everything") || lower.contains("full analysis") {
            currentAnalysisTask?.cancel()
            currentGenerationTask?.cancel()
            currentGenerationTask = Task { await generateDeepDiveArtifact(goal: chip) }
            return
        }

        // Cancel stale analysis, start generation
        currentAnalysisTask?.cancel()
        currentGenerationTask?.cancel()
        currentGenerationTask = Task { await generateArtifact(goal: chip) }
    }

    /// Recall a saved skill — re-generates the artifact applied to the current scene context
    private func handleSkillRecall(_ skill: SavedSkill) {
        guard !isGenerating else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        SkillStore.shared.recordUse(skill.id)

        // If scene has changed since the skill was saved, re-generate with current context
        let currentScene = lastSceneDescription
        let sceneChanged = !currentScene.isEmpty && currentScene.lowercased() != skill.sceneDescription.lowercased()

        if sceneChanged {
            // Re-generate: apply the saved skill's format/goal to the NEW object
            let contextualGoal = "\(skill.goal) — apply this to: \(currentScene)"
            let userMsg = CompanionMessage.user("\(skill.goal) (on \(currentScene.prefix(30)))")
            withAnimation(.easeInOut(duration: 0.2)) {
                messages.append(userMsg)
            }
            currentGenerationTask?.cancel()
            currentGenerationTask = Task { await generateArtifact(goal: contextualGoal) }
        } else {
            // Same scene or no scene — instant render from saved HTML
            let userMsg = CompanionMessage.user(skill.goal)
            withAnimation(.easeInOut(duration: 0.2)) {
                messages.append(userMsg)
            }

            artifactGoal = skill.goal
            artifactHTML = skill.html
            SoundManager.shared.play(.artifactReveal)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            transitionTo(.acting)
            withAnimation(.spring(duration: 0.4)) {
                showArtifact = true
            }
        }
    }

    private func submitInput() {
        guard !isGenerating else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        isInputFocused = false

        let userMsg = CompanionMessage.user(text)
        withAnimation(.easeInOut(duration: 0.2)) {
            messages.append(userMsg)
        }
        conversationHistory.append(.user(text))
        UserProfile.recordSuggestionTap(text, index: nil)

        policyEngine.recordAcceptance()
        TelemetryCollector.shared.recordPromptAccepted(goal: text)

        currentAnalysisTask?.cancel()
        currentGenerationTask?.cancel()
        currentGenerationTask = Task { await generateArtifact(goal: text) }
    }

    // MARK: - Artifact Generation

    private func generateArtifact(goal: String) async {
        guard !isGenerating else { return }
        guard let snapshot = camera.captureSnapshot() else {
            errorMessage = "Camera not ready"
            showError = true
            return
        }

        isGenerating = true
        transitionTo(.acting)

        // Show a system message
        let thinkingMsg = CompanionMessage.system("Creating something for you...")
        withAnimation { messages.append(thinkingMsg) }

        defer {
            isGenerating = false
            // Remove the thinking message
            withAnimation {
                messages.removeAll { $0.id == thinkingMsg.id }
            }
        }

        do {
            artifactGoal = goal
            sceneSession.currentGoal = goal
            sceneSession.recordGoalAttempt(goal)
            sceneSession.artifactsGenerated += 1
            sceneSession.recordArtifactFormat(goal)

            let artifactTraceStart = Date()
            AgentTraceCollector.shared.log(agent: "Artifact", model: "mistral-small", action: "generateArtifact", status: .started, detail: goal.prefix(40).description)

            let html: String
            if demoMode {
                try await Task.sleep(for: .milliseconds(600))
                html = DemoModeCache.shared.fallbackArtifact(goal: goal)
                AgentTraceCollector.shared.log(agent: "Artifact", model: "demo-cache", action: "generateArtifact", status: .completed, durationMs: 600, detail: "[DEMO] \(goal.prefix(20))")
            } else {
                let profile = UserProfile.load() ?? UserProfile()
                html = try await MistralAPI.shared.generateArtifact(
                    imageData: snapshot.data,
                    goal: goal,
                    userProfile: profile,
                    sceneSession: sceneSession
                )
            }
            let artifactTraceDuration = Int(Date().timeIntervalSince(artifactTraceStart) * 1000)
            AgentTraceCollector.shared.log(agent: "Artifact", model: "mistral-small", action: "generateArtifact", status: .completed, durationMs: artifactTraceDuration, detail: "\(html.count) chars")
            let validatedHTML = ArtifactWebView.validateArtifactHTML(html, goal: goal)
            artifactHTML = validatedHTML
            artifactCache[goal] = validatedHTML  // cache successful artifact
            AgentTraceCollector.shared.lastArtifactJSON = "Goal: \(goal)\nHTML length: \(html.count) chars\n\n\(html.prefix(500))"
            TelemetryCollector.shared.recordArtifactGenerated(goal: goal)
            SoundManager.shared.play(.artifactReveal)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(duration: 0.4)) {
                showArtifact = true
            }
        } catch {
            // Log failure trace
            AgentTraceCollector.shared.log(agent: "Artifact", model: "mistral-small", action: "generateArtifact", status: .failed, detail: String(describing: error).prefix(60).description)
            // Try to serve cached artifact on failure
            if let cached = artifactCache[goal] {
                print("[Companion] Serving cached artifact for: \(goal)")
                artifactHTML = cached
                SoundManager.shared.play(.artifactReveal)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(duration: 0.4)) {
                    showArtifact = true
                }
            } else {
                errorMessage = error.localizedDescription
                showError = true
                SoundManager.shared.play(.errorSound, volume: 0.2)
                transitionTo(.errorSafe)
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    transitionTo(.cameraActive)
                }
            }
        }
    }

    // MARK: - OCR Artifact

    private func runOCRAndBuildArtifact(goal: String) async {
        guard !isGenerating else { return }
        guard let snapshot = camera.captureSnapshot() else {
            errorMessage = "Camera not ready"
            showError = true
            return
        }

        isGenerating = true
        transitionTo(.acting)

        let thinkingMsg = CompanionMessage.system("Reading text...")
        withAnimation { messages.append(thinkingMsg) }

        defer {
            isGenerating = false
            withAnimation {
                messages.removeAll { $0.id == thinkingMsg.id }
            }
        }

        do {
            let traceStart = Date()
            AgentTraceCollector.shared.log(agent: "OCR", model: "mistral-small", action: "extractText", status: .started, detail: goal.prefix(40).description)

            let profile = UserProfile.load() ?? UserProfile()
            let ocrResult = try await MistralAPI.shared.extractText(
                imageData: snapshot.data,
                targetLanguage: profile.language
            )

            let traceDuration = Int(Date().timeIntervalSince(traceStart) * 1000)
            AgentTraceCollector.shared.log(agent: "OCR", model: "mistral-small", action: "extractText", status: .completed, durationMs: traceDuration, detail: "\(ocrResult.regions.count) regions, \(ocrResult.languagesDetected.joined(separator: ","))")

            // Build structured HTML artifact from OCR results
            let html = buildOCRArtifactHTML(result: ocrResult)
            artifactGoal = goal
            let validatedOCRHTML = ArtifactWebView.validateArtifactHTML(html, goal: goal)
            artifactHTML = validatedOCRHTML
            artifactCache[goal] = validatedOCRHTML
            SoundManager.shared.play(.artifactReveal)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(duration: 0.4)) {
                showArtifact = true
            }

            // Save as poetry entry
            let allText = ocrResult.regions.map(\.text).joined(separator: " ")
            savePoetryEntry(text: allText)

        } catch {
            AgentTraceCollector.shared.log(agent: "OCR", model: "mistral-small", action: "extractText", status: .failed, detail: String(describing: error).prefix(60).description)
            // Fallback to regular artifact generation
            await generateArtifact(goal: goal)
        }
    }

    private func buildOCRArtifactHTML(result: MistralAPI.OCRResult) -> String {
        let typeColors: [String: String] = [
            "label": "#8B5CF6",
            "heading": "#3B82F6",
            "body": "#6B7280",
            "button": "#10B981",
            "warning": "#EF4444",
            "number": "#F59E0B"
        ]

        var regionRows = ""
        for region in result.regions {
            let color = typeColors[region.textType] ?? "#6B7280"
            let confPct = Int(region.confidence * 100)
            regionRows += """
            <div class="region" style="border-left: 3px solid \(color);">
                <div class="region-header">
                    <span class="type-badge" style="background: \(color)20; color: \(color);">\(region.textType)</span>
                    <span class="lang-badge">\(region.language)</span>
                    <span class="conf">\(confPct)%</span>
                </div>
                <div class="original">\(Self.escapeHTML(region.text))</div>
                \(region.text != region.translation ? "<div class=\"translation\">\(Self.escapeHTML(region.translation))</div>" : "")
            </div>
            """
        }

        let langs = result.languagesDetected.joined(separator: ", ")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, sans-serif; background: #0F0F14; color: #E5E7EB; padding: 20px; }
        .header { margin-bottom: 20px; }
        .header h1 { font-size: 18px; color: #fff; margin-bottom: 4px; }
        .header .meta { font-size: 12px; color: #9CA3AF; }
        .summary { font-size: 14px; color: #D1D5DB; margin-bottom: 16px; padding: 12px; background: #1F1F2E; border-radius: 10px; }
        .region { padding: 12px; margin-bottom: 8px; background: #1A1A28; border-radius: 8px; }
        .region-header { display: flex; align-items: center; gap: 8px; margin-bottom: 6px; }
        .type-badge { font-size: 10px; font-weight: 600; padding: 2px 8px; border-radius: 10px; text-transform: uppercase; letter-spacing: 0.5px; }
        .lang-badge { font-size: 10px; color: #9CA3AF; background: #374151; padding: 2px 6px; border-radius: 6px; }
        .conf { font-size: 10px; color: #6B7280; margin-left: auto; }
        .original { font-size: 15px; font-weight: 500; margin-bottom: 4px; }
        .translation { font-size: 13px; color: #9CA3AF; font-style: italic; }
        .footer { margin-top: 16px; text-align: center; }
        .footer button { background: #8B5CF6; color: white; border: none; padding: 10px 24px; border-radius: 20px; font-size: 14px; font-weight: 600; }
        </style>
        </head>
        <body>
        <div class="header">
            <h1>Text Extraction</h1>
            <div class="meta">\(result.regions.count) regions · Languages: \(langs)</div>
        </div>
        <div class="summary">\(Self.escapeHTML(result.summary))</div>
        \(regionRows)
        <div class="footer">
            <button onclick="window.AGI && AGI.done()">Done</button>
        </div>
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Deep Dive Artifact

    private func generateDeepDiveArtifact(goal: String) async {
        guard !isGenerating else { return }
        guard let snapshot = camera.captureSnapshot() else {
            errorMessage = "Camera not ready"
            showError = true
            return
        }

        isGenerating = true
        transitionTo(.acting)

        let thinkingMsg = CompanionMessage.system("Deep diving with mistral-large + web search...")
        withAnimation { messages.append(thinkingMsg) }

        defer {
            isGenerating = false
            withAnimation {
                messages.removeAll { $0.id == thinkingMsg.id }
            }
        }

        do {
            let traceStart = Date()
            AgentTraceCollector.shared.log(agent: "DeepDive", model: "mistral-large+web_search", action: "deepDiveArtifact", status: .started, detail: goal.prefix(40).description)

            let profile = UserProfile.load() ?? UserProfile()
            let html = try await MistralAPI.shared.generateDeepDiveArtifact(
                imageData: snapshot.data,
                goal: goal,
                userProfile: profile,
                sceneSession: sceneSession
            )

            let traceDuration = Int(Date().timeIntervalSince(traceStart) * 1000)
            AgentTraceCollector.shared.log(agent: "DeepDive", model: "mistral-large+web_search", action: "deepDiveArtifact", status: .completed, durationMs: traceDuration, detail: "\(html.count) chars")

            artifactGoal = goal
            let validatedDeepDiveHTML = ArtifactWebView.validateArtifactHTML(html, goal: goal)
            artifactHTML = validatedDeepDiveHTML
            artifactCache[goal] = validatedDeepDiveHTML
            AgentTraceCollector.shared.lastArtifactJSON = "Goal: \(goal)\nModel: mistral-large + web_search\nHTML length: \(html.count) chars\n\n\(html.prefix(500))"
            SoundManager.shared.play(.artifactReveal)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(duration: 0.4)) {
                showArtifact = true
            }
        } catch {
            AgentTraceCollector.shared.log(agent: "DeepDive", model: "mistral-large+web_search", action: "deepDiveArtifact", status: .failed, detail: String(describing: error).prefix(60).description)
            // Fallback to regular generation
            await generateArtifact(goal: goal)
        }
    }

    // MARK: - Environmental Stat Keywords

    private static let statEnvironmentKeywords: [(CompanionStat, [String])] = [
        (.inlandEmpire, ["old", "worn", "abandoned", "forgotten", "dusty", "vintage", "antique"]),
        (.encyclopedia, ["label", "text", "brand", "model", "serial", "spec", "manual", "patent"]),
        (.empathy, ["person", "people", "photo", "portrait", "wear", "scratch", "used"]),
        (.visualCalculus, ["grid", "layout", "symmetr", "angle", "align", "diagram", "blueprint"]),
        (.electrochemistry, ["color", "texture", "leather", "metal", "wood", "fabric", "glass"]),
        (.rhetoric, ["sign", "poster", "advertis", "claim", "slogan", "warning"]),
        (.shivers, ["window", "street", "city", "sky", "weather", "outside", "urban"]),
        (.conceptualization, ["art", "design", "pattern", "decor", "aesthetic", "creative", "paint"])
    ]

    // MARK: - Perceptual Hash

    /// Strip stat/skill bracket tags from message text for TTS narration
    private static func stripStatTags(_ text: String) -> String {
        let pattern = "\\[(?:INLAND EMPIRE|ENCYCLOPEDIA|EMPATHY|VISUAL CALCULUS|ELECTROCHEMISTRY|RHETORIC|SHIVERS|CONCEPTUALIZATION)[^\\]]*\\]:?\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Downscale image to 8x8 grayscale grid → 64-byte hash
    private static func perceptualHash(_ image: UIImage) -> [UInt8] {
        let size = CGSize(width: 8, height: 8)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        guard let cgImage = UIGraphicsGetImageFromCurrentImageContext()?.cgImage else {
            UIGraphicsEndImageContext()
            return []
        }
        UIGraphicsEndImageContext()

        guard let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else {
            return []
        }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        var hash: [UInt8] = []
        for i in 0..<64 {
            let offset = i * bytesPerPixel
            // Simple luminance from RGB
            let r = UInt16(ptr[offset])
            let g = UInt16(ptr[offset + 1])
            let b = UInt16(ptr[offset + 2])
            let gray = UInt8((r * 77 + g * 150 + b * 29) >> 8)
            hash.append(gray)
        }
        return hash
    }

    /// Compare two perceptual hashes → similarity 0.0 to 1.0
    private static func hashSimilarity(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == 64 && b.count == 64 else { return 0.0 }
        var totalDiff: Int = 0
        for i in 0..<64 {
            totalDiff += abs(Int(a[i]) - Int(b[i]))
        }
        // Max possible difference: 64 * 255 = 16320
        return 1.0 - Double(totalDiff) / 16320.0
    }

    // MARK: - Artifact Actions

    private func shareArtifact(html: String, goal: String) {
        // Create a shareable text summary + HTML file (sanitize filename)
        let sanitized = goal.prefix(30)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "|", with: "-")
        let filename = sanitized + ".html"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? html.write(to: tempURL, atomically: true, encoding: .utf8)

        let items: [Any] = [
            "AGI generated artifact: \(goal)" as String,
            tempURL
        ]

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        SoundManager.shared.play(.successChime, volume: 0.2)
    }

    // MARK: - Skill Save/Recall

    private func saveArtifactAsSkill(html: String, goal: String) {
        let skill = SavedSkill(goal: goal, html: html, sceneDescription: lastSceneDescription)
        SkillStore.shared.save(skill)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        SoundManager.shared.play(.successChime, volume: 0.2)
        let saveMsg = CompanionMessage.system("Saved as skill: \(goal)")
        withAnimation(.easeInOut(duration: 0.2)) {
            messages.append(saveMsg)
        }
    }

    private func isSkillSaved(goal: String) -> Bool {
        SkillStore.shared.skills.contains { $0.goal.lowercased() == goal.lowercased() }
    }

    // MARK: - Skill Browser Sheet

    private var skillBrowserSheet: some View {
        NavigationStack {
            List {
                // MARK: Artifact Catalog
                Section {
                    ForEach(Self.artifactCatalog, id: \.prompt) { entry in
                        Button {
                            showSkillBrowser = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                let goal = lastSceneDescription.isEmpty
                                    ? entry.prompt
                                    : "\(entry.prompt) — apply to: \(lastSceneDescription)"
                                handleChipTap(goal)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Text(entry.emoji)
                                    .font(.title)
                                    .frame(width: 44, height: 44)
                                    .background(entry.color.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                    Text(entry.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("Artifact Catalog")
                } footer: {
                    Text("Tap any format to generate it for what's on camera right now.")
                }

                // MARK: Saved Skills
                if !SkillStore.shared.skills.isEmpty {
                    Section {
                        ForEach(SkillStore.shared.skills) { skill in
                            Button {
                                showSkillBrowser = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    handleSkillRecall(skill)
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    Text(skillEmoji(for: skill.goal))
                                        .font(.title)
                                        .frame(width: 44, height: 44)
                                        .background(Color.yellow.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(skill.goal)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)

                                        HStack(spacing: 8) {
                                            Label(skill.timestamp.formatted(.relative(presentation: .named)), systemImage: "clock")
                                            if skill.useCount > 0 {
                                                Label("\(skill.useCount)x", systemImage: "arrow.counterclockwise")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                        if !skill.sceneDescription.isEmpty {
                                            Text(skill.sceneDescription)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .onDelete { offsets in
                            SkillStore.shared.remove(at: offsets)
                        }
                    } header: {
                        Text("Saved Skills")
                    } footer: {
                        Text("\(SkillStore.shared.skills.count) saved. Swipe to delete.")
                    }
                }
            }
            .navigationTitle("Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showSkillBrowser = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Artifact Catalog Data

    private struct ArtifactCatalogEntry {
        let emoji: String
        let name: String
        let description: String
        let prompt: String
        let color: Color
    }

    private static let artifactCatalog: [ArtifactCatalogEntry] = [
        .init(emoji: "🃏", name: "Collectible Card", description: "Trading card with rarity, stats, and flavor text", prompt: "Mint a collectible card", color: .yellow),
        .init(emoji: "💬", name: "Object Dialogue", description: "Inner-voice conversation with the object", prompt: "Talk to this object", color: .purple),
        .init(emoji: "📖", name: "Narrative Card", description: "Literary story about what you see", prompt: "Write its autobiography", color: .orange),
        .init(emoji: "🔍", name: "Spec Sheet", description: "Technical identification and specs", prompt: "Identify and run the specs", color: .cyan),
        .init(emoji: "📊", name: "Comparison Chart", description: "Rating bars, scored breakdown", prompt: "Rate and score this", color: .green),
        .init(emoji: "🗺️", name: "Visual Map", description: "CSS diagram, spatial layout, heatmap", prompt: "Map the layout", color: .blue),
        .init(emoji: "⏳", name: "Timeline", description: "Chronological history or evolution", prompt: "Build a timeline of its history", color: .brown),
        .init(emoji: "🐉", name: "Bestiary Entry", description: "RPG encyclopedia entry with traits and lore", prompt: "Add to the bestiary", color: .red),
        .init(emoji: "🧠", name: "Quiz / Flashcard", description: "Interactive trivia about the object", prompt: "Quiz me on this", color: .indigo),
        .init(emoji: "🎨", name: "Mood Palette", description: "Color swatches, vibe analysis, aesthetic", prompt: "Extract the vibe palette", color: .pink),
        .init(emoji: "⭐", name: "Review / Roast", description: "Honest review with star ratings and verdict", prompt: "Roast and review this", color: .orange),
        .init(emoji: "🏆", name: "Tier List", description: "S/A/B/C/D ranking with justification", prompt: "Tier rank this", color: .yellow),
        .init(emoji: "📐", name: "Blueprint", description: "Technical schematic with labeled components", prompt: "Blueprint the internals", color: .gray),
        .init(emoji: "⚔️", name: "VS Battle", description: "Head-to-head matchup with stat comparison", prompt: "Battle: this versus its rival", color: .red),
        .init(emoji: "🎮", name: "Simulation", description: "Mini interactive demo with CSS animations", prompt: "Simulate how this works", color: .green),
        .init(emoji: "🖊️", name: "Poem / Haiku", description: "Formatted literary piece inspired by the object", prompt: "Compose a poem about this", color: .purple),
        .init(emoji: "🧪", name: "Recipe", description: "Ingredients, proportions, and steps", prompt: "Show the recipe or ingredients", color: .mint),
        .init(emoji: "📋", name: "Step-by-Step Guide", description: "Visual guide with numbered steps", prompt: "Explain how to use this step by step", color: .teal),
        .init(emoji: "🌐", name: "Translation", description: "Read and translate text on the object", prompt: "Translate the text", color: .blue),
        .init(emoji: "🔬", name: "Deep Dive", description: "Web-backed research with real-world data", prompt: "Deep dive with web search", color: .indigo),
    ]

    /// Extract a representative emoji from the skill goal text
    private func skillEmoji(for goal: String) -> String {
        let lower = goal.lowercased()
        if lower.contains("card") || lower.contains("collect") || lower.contains("mint") { return "🃏" }
        if lower.contains("dialogue") || lower.contains("talk") || lower.contains("interview") || lower.contains("interrogate") { return "💬" }
        if lower.contains("map") || lower.contains("diagram") || lower.contains("blueprint") { return "🗺️" }
        if lower.contains("spec") || lower.contains("identify") || lower.contains("id ") { return "🔍" }
        if lower.contains("story") || lower.contains("narrate") || lower.contains("lore") { return "📖" }
        if lower.contains("chart") || lower.contains("compare") || lower.contains("rate") || lower.contains("score") { return "📊" }
        if lower.contains("timeline") || lower.contains("history") { return "⏳" }
        if lower.contains("bestiary") || lower.contains("creature") || lower.contains("log") { return "🐉" }
        if lower.contains("quiz") || lower.contains("trivia") || lower.contains("flashcard") { return "🧠" }
        if lower.contains("roast") || lower.contains("review") || lower.contains("critique") { return "⭐" }
        if lower.contains("poem") || lower.contains("haiku") || lower.contains("ode") { return "🖊️" }
        if lower.contains("tier") || lower.contains("rank") { return "🏆" }
        if lower.contains("mood") || lower.contains("vibe") || lower.contains("palette") { return "🎨" }
        if lower.contains("battle") || lower.contains("versus") || lower.contains("vs") { return "⚔️" }
        if lower.contains("recipe") || lower.contains("ingredient") { return "🧪" }
        if lower.contains("guide") || lower.contains("how") || lower.contains("explain") { return "📋" }
        if lower.contains("translate") || lower.contains("read") { return "🌐" }
        if lower.contains("deep dive") || lower.contains("learn more") { return "🔬" }
        return "✨"
    }

    // MARK: - Wellbeing Artifact Flows

    private func savePoetryEntry(text: String) {
        guard !WellbeingStore.shared.savingPaused else { return }
        let entry = PoetryLogEntry(excerpt: String(text.prefix(300)), sourceType: "ocr")
        WellbeingStore.shared.addPoetryEntry(entry)
    }

    private func saveCuriosityEntry(object: String, wonder: String, followUp: String) {
        guard !WellbeingStore.shared.savingPaused else { return }
        let entry = CuriosityEntry(object: object, wonder: wonder, followUp: followUp)
        WellbeingStore.shared.addCuriosityEntry(entry)
    }

    private func saveMirrorEntry(mood: Int, note: String) {
        let entry = MirrorEntry(mood: mood, note: note)
        WellbeingStore.shared.addMirrorEntry(entry)
    }

    /// Generates a local One Minute Mirror artifact (no API call)
    private func showMirrorArtifact() {
        artifactGoal = "One Minute Mirror"
        artifactHTML = Self.mirrorArtifactHTML()
        transitionTo(.acting)
        withAnimation(.spring(duration: 0.4)) {
            showArtifact = true
        }
    }

    private static func mirrorArtifactHTML() -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;background:transparent;color:#fff;font-family:-apple-system,sans-serif}
        .card{background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.18);backdrop-filter:blur(16px);border-radius:16px;padding:18px;max-width:340px;margin:0 auto}
        h2{margin:0 0 8px;font-size:18px}
        .muted{color:rgba(255,255,255,.6);font-size:13px;margin-bottom:14px}
        .moods{display:flex;gap:10px;justify-content:center;margin:16px 0}
        .mood{width:48px;height:48px;border-radius:50%;border:2px solid rgba(255,255,255,.2);display:flex;align-items:center;justify-content:center;font-size:24px;cursor:pointer;transition:all .2s}
        .mood.sel{border-color:#22c55e;background:rgba(34,197,94,.2);transform:scale(1.15)}
        input[type=text]{width:100%;box-sizing:border-box;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.15);border-radius:10px;color:#fff;padding:10px;font-size:14px;margin:10px 0}
        .save{width:100%;min-height:44px;border:0;border-radius:10px;background:#22c55e;color:#062b12;font-weight:700;font-size:15px;cursor:pointer;margin-top:8px}
        .save:disabled{opacity:.4}
        </style></head><body><div class="card">
        <h2>One Minute Mirror</h2>
        <div class="muted">How are you feeling right now?</div>
        <div class="moods" id="moods"></div>
        <input type="text" id="note" placeholder="One-line note (optional)" maxlength="100">
        <button class="save" id="saveBtn" disabled onclick="doSave()">Save reflection</button>
        </div>
        <script>
        var sel=0;var emojis=['😔','😕','😐','🙂','😊'];
        var md=document.getElementById('moods');
        emojis.forEach(function(e,i){var d=document.createElement('div');d.className='mood';d.textContent=e;d.onclick=function(){sel=i+1;document.querySelectorAll('.mood').forEach(function(m){m.classList.remove('sel')});d.classList.add('sel');document.getElementById('saveBtn').disabled=false;try{AGI.haptic('selection')}catch(x){}};md.appendChild(d)});
        function doSave(){if(!sel)return;var n=document.getElementById('note').value||'';try{AGI.haptic('success');AGI.done('mirror_'+sel+'_'+encodeURIComponent(n))}catch(e){};document.querySelector('.muted').textContent='Saved. Take care.';document.getElementById('saveBtn').textContent='Done';document.getElementById('saveBtn').onclick=function(){try{AGI.done('all')}catch(e){}}}
        </script></body></html>
        """
    }

    // MARK: - Artifact Actions

    private func handleArtifactAction(_ action: ArtifactAction) {
        switch action {
        case .stepDone(let stepId):
            // Handle mirror artifact results
            if stepId.hasPrefix("mirror_") {
                let parts = stepId.dropFirst(7).split(separator: "_", maxSplits: 1)
                let mood = Int(parts.first ?? "3") ?? 3
                let note = parts.count > 1 ? String(parts[1]).removingPercentEncoding ?? "" : ""
                saveMirrorEntry(mood: mood, note: note)
            }
            sceneSession.recordStepSuccess(stepId)
            transitionTo(.verifying)
            Task {
                try? await Task.sleep(for: .seconds(0.5))
                transitionTo(.learning)
                try? await Task.sleep(for: .seconds(0.3))
                transitionTo(.cameraActive)
            }

        case .stepFailed(let stepId, let reason):
            sceneSession.recordStepFailure(stepId)
            TelemetryCollector.shared.recordTaskFailure(goal: artifactGoal, reason: reason)
            // Track missed hazard if the assessed risk was low
            if currentRiskLevel == "low" {
                TelemetryCollector.shared.recordMissedHazard(goal: artifactGoal, riskLevel: currentRiskLevel)
            }

        case .allDone:
            sceneSession.recordGoalSuccess(sceneSession.currentGoal)
            TelemetryCollector.shared.recordTaskSuccess(goal: artifactGoal)
            SoundManager.shared.play(.artifactClose, volume: 0.25)
            withAnimation(.easeInOut(duration: 0.25)) {
                showArtifact = false
                artifactHTML = nil
                transitionTo(.cameraActive)
            }

        case .whyTapped:
            TelemetryCollector.shared.recordWhyTap()

        case .dialogueReply(let text):
            // Inject dialogue choice into conversation history
            let userMsg = CompanionMessage.user(text)
            withAnimation(.easeInOut(duration: 0.2)) {
                messages.append(userMsg)
            }
            conversationHistory.append(.user("[Dialogue choice] \(text)"))
            SoundManager.shared.play(.bubbleAppear, volume: 0.15)
        }
    }

    // MARK: - Crowd Notes Overlay

    private var crowdNotesOverlay: some View {
        GeometryReader { proxy in
            ZStack {
                // Render each visible note chip at its bbox position
                ForEach(crowdNotes.filter { !$0.hidden }) { note in
                    let x = note.bbox.centerX * proxy.size.width
                    let y = note.bbox.centerY * proxy.size.height

                    crowdNoteChip(note: note)
                        .position(x: x, y: y)
                        .transition(.scale.combined(with: .opacity))
                }

                // Selected note detail card
                if let selectedId = selectedNoteId,
                   let note = crowdNotes.first(where: { $0.id == selectedId && !$0.hidden }) {
                    crowdNoteDetail(note: note, in: proxy)
                }

                // Detection indicator
                if isDetectionInFlight {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 6) {
                                ProgressView()
                                    .tint(.white.opacity(0.6))
                                    .scaleEffect(0.6)
                                Text("Scanning...")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial.opacity(0.5))
                            .clipShape(Capsule())
                            .padding(.trailing, 20)
                        }
                        Spacer()
                    }
                    .padding(.top, 50)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func crowdNoteChip(note: CrowdNote) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedNoteId = selectedNoteId == note.id ? nil : note.id
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(noteColor(for: note))
                    .frame(width: 6, height: 6)
                Text(note.label)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if note.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial.opacity(0.8))
            )
            .overlay(
                Capsule()
                    .stroke(noteColor(for: note).opacity(0.4), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func crowdNoteDetail(note: CrowdNote, in proxy: GeometryProxy) -> some View {
        let x = min(max(170, note.bbox.centerX * proxy.size.width), proxy.size.width - 170)
        let y = min(note.bbox.centerY * proxy.size.height + 50, proxy.size.height - 200)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(noteColor(for: note))
                    .frame(width: 8, height: 8)
                Text(note.label)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation { selectedNoteId = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Text(note.note)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(3)

            // Action buttons
            HStack(spacing: 8) {
                crowdNoteAction("Create Artifact", icon: "sparkles") {
                    selectedNoteId = nil
                    currentGenerationTask?.cancel()
                    currentGenerationTask = Task {
                        await generateArtifact(goal: "\(note.label): \(note.note)")
                    }
                }
                crowdNoteAction(note.pinned ? "Unpin" : "Pin", icon: "pin") {
                    togglePin(noteId: note.id)
                }
                crowdNoteAction("Hide", icon: "eye.slash") {
                    hideNote(noteId: note.id)
                }
                crowdNoteAction("Forget", icon: "trash") {
                    forgetNote(noteId: note.id)
                }
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(noteColor(for: note).opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        .position(x: x, y: y)
        .transition(.scale.combined(with: .opacity))
    }

    private func crowdNoteAction(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 9))
            }
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func noteColor(for note: CrowdNote) -> Color {
        switch note.riskLevel {
        case "high": return Color(red: 1.0, green: 0.3, blue: 0.2)
        case "medium": return Color(red: 1.0, green: 0.65, blue: 0.1)
        default:
            if note.confidence < 0.4 { return Color(red: 1.0, green: 0.7, blue: 0.2) }
            return Color(red: 0.3, green: 0.7, blue: 1.0)
        }
    }

    // MARK: - Crowd Notes Timer & Detection

    private func startCrowdNotesTimer() {
        // Initial detection
        Task { await crowdNotesTick() }
        // Periodic re-detection every 8s (give user time to interact)
        crowdNotesTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { _ in
            Task { @MainActor in
                await crowdNotesTick()
            }
        }
    }

    private func stopCrowdNotesTimer() {
        crowdNotesTimer?.invalidate()
        crowdNotesTimer = nil
    }

    private func crowdNotesTick() async {
        guard crowdNotesMode else { return }
        guard !isDetectionInFlight else { return }
        guard !sensingPaused else { return }
        guard !showArtifact else { return }
        guard !isGenerating else { return }
        guard let snapshot = camera.captureSnapshot() else { return }

        isDetectionInFlight = true
        defer { isDetectionInFlight = false }

        let detected = try? await MistralAPI.shared.detectObjects(imageData: snapshot.data)
        guard let objects = detected, !objects.isEmpty else { return }

        withAnimation(.spring(duration: 0.6, bounce: 0.15)) {
            // Build a lookup of existing non-pinned notes by lowercase label
            var existingByLabel: [String: Int] = [:]  // label -> index in crowdNotes
            for (idx, note) in crowdNotes.enumerated() {
                if !note.pinned {
                    existingByLabel[note.label.lowercased()] = idx
                }
            }

            var matchedLabels: Set<String> = []

            for obj in objects {
                let labelLower = obj.label.lowercased()

                // Skip if a pinned note already covers this label
                if crowdNotes.contains(where: { $0.pinned && $0.label.lowercased() == labelLower }) {
                    matchedLabels.insert(labelLower)
                    continue
                }

                if let existingIdx = existingByLabel[labelLower] {
                    // Update position + note text in place — keeps the same ID so SwiftUI animates
                    crowdNotes[existingIdx].bbox = obj.bbox
                    crowdNotes[existingIdx].note = obj.note
                    crowdNotes[existingIdx].confidence = obj.confidence
                    matchedLabels.insert(labelLower)
                } else {
                    // Genuinely new object — add it
                    SoundManager.shared.play(.objectDetected, volume: 0.15)
                    let note = CrowdNote(
                        trackId: nextTrackId,
                        label: obj.label,
                        bbox: obj.bbox,
                        note: obj.note,
                        confidence: obj.confidence,
                        riskLevel: obj.riskLevel
                    )
                    nextTrackId += 1
                    crowdNotes.append(note)
                    matchedLabels.insert(labelLower)
                }
            }

            // Remove non-pinned notes that weren't seen this cycle (object left the frame)
            crowdNotes.removeAll { note in
                !note.pinned && !matchedLabels.contains(note.label.lowercased())
            }
        }

        // Wellbeing: log detected objects
        if !WellbeingStore.shared.savingPaused {
            for obj in objects ?? [] {
                let entry = LensLedgerEntry(
                    label: obj.label,
                    confidence: obj.confidence,
                    scene: "crowd_notes"
                )
                WellbeingStore.shared.addLensEntry(entry)
            }
        }
    }

    // MARK: - Crowd Notes Actions

    private func togglePin(noteId: UUID) {
        if let idx = crowdNotes.firstIndex(where: { $0.id == noteId }) {
            crowdNotes[idx].pinned.toggle()
            SoundManager.shared.play(.pinNote, volume: 0.25)
        }
    }

    private func hideNote(noteId: UUID) {
        withAnimation {
            if let idx = crowdNotes.firstIndex(where: { $0.id == noteId }) {
                crowdNotes[idx].hidden = true
                if selectedNoteId == noteId { selectedNoteId = nil }
            }
        }
    }

    private func forgetNote(noteId: UUID) {
        withAnimation {
            crowdNotes.removeAll { $0.id == noteId }
            if selectedNoteId == noteId { selectedNoteId = nil }
        }
    }

    // MARK: - World Object Labels (main companion mode)

    /// Subtle tappable labels anchored to detected objects in the camera feed.
    /// Tapping one injects it into the conversation.
    private var worldObjectLabels: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(crowdNotes.filter { !$0.hidden }) { note in
                    let x = note.bbox.centerX * proxy.size.width
                    // Place label just above the bbox center, clamped to safe zone
                    // Top: below status bar + top controls (~60pt)
                    // Bottom: above chat bubbles + chips + input + tab bar (~280pt from bottom)
                    let topSafe: CGFloat = 60
                    let bottomSafe = proxy.size.height * 0.58
                    let rawY = note.bbox.y * proxy.size.height - 8
                    let y = min(max(topSafe, rawY), bottomSafe)

                    Button {
                        injectObjectIntoConversation(note)
                    } label: {
                        Text(note.label)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(.black.opacity(0.35))
                                    .background(
                                        Capsule()
                                            .fill(.ultraThinMaterial.opacity(0.4))
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
                            )
                    }
                    .position(x: x, y: y)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    /// When user taps a world object label, inject it into the conversation as context.
    private func injectObjectIntoConversation(_ note: CrowdNote) {
        SoundManager.shared.play(.objectDetected, volume: 0.15)

        let userMsg = CompanionMessage.user("Tell me about the \(note.label)")
        withAnimation(.easeInOut(duration: 0.2)) {
            messages.append(userMsg)
        }
        conversationHistory.append(.user("I'm pointing at the \(note.label). \(note.note). Tell me about it."))

        // Generate artifact about this object
        currentAnalysisTask?.cancel()
        currentGenerationTask?.cancel()
        currentGenerationTask = Task {
            await generateArtifact(goal: "Talk to this object: \(note.label)")
        }
    }

    // MARK: - World Object Timer (background detection for main mode)

    private func startWorldObjectTimer() {
        // Initial detection after a short delay
        Task {
            try? await Task.sleep(for: .seconds(3))
            await worldObjectTick()
        }
        // Re-detect every 12s in main mode (less aggressive than crowd notes mode)
        worldObjectTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: true) { _ in
            Task { @MainActor in
                await worldObjectTick()
            }
        }
    }

    private func stopWorldObjectTimer() {
        worldObjectTimer?.invalidate()
        worldObjectTimer = nil
    }

    /// Lightweight object detection that reuses crowdNotes array.
    /// Only runs when NOT in crowd notes mode (crowd notes mode has its own faster timer).
    private func worldObjectTick() async {
        guard !crowdNotesMode else { return }
        guard !isDetectionInFlight else { return }
        guard !sensingPaused else { return }
        guard !showArtifact else { return }
        guard !isGenerating else { return }
        guard MistralAPI.shared.hasAPIKey else { return }
        guard let snapshot = camera.captureSnapshot() else { return }

        isDetectionInFlight = true
        defer { isDetectionInFlight = false }

        let detected = try? await MistralAPI.shared.detectObjects(imageData: snapshot.data)
        guard let objects = detected, !objects.isEmpty else { return }

        withAnimation(.spring(duration: 0.6, bounce: 0.15)) {
            var existingByLabel: [String: Int] = [:]
            for (idx, note) in crowdNotes.enumerated() {
                if !note.pinned {
                    existingByLabel[note.label.lowercased()] = idx
                }
            }

            var matchedLabels: Set<String> = []

            for obj in objects {
                let labelLower = obj.label.lowercased()
                if crowdNotes.contains(where: { $0.pinned && $0.label.lowercased() == labelLower }) {
                    matchedLabels.insert(labelLower)
                    continue
                }

                if let existingIdx = existingByLabel[labelLower] {
                    crowdNotes[existingIdx].bbox = obj.bbox
                    crowdNotes[existingIdx].note = obj.note
                    matchedLabels.insert(labelLower)
                } else {
                    let note = CrowdNote(
                        trackId: nextTrackId,
                        label: obj.label,
                        bbox: obj.bbox,
                        note: obj.note,
                        confidence: obj.confidence,
                        riskLevel: obj.riskLevel
                    )
                    nextTrackId += 1
                    crowdNotes.append(note)
                    matchedLabels.insert(labelLower)
                }
            }

            crowdNotes.removeAll { note in
                !note.pinned && !matchedLabels.contains(note.label.lowercased())
            }
        }
    }
}
