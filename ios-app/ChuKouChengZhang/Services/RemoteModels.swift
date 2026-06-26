import Foundation

struct ProviderStatusDTO: Decodable {
    let ok: Bool
    let provider: String
    let checkedAt: String?
}

struct BootstrapDTO: Decodable {
    let providerStatus: ProviderStatusDTO
    let transcripts: [TranscriptDTO]
    let ideas: [IdeaDTO]
    let report: DailyReportDTO
}

struct DailyReportDTO: Decodable {
    let totalWords: Int
    let transcribeCount: Int
    let trainingCount: Int
    let polishCount: Int
    let catchphraseCount: Int
    let speechInputCount: Int?
    let bestSentence: String
}

struct CaptureMetaDTO: Codable {
    let durationSeconds: Double?
    let source: String?

    init(durationSeconds: Double? = nil, source: String? = nil) {
        self.durationSeconds = durationSeconds
        self.source = source
    }
}

struct AudioMetaDTO: Decodable {
    let mimeType: String?
    let fileName: String?
    let fileSizeBytes: Int?
}

struct TranscriptionSegmentDTO: Decodable {
    let start: Double?
    let end: Double?
    let text: String?
}

struct TranscriptionResultDTO: Decodable {
    let text: String
    let language: String
    let duration: Double?
    let wordCount: Int?
    let scene: String
    let inputSource: String
    let captureMeta: CaptureMetaDTO?
    let provider: String
    let audioMeta: AudioMetaDTO?
    let segments: [TranscriptionSegmentDTO]
}

struct ExpressionIssueDTO: Decodable {
    let title: String
    let detail: String
}

struct TranscriptDTO: Decodable {
    let id: String
    let createdAt: String
    let scene: String
    let mode: String
    let inputSource: String?
    let rawText: String
    let polishedText: String
    let summaryTitle: String?
    let suggestedTags: [String]?
    let nextAction: String?
    let issues: [ExpressionIssueDTO]
    let provider: String?
}

struct CreateTranscriptRequestDTO: Encodable {
    let rawText: String?
    let scene: String
    let mode: String
    let inputSource: String
    let captureMeta: CaptureMetaDTO?
    let audioBase64: String?
    let audioMimeType: String?
    let audioName: String?
}

struct TranscribeAudioRequestDTO: Encodable {
    let rawText: String
    let scene: String
    let inputSource: String
    let captureMeta: CaptureMetaDTO?
    let audioBase64: String
    let audioMimeType: String?
    let audioName: String?
}

struct TrainingAttemptDTO: Decodable {
    let id: String
    let transcriptId: String
    let round: Int
    let text: String
    let clarityScore: Int
    let structureScore: Int
    let polishScore: Int
    let feedback: String
}

struct EvaluateTrainingRequestDTO: Encodable {
    let transcriptId: String
    let attemptText: String
    let round: Int
}

struct IdeaDTO: Decodable {
    let id: String
    let transcriptId: String
    let title: String
    let rawInput: String
    let normalizedText: String
    let category: String
    let tags: [String]
    let nextAction: String
    let status: String
    let createdAt: String
}

struct ArchiveIdeaRequestDTO: Encodable {
    let transcriptId: String
}

extension TranscriptDTO {
    func toDomain() -> Transcript {
        Transcript(
            createdAt: Self.parseDate(createdAt),
            scene: SceneType(serverValue: scene),
            rawText: rawText,
            polishedText: polishedText,
            mode: PolishMode(serverValue: mode),
            inputSource: TranscriptInputSource(serverValue: inputSource),
            summaryTitle: summaryTitle,
            suggestedTags: suggestedTags ?? [],
            nextAction: nextAction,
            provider: provider,
            issues: issues.map { ExpressionIssue(title: $0.title, detail: $0.detail) }
        )
    }

    private static func parseDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? Date()
    }
}

extension TrainingAttemptDTO {
    func toDomain() -> TrainingAttempt {
        TrainingAttempt(
            round: round,
            text: text,
            clarityScore: clarityScore,
            structureScore: structureScore,
            polishScore: polishScore,
            feedback: feedback
        )
    }
}

extension IdeaDTO {
    func toDomain() -> Idea {
        Idea(
            title: title,
            rawInput: rawInput,
            normalizedText: normalizedText,
            category: IdeaCategory(serverValue: category),
            tags: tags,
            nextAction: nextAction,
            status: status,
            createdAt: ISO8601DateFormatter().date(from: createdAt) ?? Date()
        )
    }
}

extension DailyReportDTO {
    func toDomain() -> DailyReport {
        DailyReport(
            totalWords: totalWords,
            transcribeCount: transcribeCount,
            trainingCount: trainingCount,
            polishCount: polishCount,
            catchphraseCount: catchphraseCount,
            speechInputCount: speechInputCount ?? 0,
            bestSentence: bestSentence
        )
    }
}

extension SceneType {
    init(serverValue: String) {
        switch serverValue {
        case "general": self = .general
        case "report": self = .report
        case "pitch": self = .pitch
        case "interview": self = .interview
        case "idea": self = .idea
        default: self = .general
        }
    }

    var serverValue: String {
        switch self {
        case .general: return "general"
        case .report: return "report"
        case .pitch: return "pitch"
        case .interview: return "interview"
        case .idea: return "idea"
        }
    }
}

extension PolishMode {
    init(serverValue: String) {
        switch serverValue {
        case "concise": self = .concise
        case "formal": self = .formal
        case "spoken": self = .spoken
        case "executive": self = .executive
        default: self = .concise
        }
    }

    var serverValue: String {
        switch self {
        case .concise: return "concise"
        case .formal: return "formal"
        case .spoken: return "spoken"
        case .executive: return "executive"
        }
    }
}

extension IdeaCategory {
    init(serverValue: String) {
        switch serverValue {
        case "产品点子": self = .product
        case "功能需求": self = .feature
        case "商业模式": self = .business
        case "待验证假设": self = .hypothesis
        default: self = .content
        }
    }
}

extension TranscriptInputSource {
    init(serverValue: String?) {
        switch serverValue {
        case "text":
            self = .text
        case "speech":
            self = .speech
        default:
            self = .unknown
        }
    }
}
