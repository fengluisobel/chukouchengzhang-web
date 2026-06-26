import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ResultView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let transcript: Transcript

    @State private var localMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(transcript.summaryTitle ?? "原文 / 优化稿")
                        .font(.title2.bold())

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ResultChip(text: transcript.scene.rawValue, systemImage: "tag")
                            ResultChip(text: transcript.mode.rawValue, systemImage: "wand.and.stars")
                            ResultChip(text: transcript.inputSource.label, systemImage: transcript.inputSource == .speech ? "waveform" : "text.alignleft")
                            if let provider = transcript.provider, !provider.isEmpty {
                                ResultChip(text: provider, systemImage: "server.rack")
                            }
                        }
                    }
                }

                if !transcript.suggestedTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(transcript.suggestedTags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    ShareLink(item: transcript.polishedText) {
                        Label("分享优化稿", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        copyPolishedText()
                    } label: {
                        Label("复制优化稿", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if let localMessage {
                    Text(localMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 12) {
                    TextCard(title: "原文", text: transcript.rawText)
                    TextCard(title: "优化稿", text: transcript.polishedText, highlight: true)
                }

                if let nextAction = transcript.nextAction, !nextAction.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("下一步建议")
                            .font(.headline)
                        Text(nextAction)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("表达问题分析")
                        .font(.headline)
                    ForEach(transcript.issues) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.title)
                                .font(.subheadline.bold())
                            Text(issue.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }

                HStack(spacing: 12) {
                    NavigationLink {
                        TrainingView(transcript: transcript)
                    } label: {
                        Label("开始训练", systemImage: "repeat.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button("归档灵感") {
                        Task {
                            viewModel.selectedTranscript = transcript
                            if viewModel.useRemoteAPI {
                                await viewModel.archiveSelectedTranscriptRemotely()
                            } else {
                                viewModel.archiveSelectedTranscriptAsIdea()
                            }
                            localMessage = "已归档到灵感库。"
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoading)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle("结果")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.selectedTranscript = transcript
        }
    }

    private func copyPolishedText() {
        #if canImport(UIKit)
        UIPasteboard.general.string = transcript.polishedText
        localMessage = "优化稿已复制到剪贴板。"
        #else
        localMessage = "当前环境不支持系统剪贴板。"
        #endif
    }
}

private struct TextCard: View {
    let title: String
    let text: String
    var highlight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(highlight ? .orange : .primary)
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight ? Color.orange.opacity(0.12) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ResultChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
    }
}
