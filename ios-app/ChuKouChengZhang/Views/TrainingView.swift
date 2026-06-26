import SwiftUI

struct TrainingView: View {
    private enum InputMode: String, CaseIterable, Identifiable {
        case text = "文本"
        case voice = "语音"
        var id: String { rawValue }
    }

    @EnvironmentObject private var viewModel: AppViewModel
    let transcript: Transcript

    @StateObject private var recorder = AudioRecorderService()
    @State private var attemptText: String = ""
    @State private var inputMode: InputMode = .text
    @State private var localMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("训练模式")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 8) {
                    Text("标准稿")
                        .font(.headline)
                    Text(transcript.polishedText)
                        .padding()
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                if viewModel.useRemoteAPI {
                    Picker("训练输入", selection: $inputMode) {
                        ForEach(InputMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if viewModel.useRemoteAPI && inputMode == .voice {
                    voiceTrainingSection
                } else {
                    textTrainingSection
                }

                if let localMessage {
                    Text(localMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("训练结果")
                        .font(.headline)
                    if viewModel.trainingAttempts.isEmpty {
                        Text("还没有训练结果，先来一轮。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.trainingAttempts) { attempt in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("第 \(attempt.round) 轮")
                                    .font(.headline)
                                Spacer()
                                Text("清晰度 \(attempt.clarityScore)")
                                    .foregroundStyle(.orange)
                            }
                            Text(attempt.text)
                            HStack {
                                Label("结构 \(attempt.structureScore)", systemImage: "square.split.2x1")
                                Label("成章 \(attempt.polishScore)", systemImage: "sparkles")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text(attempt.feedback)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle("表达训练")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            recorder.refreshPermissionState()
            await viewModel.loadTrainingAttemptsIfNeeded(for: transcript)
        }
    }

    private var textTrainingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("你的复述稿")
                .font(.headline)
            TextEditor(text: $attemptText)
                .frame(minHeight: 140)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            HStack {
                Button("填入示例复述") {
                    attemptText = "这个产品的核心是把用户的口头表达整理成更清晰的内容，再通过复述训练帮助用户持续提升表达能力。"
                }
                .buttonStyle(.bordered)

                Button("生成训练评分") {
                    Task {
                        await submitTextAttempt()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(attemptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            }
        }
    }

    private var voiceTrainingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("语音复述")
                .font(.headline)
            Text("录完后直接走转写 + 训练评分，不用你手动抄文字。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                Circle()
                    .fill(recorder.isRecording ? .red : .orange)
                    .frame(width: 140, height: 140)
                    .overlay {
                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .onTapGesture {
                        Task {
                            await toggleRecording()
                        }
                    }

                Text(recorder.isRecording ? "录音中…再次点击结束" : "点击开始复述")
                    .foregroundStyle(.secondary)

                Text(Self.durationText(recorder.duration))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(recorder.isRecording ? .red : .primary)

                if recorder.recordedFileURL != nil {
                    Button(recorder.isPlaying ? "停止试听" : "试听复述") {
                        do {
                            try recorder.togglePlayback()
                        } catch {
                            localMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Button("上传语音并评分") {
                    Task {
                        await submitVoiceAttempt()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(recorder.recordedFileURL == nil || viewModel.isLoading)

                if recorder.permissionState == .denied {
                    Text("麦克风权限没开，去 iPhone 设置里打开后再回来。")
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if recorder.isPlaying {
                    Text("正在试听复述录音。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private func toggleRecording() async {
        localMessage = nil

        if recorder.isRecording {
            recorder.stopRecording()
            localMessage = "复述录好了，可以直接上传评分。"
            return
        }

        do {
            try await recorder.startRecording()
            localMessage = "开始复述。"
        } catch {
            localMessage = error.localizedDescription
        }
    }

    private func submitTextAttempt() async {
        let text = attemptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await viewModel.evaluateTrainingRemotely(attemptText: text)
        if viewModel.errorMessage == nil {
            attemptText = ""
        }
    }

    private func submitVoiceAttempt() async {
        do {
            recorder.stopPlayback()
            let audioData = try recorder.recordedAudioData()
            await viewModel.evaluateTrainingRemotely(
                audioData: audioData,
                fileName: recorder.recordedFileName,
                durationSeconds: recorder.duration,
                scene: transcript.scene
            )
            if viewModel.errorMessage == nil {
                recorder.discardRecording()
            }
        } catch {
            localMessage = error.localizedDescription
        }
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
