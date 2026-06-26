import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("出口成章")
                        .font(.largeTitle.bold())
                    Text("把随口一说，变成清晰表达")
                        .foregroundStyle(.secondary)
                }

                connectionCard

                VStack(alignment: .leading, spacing: 12) {
                    Text("今日概览")
                        .font(.headline)
                    HStack {
                        StatCard(title: "今日字数", value: "\(viewModel.report.totalWords)")
                        StatCard(title: "训练次数", value: "\(viewModel.report.trainingCount)")
                    }
                    if viewModel.useRemoteAPI {
                        HStack {
                            StatCard(title: "转写次数", value: "\(viewModel.report.transcribeCount)")
                            StatCard(title: "优化次数", value: "\(viewModel.report.polishCount)")
                        }
                    }
                }

                NavigationLink {
                    RecordView()
                } label: {
                    Label(viewModel.useRemoteAPI ? "开始录音 / 转写" : "开始演练", systemImage: "mic.circle.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("最近内容")
                        .font(.headline)

                    if viewModel.transcripts.isEmpty {
                        Text("还没有内容，先录一段。")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.transcripts.prefix(5)) { transcript in
                        NavigationLink {
                            ResultView(transcript: transcript)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(transcript.summaryTitle ?? transcript.scene.rawValue)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(transcript.polishedText)
                                            .lineLimit(2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(transcript.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 8) {
                                    RecentBadge(text: transcript.scene.rawValue, color: .orange)
                                    RecentBadge(text: transcript.inputSource.label, color: transcript.inputSource == .speech ? .blue : .gray)
                                    if let provider = transcript.provider, !provider.isEmpty {
                                        RecentBadge(text: provider, color: .purple)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            viewModel.selectedTranscript = transcript
                        })
                    }
                }
            }
            .padding()
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.isLoading {
                ProgressView()
                    .padding(12)
            }
        }
        .task {
            await viewModel.loadRemoteBootstrapIfNeeded()
        }
    }

    @ViewBuilder
    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("当前模式")
                    .font(.headline)
                Spacer()
                Text(viewModel.useRemoteAPI ? "远端 API" : "Mock")
                    .font(.subheadline.bold())
                    .foregroundStyle(viewModel.useRemoteAPI ? .orange : .secondary)
            }

            Text(viewModel.providerStatusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.useRemoteAPI {
                Text(viewModel.baseURLString)
                    .font(.caption)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let lastRemoteSyncAt = viewModel.lastRemoteSyncAt {
                Text("最近同步：\(lastRemoteSyncAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                SettingsView()
            } label: {
                Label("去设置连接与录音权限", systemImage: "slider.horizontal.3")
                    .font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct RecentBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
