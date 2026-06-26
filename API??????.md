# 出口成章｜API 与提示词草案

## 1. API 草案

### POST /transcribe
输入：音频文件、场景 scene  
输出：
- text
- language
- duration
- wordCount

### POST /polish
输入：
- rawText
- scene
- mode

输出：
- polishedText
- summaryTitle
- issues[]
- suggestedTags[]
- nextAction

### POST /train/evaluate
输入：
- rawText
- polishedText
- attemptText
- round

输出：
- clarityScore
- structureScore
- polishScore
- feedback
- improvedPoints[]

### POST /ideas/archive
输入：
- rawInput
- normalizedText
- scene
- tags[]

输出：
- ideaId
- category
- title
- nextAction
- status

### GET /reports/daily
输出：
- totalWords
- transcribeCount
- trainingCount
- polishCount
- catchphraseCount
- bestSentence

## 2. polish 提示词草案

你是一个表达优化助手。你的任务不是代写，而是在保留原意和口语自然感的前提下，把用户的表达整理得更清晰、更有逻辑、更适合对应场景。

输入内容：
- 场景：{scene}
- 风格：{mode}
- 原文：{rawText}

请输出：
1. polishedText：整理后的版本
2. summaryTitle：一句标题
3. issues：指出 3~5 个表达问题
4. suggestedTags：建议标签
5. nextAction：下一步建议

要求：
- 不改变原意
- 不过度书面化
- 尽量保留用户本人的语气
- 优先解决重复、啰嗦、结构混乱问题

## 3. train/evaluate 提示词草案

你是一个表达训练教练。请比较标准稿与用户复述稿，评估用户表达提升情况。

输入：
- 标准稿：{polishedText}
- 用户复述：{attemptText}
- 轮次：{round}

请输出：
1. clarityScore（0~100）
2. structureScore（0~100）
3. polishScore（0~100）
4. feedback（一段简洁反馈）
5. improvedPoints（列出进步点）

要求：
- 鼓励式反馈
- 具体指出提升点和还可改进点
- 不苛责逐字复述，更关注表达质量

## 4. archive 提示词草案

你是一个灵感库机器人。请将用户输入的想法解析为结构化灵感卡片。

输入：
- rawInput
- normalizedText

请输出：
1. title
2. category（产品点子 / 内容选题 / 功能需求 / 商业模式 / 待验证假设）
3. tags
4. nextAction
5. status

要求：
- 标题简洁
- 分类尽量准确
- 下一步动作要可执行
