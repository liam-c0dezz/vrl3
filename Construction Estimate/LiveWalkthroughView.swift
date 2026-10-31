//
//  LiveWalkthroughView.swift
//  Construction Estimate
//

import SwiftUI
import AVFoundation

// MARK: - Realtime Manager

@Observable
final class RealtimeManager: NSObject {
    var isConnected = false
    var isListening = false
    var aiText = ""
    var statusText = "Connecting…"
    var connectionError: String? = nil

    @ObservationIgnored private var webSocketTask: URLSessionWebSocketTask?
    @ObservationIgnored private let urlSession = URLSession(configuration: .default)
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private let playerNode = AVAudioPlayerNode()
    @ObservationIgnored private var isPlaybackSetUp = false

    // MARK: Connect

    func connect(token: String) {
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        listen()

        sendEvent([
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],
                "instructions": "You are an expert construction estimator. Help the user assess job scope, materials, and labor costs based on what they describe or show you via their camera. Be concise and practical.",
                "voice": "alloy",
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": ["model": "whisper-1"],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 600
                ] as [String: Any]
            ] as [String: Any]
        ])
    }

    func disconnect() {
        stopListening()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        statusText = "Disconnected"
    }

    // MARK: Mic streaming

    func startListening() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { return }

        setupPlayback()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: 24000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else { return }

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self, self.isListening else { return }
            let targetFrames = AVAudioFrameCount(Double(buffer.frameLength) * 24000 / inputFormat.sampleRate)
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrames) else { return }
            var convErr: NSError?
            converter.convert(to: converted, error: &convErr) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            guard convErr == nil, let channel = converted.int16ChannelData else { return }
            let bytes = Data(bytes: channel[0], count: Int(converted.frameLength) * MemoryLayout<Int16>.size)
            self.sendEvent(["type": "input_audio_buffer.append", "audio": bytes.base64EncodedString()])
        }

        if !audioEngine.isRunning { try? audioEngine.start() }
        isListening = true
        statusText = "Listening…"
    }

    func stopListening() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        isListening = false
        if isConnected { statusText = "Ready" }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Snapshot

    func sendSnapshot(_ imageData: Data) {
        let base64 = imageData.base64EncodedString()
        sendEvent([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [["type": "input_image", "image": base64]] as [[String: Any]]
            ] as [String: Any]
        ])
        sendEvent(["type": "response.create"])
    }

    // MARK: Private helpers

    private func sendEvent(_ event: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { _ in }
    }

    private func listen() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                if case .string(let text) = msg,
                   let data = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    DispatchQueue.main.async { self.handle(event: json) }
                }
                self.listen()
            case .failure:
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.statusText = "Connection lost"
                }
            }
        }
    }

    private func handle(event: [String: Any]) {
        switch event["type"] as? String {
        case "session.created", "session.updated":
            isConnected = true
            statusText = "Ready"
        case "response.text.delta":
            if let delta = event["delta"] as? String { aiText += delta }
        case "response.audio.delta":
            if let b64 = event["delta"] as? String, let pcm = Data(base64Encoded: b64) {
                playPCM16(pcm)
            }
        case "response.done":
            statusText = "Ready"
        case "input_audio_buffer.speech_started":
            aiText = ""
            statusText = "Listening…"
        case "error":
            let msg = (event["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            connectionError = msg
        default: break
        }
    }

    // MARK: Audio playback

    private func setupPlayback() {
        guard !isPlaybackSetUp else { return }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
        if !audioEngine.isRunning { try? audioEngine.start() }
        playerNode.play()
        isPlaybackSetUp = true
    }

    private func playPCM16(_ data: Data) {
        let frameCount = data.count / MemoryLayout<Int16>.size
        guard frameCount > 0 else { return }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        data.withUnsafeBytes { rawPtr in
            let src = rawPtr.bindMemory(to: Int16.self)
            if let dst = buffer.floatChannelData?[0] {
                for i in 0..<frameCount { dst[i] = Float(src[i]) / 32768.0 }
            }
        }
        playerNode.scheduleBuffer(buffer)
    }
}

// MARK: - Camera Preview

struct LiveCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.videoLayer.session = session
        v.videoLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Photo Capture Delegate

final class SnapshotDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    var onCapture: ((Data?) -> Void)?
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        onCapture?(photo.fileDataRepresentation())
    }
}

