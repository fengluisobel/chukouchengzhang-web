import Foundation

struct RemoteEndpointPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let note: String
    let urlString: String?
    let enablesRemote: Bool
}

enum AppConfig {
    /// 首次安装默认先走 Mock，避免地址没配好时直接报错。
    static let defaultUseRemoteAPI = false

    /// iOS 模拟器联调本机服务可先用 127.0.0.1。
    /// 真机调试时请改成宿主机局域网 IP，例如 http://192.168.x.x:4321
    static let defaultBaseURLString = "http://127.0.0.1:4321"

    /// 可选：在宿主工程的 Info.plist 中配置 CKCZReleaseBaseURL，用于一键切到线上环境。
    static var releaseBaseURLString: String? {
        Bundle.main.object(forInfoDictionaryKey: "CKCZReleaseBaseURL") as? String
    }

    static var presets: [RemoteEndpointPreset] {
        var values: [RemoteEndpointPreset] = [
            RemoteEndpointPreset(
                id: "mock",
                title: "Mock 演示",
                note: "不联网，直接看 UI 与流程。",
                urlString: nil,
                enablesRemote: false
            ),
            RemoteEndpointPreset(
                id: "simulator-localhost",
                title: "模拟器联调",
                note: "适合 Xcode 模拟器访问本机 Node 服务。",
                urlString: defaultBaseURLString,
                enablesRemote: true
            )
        ]

        if let releaseBaseURLString, !releaseBaseURLString.isEmpty {
            values.append(
                RemoteEndpointPreset(
                    id: "release",
                    title: "线上正式服",
                    note: "已从 Info.plist 读取 CKCZReleaseBaseURL，可一键切换。",
                    urlString: releaseBaseURLString,
                    enablesRemote: true
                )
            )
        }

        return values
    }
}
