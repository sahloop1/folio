import Foundation
import Combine
import AVFoundation

@MainActor
final class AudioController: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published private(set) var recording = false
    @Published private(set) var playing = false
    @Published var error: String?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var recordingURL: URL?
    private var recorded: ((URL, TimeInterval) async -> Void)?
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private var elapsed: TimeInterval = 0
    private var requestingPermission = false

    func start(onRecorded: @escaping (URL, TimeInterval) async -> Void) async {
        guard recorder == nil && !requestingPermission else { return }
        requestingPermission = true
        defer { requestingPermission = false }
        let permission = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard permission else { error = "Microphone access is off. Enable it for Folio in Settings to record a voice note."; return }
        do {
            stopPlayback()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Folio-recording-" + UUID().uuidString + ".m4a")
            let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            recorder.delegate = self
            guard recorder.record() else { throw NSError(domain: "FolioAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "The microphone could not start recording."]) }
            self.recorder = recorder; recordingURL = url; recorded = onRecorded; elapsed = 0; recording = true
        } catch { self.error = error.localizedDescription }
    }
    func stop() {
        guard recording, let recorder else { return }
        elapsed = recorder.currentTime; recorder.stop(); recording = false
    }
    func finishRecording() async {
        guard recorder != nil else { return }
        await withCheckedContinuation { continuation in finishWaiters.append(continuation); stop() }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.recorder === recorder else { return }
            self.recording = false
            if flag, let url = self.recordingURL { await self.recorded?(url, self.elapsed) }
            else { self.error = "The recording could not be finalized. Any temporary recording file has been retained." }
            self.recorder = nil; self.recordingURL = nil; self.recorded = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            let waiters = self.finishWaiters; self.finishWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }
    func play(_ url: URL) {
        guard recorder == nil else { error = "Finish saving the current recording before playing another note."; return }
        do {
            stopPlayback()
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url); player.delegate = self
            guard player.play() else { throw NSError(domain: "FolioAudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "This recording could not be played."]) }
            self.player = player; playing = true
        } catch { self.error = error.localizedDescription }
    }
    func stopPlayback() { player?.stop(); player = nil; playing = false }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in self.playing = false } }
}
