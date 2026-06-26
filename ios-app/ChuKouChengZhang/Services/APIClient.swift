import Foundation

final class APIClient {
    private let settings: RemoteAppSettings
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(settings: RemoteAppSettings) {
        self.settings = settings
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func fetchProviderStatus() async throws -> ProviderStatusDTO {
        guard let baseURL = settings.baseURL else {
            throw APIError.invalidBaseURL(settings.baseURLString)
        }
        return try await Self.request(baseURL: baseURL, path: "/api/provider/status", decoder: decoder)
    }

    func fetchBootstrap() async throws -> BootstrapDTO {
        try await request(path: "/api/bootstrap")
    }

    func probeProviderStatus(baseURLString: String) async throws -> ProviderStatusDTO {
        try await Self.probeProviderStatus(baseURLString: baseURLString, decoder: decoder)
    }

    func fetchTranscripts() async throws -> [TranscriptDTO] {
        try await request(path: "/api/transcripts")
    }

    func createTranscript(rawText: String, scene: SceneType, mode: PolishMode) async throws -> TranscriptDTO {
        let body = CreateTranscriptRequestDTO(
            rawText: rawText,
            scene: scene.serverValue,
            mode: mode.serverValue,
            inputSource: "text",
            captureMeta: nil,
            audioBase64: nil,
            audioMimeType: nil,
            audioName: nil
        )
        return try await request(path: "/api/transcripts/create", method: "POST", body: body)
    }

    func createTranscriptFromAudio(
        audioData: Data,
        fileName: String,
        mimeType: String = "audio/m4a",
        scene: SceneType,
        mode: PolishMode,
        durationSeconds: Double?
    ) async throws -> TranscriptDTO {
        let body = CreateTranscriptRequestDTO(
            rawText: nil,
            scene: scene.serverValue,
            mode: mode.serverValue,
            inputSource: "speech",
            captureMeta: CaptureMetaDTO(durationSeconds: durationSeconds, source: "ios-recorder"),
            audioBase64: audioData.base64EncodedString(),
            audioMimeType: mimeType,
            audioName: fileName
        )
        return try await request(path: "/api/transcripts/create", method: "POST", body: body)
    }

    func transcribeAudio(
        audioData: Data,
        fileName: String,
        mimeType: String = "audio/m4a",
        scene: SceneType,
        durationSeconds: Double?
    ) async throws -> TranscriptionResultDTO {
        let body = TranscribeAudioRequestDTO(
            rawText: "",
            scene: scene.serverValue,
            inputSource: "speech",
            captureMeta: CaptureMetaDTO(durationSeconds: durationSeconds, source: "ios-recorder"),
            audioBase64: audioData.base64EncodedString(),
            audioMimeType: mimeType,
            audioName: fileName
        )
        return try await request(path: "/api/transcribe", method: "POST", body: body)
    }

    func fetchTrainingAttempts(transcriptId: String) async throws -> [TrainingAttemptDTO] {
        let safeId = transcriptId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? transcriptId
        return try await request(path: "/api/training?transcriptId=\(safeId)")
    }

    func evaluateTraining(transcriptId: String, attemptText: String, round: Int) async throws -> TrainingAttemptDTO {
        let body = EvaluateTrainingRequestDTO(transcriptId: transcriptId, attemptText: attemptText, round: round)
        return try await request(path: "/api/train/evaluate", method: "POST", body: body)
    }

    func fetchIdeas() async throws -> [IdeaDTO] {
        try await request(path: "/api/ideas")
    }

    func archiveIdea(transcriptId: String) async throws -> IdeaDTO {
        let body = ArchiveIdeaRequestDTO(transcriptId: transcriptId)
        return try await request(path: "/api/ideas/archive", method: "POST", body: body)
    }

    func fetchDailyReport() async throws -> DailyReportDTO {
        try await request(path: "/api/reports/daily")
    }

    private func request<T: Decodable>(path: String, method: String = "GET") async throws -> T {
        try await request(path: path, method: method, body: Optional<Data>.none)
    }

    private func request<T: Decodable, B: Encodable>(path: String, method: String, body: B?) async throws -> T {
        let bodyData = try body.map { try encoder.encode($0) }
        return try await request(path: path, method: method, body: bodyData)
    }

    private func request<T: Decodable>(path: String, method: String, body: Data?) async throws -> T {
        guard let baseURL = settings.baseURL else {
            throw APIError.invalidBaseURL(settings.baseURLString)
        }
        return try await Self.request(baseURL: baseURL, path: path, method: method, body: body, decoder: decoder)
    }

    static func probeProviderStatus(baseURLString: String, decoder: JSONDecoder = JSONDecoder()) async throws -> ProviderStatusDTO {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: trimmed) else {
            throw APIError.invalidBaseURL(baseURLString)
        }
        return try await request(baseURL: baseURL, path: "/api/provider/status", decoder: decoder)
    }

    private static func request<T: Decodable>(
        baseURL: URL,
        path: String,
        method: String = "GET",
        body: Data? = nil,
        decoder: JSONDecoder
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw APIError.network(error)
        } catch {
            throw APIError.unknown(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw APIError.server(message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decode(error.localizedDescription)
        }
    }
}

enum APIError: Error, LocalizedError {
    case invalidBaseURL(String)
    case invalidURL(String)
    case invalidResponse
    case network(URLError)
    case server(String)
    case decode(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let value):
            return "无效服务地址：\(value)"
        case .invalidURL(let path):
            return "无效 URL：\(path)"
        case .invalidResponse:
            return "服务返回了无效响应。"
        case .network(let error):
            switch error.code {
            case .timedOut:
                return "连接服务超时了，请检查网络或服务状态。"
            case .notConnectedToInternet:
                return "当前网络不可用，请检查设备联网状态。"
            case .cannotFindHost, .cannotConnectToHost:
                return "连不上这个服务地址，请确认服务已启动且手机能访问它。"
            default:
                return "网络请求失败：\(error.localizedDescription)"
            }
        case .server(let message):
            return "服务错误：\(message)"
        case .decode(let message):
            return "解析失败：\(message)"
        case .unknown(let message):
            return "请求失败：\(message)"
        }
    }
}
