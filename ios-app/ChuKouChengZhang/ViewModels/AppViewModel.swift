import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var transcripts: [Transcript] = [MockDataService.sampleTranscript]
    @Published var selectedTranscript: Transcript? = MockDataService.sampleTranscript
    @Published var trainingAttempts: [TrainingAttempt] = MockDataService.trainingAttempts
    @Published var ideas: [Idea] = MockDataService.ideas
    @Published var report: DailyReport = MockDataService.report
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var providerStatusText: String = "Mock 模式"
    @Published var lastRemoteSyncAt: Date?

    let settings: RemoteAppSettings
    private let apiClient: APIClient
    private var transcriptServerIDs: [UUID: String] = [:]
    private var selectedTranscriptServerID: String?
    private var hasAttemptedRemoteBootstrap = false

    convenience init() {
        self.init(settings: RemoteAppSettings())
    }

    init(settings: RemoteAppSettings) {
        self.settings = settings
        self.apiClient = APIClient(settings: settings)
    }

    var useRemoteAPI: Bool {
        settings.useRemoteAPI
    }

    var baseURLString: String {
        settings.baseURLString
    }

    var lastPresetID: String? {
        settings.lastPresetID
    }

    func applyPreset(_ preset: RemoteEndpointPreset) async {
        settings.applyPreset(preset)
        await applyRemoteSettings(useRemoteAPI: preset.enablesRemote, baseURLString: settings.baseURLString)
    }

    func applyRemoteSettings(useRemoteAPI: Bool, baseURLString: String) async {
        settings.useRemoteAPI = useRemoteAPI
        settings.baseURLString = baseURLString
        hasAttemptedRemoteBootstrap = false
        errorMessage = nil
        providerStatusText = useRemoteAPI ? "远端模式待连接" : "Mock 模式"

        if useRemoteAPI {
            await loadRemoteBootstrap()
        } else {
            loadMockSnapshot()
        }
    }

    func restoreDefaultSettings() async {
        settings.applyDefaults()
        hasAttemptedRemoteBootstrap = false
        if settings.useRemoteAPI {
            await loadRemoteBootstrap()
        } else {
            loadMockSnapshot()
        }
    }

    func testConnection(baseURLString: String) async -> String {
        do {
            let result = try await apiClient.probeProviderStatus(baseURLString: baseURLString)
            return result.ok
                ? "连接成功：远端 Provider = \(result.provider)"
                : "服务可达，但 Provider 状态异常"
        } catch {
            return error.localizedDescription
        }
    }

    func loadRemoteBootstrapIfNeeded() async {
        guard useRemoteAPI, !hasAttemptedRemoteBootstrap else { return }
        hasAttemptedRemoteBootstrap = true
        await loadRemoteBootstrap()
    }

    func reloadRemoteData() async {
        hasAttemptedRemoteBootstrap = false
        await loadRemoteBootstrapIfNeeded()
    }

    func loadRemoteBootstrap() async {
        guard useRemoteAPI else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let bootstrap = try await apiClient.fetchBootstrap()
            let providerResult = bootstrap.providerStatus

            providerStatusText = providerResult.ok ? "远端 Provider：\(providerResult.provider)" : "远端 Provider 异常"
            lastRemoteSyncAt = Date()

            transcriptServerIDs = [:]
            transcripts = bootstrap.transcripts.map { dto in
                let model = dto.toDomain()
                transcriptServerIDs[model.id] = dto.id
                return model
            }
            selectedTranscript = transcripts.first
            selectedTranscriptServerID = selectedTranscript.flatMap { transcriptServerIDs[$0.id] }

            ideas = bootstrap.ideas.map { $0.toDomain() }
            report = bootstrap.report.toDomain()

            if let transcriptId = selectedTranscriptServerID {
                let attempts = try await apiClient.fetchTrainingAttempts(transcriptId: transcriptId)
                trainingAttempts = attempts.map { $0.toDomain() }
            } else {
                trainingAttempts = []
            }
        } catch {
            if transcripts.isEmpty {
                loadMockSnapshot(clearError: false)
            }
            errorMessage = error.localizedDescription
            providerStatusText = "远端连接失败，当前先展示本地数据"
        }
    }

    func loadMockSnapshot(clearError: Bool = true) {
        transcripts = [MockDataService.sampleTranscript]
        selectedTranscript = MockDataService.sampleTranscript
        trainingAttempts = MockDataService.trainingAttempts
        ideas = MockDataService.ideas
        report = MockDataService.report
        providerStatusText = "Mock 模式"
        if clearError {
            errorMessage = nil
        }
        lastRemoteSyncAt = nil
        transcriptServerIDs = [:]
        selectedTranscriptServerID = nil
    }

    func createMockTranscript(rawText: String, scene: SceneType, mode: PolishMode = .concise) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceText = trimmed.isEmpty ? MockDataService.sampleTranscript.rawText : trimmed
        let transcript = Transcript(
            createdAt: Date(),
            scene: scene,
            rawText: sourceText,
            polishedText: Self.mockPolishText(from: sourceText, scene: scene, mode: mode),
            mode: mode,
            inputSource: .text,
            summaryTitle: Self.mockSummaryTitle(from: sourceText, scene: scene),
            suggestedTags: Self.mockTags(scene: scene, text: sourceText),
            nextAction: "当前是 Mock 模式。切到远端 API 后，就能拿到真实转写、优化和训练评分。",
            provider: "mock-local",
            issues: Self.mockIssues(from: sourceText)
        )
        transcripts.insert(transcript, at: 0)
        selectedTranscript = transcript
        selectedTranscriptServerID = nil
        trainingAttempts = []
        errorMessage = nil
        providerStatusText = "Mock 模式"
        lastRemoteSyncAt = nil
    }

    func createRemoteTranscript(rawText: String, scene: SceneType, mode: PolishMode = .concise) async {
        guard useRemoteAPI else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let dto = try await apiClient.createTranscript(rawText: rawText, scene: scene, mode: mode)
            let transcript = dto.toDomain()
            transcripts.insert(transcript, at: 0)
            transcriptServerIDs[transcript.id] = dto.id
            selectedTranscript = transcript
            selectedTranscriptServerID = dto.id
            trainingAttempts = []
            await loadReport()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createRemoteTranscriptFromAudio(
        audioData: Data,
        fileName: String,
        mimeType: String = "audio/m4a",
        scene: SceneType,
        mode: PolishMode = .concise,
        durationSeconds: Double?
    ) async {
        guard useRemoteAPI else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let dto = try await apiClient.createTranscriptFromAudio(
                audioData: audioData,
                fileName: fileName,
                mimeType: mimeType,
                scene: scene,
                mode: mode,
                durationSeconds: durationSeconds
            )
            let transcript = dto.toDomain()
            transcripts.insert(transcript, at: 0)
            transcriptServerIDs[transcript.id] = dto.id
            selectedTranscript = transcript
            selectedTranscriptServerID = dto.id
            trainingAttempts = []
            await loadReport()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTrainingAttemptsIfNeeded(for transcript: Transcript) async {
        selectedTranscript = transcript

        guard useRemoteAPI else { return }
        guard let transcriptId = transcriptServerIDs[transcript.id] else { return }

        do {
            let attempts = try await apiClient.fetchTrainingAttempts(transcriptId: transcriptId)
            trainingAttempts = attempts.map { $0.toDomain() }
            selectedTranscriptServerID = transcriptId
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func evaluateTrainingRemotely(attemptText: String) async {
        guard useRemoteAPI else { return }
        guard let transcriptId = selectedTranscriptServerID else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let dto = try await apiClient.evaluateTraining(
                transcriptId: transcriptId,
                attemptText: attemptText,
                round: trainingAttempts.count + 1
            )
            trainingAttempts.insert(dto.toDomain(), at: 0)
            await loadReport()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func evaluateTrainingRemotely(
        audioData: Data,
        fileName: String,
        mimeType: String = "audio/m4a",
        durationSeconds: Double?,
        scene: SceneType
    ) async {
        guard useRemoteAPI else { return }
        guard let transcriptId = selectedTranscriptServerID else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let transcribed = try await apiClient.transcribeAudio(
                audioData: audioData,
                fileName: fileName,
                mimeType: mimeType,
                scene: scene,
                durationSeconds: durationSeconds
            )

            let attemptText = transcribed.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !attemptText.isEmpty else {
                errorMessage = "语音已上传，但没有转出可用文字，请重试。"
                return
            }

            let dto = try await apiClient.evaluateTraining(
                transcriptId: transcriptId,
                attemptText: attemptText,
                round: trainingAttempts.count + 1
            )
            trainingAttempts.insert(dto.toDomain(), at: 0)
            await loadReport()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func archiveSelectedTranscriptAsIdea() {
        guard let transcript = selectedTranscript else { return }
        let idea = Idea(
            title: transcript.summaryTitle ?? "新的产品灵感",
            rawInput: transcript.rawText,
            normalizedText: transcript.polishedText,
            category: .product,
            tags: transcript.suggestedTags.isEmpty ? ["自动归档", transcript.scene.rawValue] : transcript.suggestedTags,
            nextAction: transcript.nextAction ?? "补充验证路径与 Demo",
            status: "新收录",
            createdAt: Date()
        )
        ideas.insert(idea, at: 0)
    }

    func archiveSelectedTranscriptRemotely() async {
        guard useRemoteAPI else { return }
        guard let transcript = selectedTranscript, let transcriptId = transcriptServerIDs[transcript.id] else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let dto = try await apiClient.archiveIdea(transcriptId: transcriptId)
            ideas.insert(dto.toDomain(), at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadIdeas() async {
        guard useRemoteAPI else { return }
        do {
            let ideaDTOs = try await apiClient.fetchIdeas()
            ideas = ideaDTOs.map { $0.toDomain() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadReport() async {
        guard useRemoteAPI else { return }
        do {
            let dto = try await apiClient.fetchDailyReport()
            report = dto.toDomain()
            lastRemoteSyncAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension AppViewModel {
    static func mockSummaryTitle(from text: String, scene: SceneType) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fragments = cleaned.components(separatedBy: CharacterSet(charactersIn: "，。！？；"))
        let first = fragments.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.trimmingCharacters(in: .whitespacesAndNewlines)
        return first.map { "\(scene.rawValue)：\($0.prefix(18))" } ?? "\(scene.rawValue)表达整理"
    }

    static func mockPolishText(from text: String, scene: SceneType, mode: PolishMode) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "【\(scene.rawValue) / \(mode.rawValue)】"
        if trimmed.isEmpty {
            return "\(prefix) 先说结论，再补充背景和下一步，这样表达会更稳。"
        }

        return "\(prefix) \(trimmed) 建议把表达整理成三段：先亮结论，再讲关键依据，最后给出明确下一步。"
    }

    static func mockIssues(from text: String) -> [ExpressionIssue] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let characterCount = trimmed.count
        var items: [ExpressionIssue] = []

        if characterCount > 45 {
            items.append(ExpressionIssue(title: "句子偏长", detail: "信息一次塞太多了，建议拆成 2-3 句。"))
        }

        items.append(ExpressionIssue(title: "结论不够靠前", detail: "先把最重要的一句顶到前面，听的人会更容易跟上。"))

        if !trimmed.contains("下一步") {
            items.append(ExpressionIssue(title: "缺少动作收口", detail: "结尾可以补一句“下一步做什么”，表达会更像完成稿。"))
        }

        return items
    }

    static func mockTags(scene: SceneType, text: String) -> [String] {
        var tags = [scene.rawValue, "Mock 生成"]
        if text.contains("产品") {
            tags.append("产品表达")
        }
        if text.contains("汇报") {
            tags.append("工作汇报")
        }
        return tags
    }
}
