import Foundation
import Combine
import AVFoundation

@MainActor
final class AudioRecorderService: NSObject, ObservableObject {
    enum PermissionState: Equatable {
        case undetermined
        case denied
        case granted
    }

    enum RecorderError: LocalizedError {
        case permissionDenied
        case recorderUnavailable
        case playbackUnavailable
        case fileMissing

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "没有麦克风权限，请先到系统设置里允许录音。"
            case .recorderUnavailable:
                return "录音器初始化失败，请重试。"
            case .playbackUnavailable:
                return "录音播放失败，请重新录一段试试。"
            case .fileMissing:
                return "没有找到录音文件，请重新录一段。"
            }
        }
    }

    @Published private(set) var permissionState: PermissionState = .undetermined
    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var recordedFileURL: URL?

    private var recorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    override init() {
        super.init()
        refreshPermissionState()
    }

    func refreshPermissionState() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            permissionState = .granted
        case .denied:
            permissionState = .denied
        case .undetermined:
            permissionState = .undetermined
        @unknown default:
            permissionState = .undetermined
        }
    }

    func requestPermissionIfNeeded() async -> Bool {
        refreshPermissionState()
        if permissionState == .granted {
            return true
        }

        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }

        permissionState = granted ? .granted : .denied
        return granted
    }

    func startRecording() async throws {
        let granted = await requestPermissionIfNeeded()
        guard granted else {
            throw RecorderError.permissionDenied
        }

        stopPlayback()
        try configureSessionForRecording()

        let url = Self.makeRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw RecorderError.recorderUnavailable
        }

        self.recorder = recorder
        self.recordedFileURL = url
        self.duration = 0
        self.isRecording = true
        startTimer()
    }

    func stopRecording() {
        recorder?.stop()
        isRecording = false
        duration = recorder?.currentTime ?? duration
        recorder = nil
        stopTimer()
        deactivateSessionIfPossible()
    }

    func togglePlayback() throws {
        if isPlaying {
            stopPlayback()
        } else {
            try startPlayback()
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        deactivateSessionIfPossible()
    }

    func discardRecording() {
        if isRecording {
            stopRecording()
        }
        stopPlayback()

        if let recordedFileURL {
            try? FileManager.default.removeItem(at: recordedFileURL)
        }
        self.recordedFileURL = nil
        self.duration = 0
    }

    func recordedAudioData() throws -> Data {
        guard let recordedFileURL else {
            throw RecorderError.fileMissing
        }
        return try Data(contentsOf: recordedFileURL)
    }

    var recordedFileName: String {
        recordedFileURL?.lastPathComponent ?? "recording.m4a"
    }

    private func startPlayback() throws {
        guard let recordedFileURL else {
            throw RecorderError.fileMissing
        }

        if isRecording {
            stopRecording()
        }

        try configureSessionForPlayback()
        let player = try AVAudioPlayer(contentsOf: recordedFileURL)
        player.delegate = self
        player.prepareToPlay()
        guard player.play() else {
            throw RecorderError.playbackUnavailable
        }
        audioPlayer = player
        isPlaying = true
    }

    private func configureSessionForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func configureSessionForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func deactivateSessionIfPossible() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.duration = self.recorder?.currentTime ?? self.duration
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private static func makeRecordingURL() -> URL {
        let fileName = "ckcz-recording-\(UUID().uuidString).m4a"
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }
}

extension AudioRecorderService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.audioPlayer = nil
            self.isPlaying = false
            self.deactivateSessionIfPossible()
        }
    }
}
