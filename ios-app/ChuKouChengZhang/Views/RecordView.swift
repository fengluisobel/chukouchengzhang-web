import SwiftUI

struct RecordView: View {
    private enum InputMode: String, CaseIterable, Identifiable {
        case voice = "语音"
        case text = "文本"
        var id: String { rawValue }
    }

    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = AudioRecorderService()

    @State private var selectedScene: SceneType = .idea
    @State private var selectedMode: PolishMode = .concise
    @State private var draftText: String = ""
    @State private var inputMode: InputMode = .voice
    @State private var localMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("录一段你的表达")
                    .font(.title2.bold())

                Picker("场景", selection: $selectedScene) {
                    ForEach(SceneType.allCases) { scene in
                        Text(scene.rawValue).tag(scene)
                    }
                }
                .pickerStyle(.segmented)

                Picker("风格", selection: $selectedMode) {
                    ForEach(PolishMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.useRemoteAPI {
                    Picker("输入方式", selection: $inputMode) {
                        ForEach(InputMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if shouldShowVoiceRecorder {
                    voiceRecorderSection
                }

                if shouldShowVoiceRecorder {
                    if recorder.recordedFileURL != nil {
                        HStack {
                            Button(recorder.isPlaying ? "停止试听" : "试听录音") {
                                do {
                                    try recorder.togglePlayback()
                                } catch {
                                    localMessage = error.localizedDescription
                                }
                            }
                            .buttonStyle(.bordered)

                            Button("删除录音") {
                                recorder.discardRecording()
                                localMessage = "已删除刚才那段录音。"
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(textSectionTitle)
                            .font(.headline)
                        Text(viewModel.useRemoteAPI ? "你可以直接粘文字，或者切到“语音”模式录真音频。" : "当前是 Mock 模式，会基于你输入的内容本地生成一版结果，方便先把流程跑顺。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $draftText)
                            .frame(minHeight: 180)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    Button("填入 Demo 示例") {
                        draftText = MockDataService.sampleTranscript.rawText
                        inputMode = .text
                    }
                    .buttonStyle(.bordered)
                }

                Button(submitButtonTitle) {
                    Task {
                        await submitTranscript()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isSubmitDisabled)

                if let localMessage {
                    Text(localMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle("开始录音")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            recorder.refreshPermissionState()
            if !viewModel.useRemoteAPI {
                inputMode = .text
            }
        }
    }

    private var shouldShowVoiceRecorder: Bool {
        viewModel.useRemoteAPI && inputMode == .voice
    }

    private var isSubmitDisabled: Bool {
        if viewModel.isLoading { return true }
        if shouldShowVoiceRecorder {
            return recorder.recordedFileURL == nil
        }
        return draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var submitButtonTitle: String {
        shouldShowVoiceRecorder ? "上传录音并生成结果" : "生成转写与优化稿"
    }

    private var textSectionTitle: String {
        shouldShowVoiceRecorder ? "文本补录（可选）" : "表达内容"
    }

    private var voiceRecorderSection: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(recorder.isRecording ? .red : .orange)
                .frame(width: 160, height: 160)
                .overlay {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(.white)
                }
                .onTapGesture {
                    Task {
                        await toggleRecording()
                    }
                }

            Text(recorder.isRecording ? "录音中…再次点击结束" : "点击开始录音")
                .foregroundStyle(.secondary)

            Text(Self.durationText(recorder.duration))
                .font(.title3.monospacedDigit())
                .foregroundStyle(recorder.isRecording ? .red : .primary)

            if recorder.isPlaying {
                Label("正在试听录音", systemImage: "waveform")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if recorder.permissionState == .denied {
                Text("麦克风权限被拒绝了。去 iPhone 设置里打开后，再回来录。")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if recorder.recordedFileURL != nil {
                Text("录音已就绪，点下方按钮就能直接走转写与优化。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func toggleRecording() async {
        localMessage = nil

        if recorder.isRecording {
            recorder.stopRecording()
            localMessage = "录音结束，可直接上传。"
            return
        }

        do {
            try await recorder.startRecording()
            localMessage = "开始录音了。"
        } catch {
            localMessage = error.localizedDescription
        }
    }

    private func submitTranscript() async {
        localMessage = nil
        viewModel.errorMessage = nil

        if shouldShowVoiceRecorder {
            do {
                recorder.stopPlayback()
                let audioData = try recorder.recordedAudioData()
                await viewModel.createRemoteTranscriptFromAudio(
                    audioData: audioData,
                    fileName: recorder.recordedFileName,
                    scene: selectedScene,
                    mode: selectedMode,
                    durationSeconds: recorder.duration
                )
            } catch {
                localMessage = error.localizedDescription
            }
        } else {
            let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }

            if viewModel.useRemoteAPI {
                await viewModel.createRemoteTranscript(rawText: text, scene: selectedScene, mode: selectedMode)
            } else {
                viewModel.createMockTranscript(rawText: text, scene: selectedScene, mode: selectedMode)
            }
        }

        if viewModel.errorMessage == nil {
            recorder.discardRecording()
            dismiss()
        }
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
