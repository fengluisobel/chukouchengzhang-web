import Foundation

struct MockDataService {
    static let sampleTranscript = Transcript(
        createdAt: Date(),
        scene: .idea,
        rawText: "我想做一个结合语音转文字和表达训练的产品，它不只是把你说的话记下来，还会帮你整理成更有逻辑的版本，并且让你重新说一遍，看看有没有进步。",
        polishedText: "我想做一款结合语音转写与表达训练的产品。它不仅能记录用户说了什么，还能将内容整理成更清晰、更有逻辑的表达版本，并通过再次复述帮助用户持续提升表达能力。",
        mode: .concise,
        inputSource: .speech,
        summaryTitle: "把口头表达整理成清晰成稿",
        suggestedTags: ["表达训练", "语音转写", "产品灵感"],
        nextAction: "先把核心流程做成可跑通的 MVP，再拉 3 个真实用户试用。",
        provider: "mock-local",
        issues: [
            ExpressionIssue(title: "重复表达", detail: "‘还会帮你’与后文语义重复，可合并。"),
            ExpressionIssue(title: "句子过长", detail: "原句承载信息过多，适合拆成两句。"),
            ExpressionIssue(title: "结构不清", detail: "先说产品定义，再说产品价值会更顺。")
        ]
    )

    static let trainingAttempts: [TrainingAttempt] = [
        TrainingAttempt(round: 1, text: "我想做一个能记录并优化表达的产品。", clarityScore: 72, structureScore: 68, polishScore: 70, feedback: "表达目标清楚了，但产品价值还可以再明确。"),
        TrainingAttempt(round: 2, text: "我想做一款结合语音转写和表达训练的产品，帮助用户把口头表达整理成更清晰的内容。", clarityScore: 85, structureScore: 82, polishScore: 84, feedback: "结构明显更清楚，核心价值表达到了。")
    ]

    static let ideas: [Idea] = [
        Idea(
            title: "出口成章",
            rawInput: sampleTranscript.rawText,
            normalizedText: sampleTranscript.polishedText,
            category: .product,
            tags: ["表达训练", "语音转写", "产品灵感"],
            nextAction: "整理 MVP 页面并做首版 Demo",
            status: "推进中",
            createdAt: Date()
        ),
        Idea(
            title: "汇报增强模式",
            rawInput: "把工作汇报说完后，自动生成结论先行版。",
            normalizedText: "面向职场用户提供结论先行的汇报整理模式。",
            category: .feature,
            tags: ["职场", "汇报"],
            nextAction: "补充汇报模板",
            status: "待验证",
            createdAt: Date().addingTimeInterval(-86400)
        )
    ]

    static let report = DailyReport(
        totalWords: 3268,
        transcribeCount: 12,
        trainingCount: 4,
        polishCount: 10,
        catchphraseCount: 21,
        speechInputCount: 7,
        bestSentence: "生成内容不稀缺，清晰表达自己才是核心竞争力。"
    )
}
