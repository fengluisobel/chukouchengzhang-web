import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    @State private var useRemoteAPI = false
    @State private var baseURLString = ""
    @State private var localMessage: String?
    @State private var isTestingConnection = false

    var body: some View {
        Form {
            Section("快速切换") {
                ForEach(AppConfig.presets) { preset in
                    Button {
                        Task {
                            await applyPreset(preset)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(preset.title)
                                Spacer()
                                if viewModel.lastPresetID == preset.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                            Text(preset.note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }

            Section("连接模式") {
                Toggle("启用远端 API", isOn: $useRemoteAPI)
                Text(useRemoteAPI ? "当前将尝试连接你配置的服务地址。" : "当前使用内置 Mock 数据，适合演示 UI。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("服务地址") {
                TextField("http://127.0.0.1:4321", text: $baseURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Text("模拟器可先用 127.0.0.1；真机调试请改成宿主机局域网 IP。若要一键切正式服，请在宿主工程 Info.plist 配置 CKCZReleaseBaseURL。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("状态") {
                LabeledContent("当前模式", value: viewModel.useRemoteAPI ? "远端 API" : "Mock")
                LabeledContent("当前地址", value: viewModel.baseURLString)
                LabeledContent("Provider 状态", value: viewModel.providerStatusText)
                if let lastRemoteSyncAt = viewModel.lastRemoteSyncAt {
                    LabeledContent("最近同步", value: lastRemoteSyncAt.formatted(date: .omitted, time: .shortened))
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if let localMessage {
                    Text(localMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("操作") {
                Button(isTestingConnection ? "正在测试连接…" : "测试连接") {
                    Task {
                        await testConnection()
                    }
                }
                .disabled(isTestingConnection || baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("保存并连接") {
                    Task {
                        await saveAndConnect()
                    }
                }
                .disabled(viewModel.isLoading)

                Button("重新拉取远端数据") {
                    Task {
                        await viewModel.reloadRemoteData()
                        localMessage = "已触发重新拉取。"
                    }
                }
                .disabled(viewModel.isLoading || !viewModel.useRemoteAPI)

                Button("恢复默认设置") {
                    Task {
                        await viewModel.restoreDefaultSettings()
                        syncFromViewModel()
                        localMessage = "已恢复默认设置。"
                    }
                }
                .disabled(viewModel.isLoading)
            }

            Section("接入说明") {
                Text("1. Node 服务默认地址：http://127.0.0.1:4321")
                Text("2. 真机不能用 127.0.0.1，要改成电脑局域网 IP")
                Text("3. 真录音需要 Info.plist 里配置 NSMicrophoneUsageDescription")
                Text("4. 本地 HTTP 联调需要 ATS 例外；正式上线建议切 HTTPS")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("设置")
        .task {
            syncFromViewModel()
        }
    }

    private func syncFromViewModel() {
        useRemoteAPI = viewModel.useRemoteAPI
        baseURLString = viewModel.baseURLString
    }

    private func applyPreset(_ preset: RemoteEndpointPreset) async {
        localMessage = nil
        await viewModel.applyPreset(preset)
        syncFromViewModel()
        localMessage = preset.enablesRemote ? "已切到 \(preset.title)。" : "已切回 Mock 演示模式。"
    }

    private func testConnection() async {
        isTestingConnection = true
        defer { isTestingConnection = false }
        localMessage = await viewModel.testConnection(baseURLString: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func saveAndConnect() async {
        localMessage = nil
        await viewModel.applyRemoteSettings(
            useRemoteAPI: useRemoteAPI,
            baseURLString: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        localMessage = useRemoteAPI ? "设置已保存，已尝试连接远端服务。" : "设置已保存，当前回到 Mock 模式。"
    }
}