// MARK: - Live Walkthrough View

struct LiveWalkthroughView: View {
    let fetchToken: () async -> String?
    let onDismiss: () -> Void

    @State private var realtimeManager = RealtimeManager()
    @State private var captureSession = AVCaptureSession()
    @State private var photoOutput = AVCapturePhotoOutput()
    @State private var snapshotDelegate = SnapshotDelegate()
    @State private var lastSnapshotThumb: UIImage? = nil
    @State private var deniedPermission: AppProtectedResource?

    private let brandBlue = AppBrand.accent

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LiveCameraPreview(session: captureSession).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                if let err = realtimeManager.connectionError {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.red.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
                if !realtimeManager.aiText.isEmpty { aiResponseBubble }
                bottomControls
            }
        }
        .onAppear {
            setupCamera()
            Task {
                if let token = await fetchToken() {
                    realtimeManager.connect(token: token)
                } else {
                    realtimeManager.connectionError = "Couldn't get session token — check your connection."
                }
            }
        }
        .onDisappear {
            realtimeManager.disconnect()
            captureSession.stopRunning()
        }
        .alert(item: $deniedPermission) { resource in
            Alert(
                title: Text("\(resource.displayName) Access Needed"),
                message: Text(resource.deniedMessage),
                primaryButton: .default(Text("Open Settings")) {
                    AppPermissions.openSettings()
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            HapticButton(action: {
                realtimeManager.disconnect()
                captureSession.stopRunning()
                onDismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }

            Spacer()

            // Status pill
            HStack(spacing: 6) {
                Circle()
                    .fill(realtimeManager.isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(realtimeManager.statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.45))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    // MARK: AI response bubble

    private var aiResponseBubble: some View {
        ScrollView {
            Text(realtimeManager.aiText)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .frame(maxHeight: 180)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: Bottom controls

    private var bottomControls: some View {
        HStack(spacing: 0) {
            // Snapshot button
            HapticButton(action: takeSnapshot) {
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.2)).frame(width: 56, height: 56)
                        Image(systemName: "camera.fill").font(.system(size: 22)).foregroundColor(.white)
                    }
                    Text("Snapshot").font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)

            // Mic / main button
            HapticButton(action: {
                if realtimeManager.isListening {
                    realtimeManager.stopListening()
                } else {
                    Task {
                        if await AppPermissions.request(.microphone) {
                            realtimeManager.startListening()
                        } else {
                            deniedPermission = .microphone
                        }
                    }
                }
            }) {
                ZStack {
                    Circle()
                        .fill(realtimeManager.isListening ? Color.red : brandBlue)
                        .frame(width: 72, height: 72)
                        .shadow(color: (realtimeManager.isListening ? Color.red : brandBlue).opacity(0.5), radius: 12)
                    Image(systemName: realtimeManager.isListening ? "mic.fill" : "mic")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)

            // Last snapshot thumbnail (or placeholder)
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 56, height: 56)
                    if let thumb = lastSnapshotThumb {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Image(systemName: "photo").font(.system(size: 22)).foregroundColor(.white.opacity(0.4))
                    }
                }
                Text("Last sent").font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 60)
    }

    // MARK: Camera setup

    private func setupCamera() {
        let session = captureSession
        let output = photoOutput
        Task.detached(priority: .userInitiated) {
            session.beginConfiguration()
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                session.commitConfiguration()
                return
            }
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            session.startRunning()
        }
    }

    private func takeSnapshot() {
        let settings = AVCapturePhotoSettings()
        snapshotDelegate.onCapture = { data in
            guard let data else { return }
            // Show thumbnail
            if let img = UIImage(data: data) {
                lastSnapshotThumb = img
            }
            realtimeManager.sendSnapshot(data)
        }
        photoOutput.capturePhoto(with: settings, delegate: snapshotDelegate)
    }
}
