import Foundation

enum SceneType: String, CaseIterable, Identifiable {
    case general = "通用"
    case report = "汇报"
    case pitch = "口播"
    case interview = "面试"
    case idea = "灵感"

    var id: String { rawValue }
}

enum PolishMode: String, CaseIterable, Identifiable {
    case concise = "简洁"
    case formal = "正式"
    case spoken = "口播"
    case executive = "汇报"

    var id: String { rawValue }
}

enum IdeaCategory: String, CaseIterable, Identifiable {
    case product = "产品点子"
    case content = "内容选题"
    case feature = "功能需求"
    case business = "商业模式"
    case hypothesis = "待验证假设"

    var id: String { rawValue }
}

enum TranscriptInputSource: String, Hashable {
    case text
    case speech
    case unknown

    var label: String {
        switch self {
        case .text:
            return "文本"
        case .speech:
            return "语音"
        case .unknown:
            return "未知"
        }
    }
}

struct ExpressionIssue: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let detail: String
}

struct Transcript: Identifiable, Hashable {
    let id = UUID()
    let createdAt: Date
    let scene: SceneType
    let rawText: String
    let polishedText: String
    let mode: PolishMode
    let inputSource: TranscriptInputSource
    let summaryTitle: String?
    let suggestedTags: [String]
    let nextAction: String?
    let provider: String?
    let issues: [ExpressionIssue]

    init(
        createdAt: Date,
        scene: SceneType,
        rawText: String,
        polishedText: String,
        mode: PolishMode,
        inputSource: TranscriptInputSource = .text,
        summaryTitle: String? = nil,
        suggestedTags: [String] = [],
        nextAction: String? = nil,
        provider: String? = nil,
        issues: [ExpressionIssue]
    ) {
        self.createdAt = createdAt
        self.scene = scene
        self.rawText = rawText
        self.polishedText = polishedText
        self.mode = mode
        self.inputSource = inputSource
        self.summaryTitle = summaryTitle
        self.suggestedTags = suggestedTags
        self.nextAction = nextAction
        self.provider = provider
        self.issues = issues
    }
}

struct TrainingAttempt: Identifiable, Hashable {
    let id = UUID()
    let round: Int
    let text: String
    let clarityScore: Int
    let structureScore: Int
    let polishScore: Int
    let feedback: String
}

struct Idea: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let rawInput: String
    let normalizedText: String
    let category: IdeaCategory
    let tags: [String]
    let nextAction: String
    let status: String
    let createdAt: Date
}

struct DailyReport {
    let totalWords: Int
    let transcribeCount: Int
    let trainingCount: Int
    let polishCount: Int
    let catchphraseCount: Int
    let speechInputCount: Int
    let bestSentence: String

    init(
        totalWords: Int,
        transcribeCount: Int,
        trainingCount: Int,
        polishCount: Int,
        catchphraseCount: Int,
        speechInputCount: Int = 0,
        bestSentence: String
    ) {
        self.totalWords = totalWords
        self.transcribeCount = transcribeCount
        self.trainingCount = trainingCount
        self.polishCount = polishCount
        self.catchphraseCount = catchphraseCount
        self.speechInputCount = speechInputCount
        self.bestSentence = bestSentence
    }
}
