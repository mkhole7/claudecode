import Speech
import AVFoundation

class VoiceRecognizer: NSObject, ObservableObject {
    @Published var transcribedText = ""
    @Published var isRecording = false
    @Published var errorMessage: String?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 3.0

    func requestPermission() async -> Bool {
        let micStatus = AVAudioApplication.shared.recordPermission
        if micStatus == .denied { return false }
        if micStatus == .undetermined {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    func startRecording() async {
        guard !audioEngine.isRunning else { return }

        guard await requestPermission() else {
            await MainActor.run { errorMessage = "음성 인식 권한이 필요합니다. 설정에서 허용해 주세요." }
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            await MainActor.run { errorMessage = "오디오 세션을 시작할 수 없습니다." }
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        await MainActor.run {
            isRecording = true
            transcribedText = ""
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcribedText = result.bestTranscription.formattedString
                    // 음성 인식될 때마다 3초 무음 타이머 리셋
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = Timer.scheduledTimer(withTimeInterval: self.silenceTimeout, repeats: false) { [weak self] _ in
                        Task { await self?.stopRecording() }
                    }
                }
            }
            if error != nil || result?.isFinal == true {
                Task { await self.stopRecording() }
            }
        }
    }

    func stopRecording() async {
        guard audioEngine.isRunning else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        await MainActor.run { isRecording = false }
    }
}
