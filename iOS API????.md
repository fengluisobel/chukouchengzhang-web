# 出口成章｜iOS SwiftUI API 对接说明

## 文档目标
说明如何将当前本地原型接口：

- 服务目录：`/home/gem/workspace/agent/workspace/projects/出口成章/app/`
- SwiftUI 骨架目录：`/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/ChuKouChengZhang/`

对接起来，让现有 SwiftUI 页面逐步从 Mock 数据切换为真实接口。

---

## 一、当前现状

### Web/Node 原型已实现接口
- `GET /api/health`
- `POST /api/transcripts/create`
- `GET /api/transcripts`
- `POST /api/train/evaluate`
- `GET /api/training?transcriptId=...`
- `POST /api/ideas/archive`
- `GET /api/ideas`
- `GET /api/reports/daily`
- `POST /api/reset`

### SwiftUI 当前状态
Swift 文件位于：
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/ChuKouChengZhang/`

当前使用：
- `MockDataService.swift`
- `AppViewModel.swift`

即：
- 页面已经有
- 流程已经有
- 但数据全是本地 Mock

目标是把 `MockDataService` 的职责逐步替换成 `APIClient`。

---

## 二、推荐对接策略

不要一次性全切，按下面顺序做：

### Step 1：先保留 UI，不动页面结构
页面保持不改：
- 首页
- 录音页
- 结果页
- 训练页
- 灵感库页
- 报告页

### Step 2：新增网络层
新建：
- `Services/APIClient.swift`
- `Services/AppConfig.swift`

这一步已经落地了基础骨架：
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/ChuKouChengZhang/Services/AppConfig.swift`
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/ChuKouChengZhang/Services/APIClient.swift`
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/ChuKouChengZhang/Services/RemoteModels.swift`
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/ChuKouChengZhang/ViewModels/AppViewModel.swift`（已补远端异步方法）

### Step 3：先替换读取接口
优先切换：
- 读取 transcripts
- 读取 ideas
- 读取 report

### Step 4：再替换写入接口
再切换：
- 创建 transcript
- 训练评分
- 归档 idea

### Step 5：最后接真实录音上传
这是第二阶段工作。

---

## 三、接口基地址配置

建议新增：

### `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/ChuKouChengZhang/Services/AppConfig.swift`

```swift
import Foundation

enum AppConfig {
    static let baseURL = URL(string: "http://127.0.0.1:4321")!
}
```

> 注意：
> - `127.0.0.1` 只适用于“iOS 模拟器访问本机服务”场景。
> - 如果是真机调试，需要替换成宿主机局域网 IP，例如 `http://192.168.x.x:4321`。

---

## 四、推荐的数据模型映射

当前 SwiftUI 模型定义在：
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/ChuKouChengZhang/Models.swift`

建议下一步把这些模型改成同时支持 `Codable`。

例如：

```swift
struct ExpressionIssue: Identifiable, Hashable, Codable {
    let id: UUID?
    let title: String
    let detail: String
}
```

但这里要注意：
当前 Node 接口返回的 `issues` 里未必有 UUID。

更稳的做法：
- 服务端 DTO 和 ViewModel 展示模型分开

建议新增 DTO：

```swift
struct IssueDTO: Codable {
    let title: String
    let detail: String
}

struct TranscriptDTO: Codable {
    let id: String
    let createdAt: String
    let scene: String
    let mode: String
    let rawText: String
    let polishedText: String
    let summaryTitle: String
    let suggestedTags: [String]
    let nextAction: String
    let issues: [IssueDTO]
}
```

然后在 ViewModel 中把 DTO 转换成 UI 模型。

---

## 五、APIClient 结构建议

建议新增文件：
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/ChuKouChengZhang/Services/APIClient.swift`

最小实现示例：

```swift
import Foundation

final class APIClient {
    static let shared = APIClient()
    private init() {}

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        var request = URLRequest(url: AppConfig.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}
```

---

## 六、各页面的迁移方式

## 6.1 HomeView
当前依赖：
- `viewModel.report`
- `viewModel.transcripts`

要改成：
- 页面出现时调用 `loadDashboard()`
- 同时拉：
  - `/api/reports/daily`
  - `/api/transcripts`

建议在 `AppViewModel` 新增：

```swift
@MainActor
func loadDashboard() async {
    async let report: DailyReportDTO = api.reportDaily()
    async let transcripts: [TranscriptDTO] = api.fetchTranscripts()
    // await 后再映射到 @Published
}
```

---

## 6.2 RecordView
当前行为：
- 点击按钮直接 `createMockTranscript(scene:)`

要改成：
- 用户录入文本后
- 调用 `POST /api/transcripts/create`
- 请求体：

```json
{
  "rawText": "用户输入内容",
  "scene": "idea",
  "mode": "concise"
}
```

Swift 示例：

```swift
struct CreateTranscriptRequest: Codable {
    let rawText: String
    let scene: String
    let mode: String
}
```

返回成功后：
- 插入 `transcripts`
- 更新 `selectedTranscript`
- dismiss 回上一页

---

## 6.3 ResultView
当前使用：
- `transcript.rawText`
- `transcript.polishedText`
- `transcript.issues`

这个页面结构可以不改。

只需要保证 `selectedTranscript` 来自 API 返回值，而不是 Mock 数据。

---

## 6.4 TrainingView
当前使用：
- `viewModel.trainingAttempts`

要改成两步：

### 进入页面时
调用：
- `GET /api/training?transcriptId=xxx`

### 提交复述稿时
调用：
- `POST /api/train/evaluate`

请求体：
```json
{
  "transcriptId": "ts_xxx",
  "attemptText": "用户复述稿",
  "round": 1
}
```

返回成功后：
- 刷新 `trainingAttempts`
- 重新渲染页面

---

## 6.5 LibraryView
进入页面时调用：
- `GET /api/ideas`

接口返回后直接映射到：
- `viewModel.ideas`

---

## 6.6 ReportsView
进入页面时调用：
- `GET /api/reports/daily`

映射到：
- `viewModel.report`

---

## 七、ViewModel 改造建议

当前文件：
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/ChuKouChengZhang/ViewModels/AppViewModel.swift`

建议改造思路：

### 先保留原有 Published 状态
继续保留：
- `transcripts`
- `selectedTranscript`
- `trainingAttempts`
- `ideas`
- `report`

### 再补异步方法
例如：
- `loadDashboard()`
- `createTranscript(rawText:scene:mode:)`
- `loadTrainingAttempts(transcriptId:)`
- `evaluateTraining(transcriptId:attemptText:round:)`
- `archiveSelectedTranscript()`
- `loadIdeas()`
- `loadReport()`

### 再补加载状态
建议新增：
- `@Published var isLoading = false`
- `@Published var errorMessage: String?`

这样页面上能显示：
- 加载中
- 请求失败
- 重试按钮

---

## 八、错误处理建议

接口层要区分三类错误：

### 1）网络错误
如：
- 服务没启动
- 超时
- 无法连通

提示：
- “当前无法连接服务，请检查本地服务是否启动。”

### 2）业务错误
如：
- `RAW_TEXT_REQUIRED`
- `TRANSCRIPT_NOT_FOUND`
- `ATTEMPT_REQUIRED`

提示要转成人话，不要直接给错误码。

### 3）解析错误
如：
- JSON 字段变化
- 后端返回结构不一致

开发期直接打印日志，线上要加兜底提示。

---

## 九、真机与模拟器联调注意事项

## 9.1 模拟器
若 Node 服务运行在 Mac 本机：
- 可直接尝试 `http://127.0.0.1:4321`

## 9.2 真机
不能再用 `127.0.0.1`。
需要：
- 把 baseURL 改成宿主机局域网 IP
- 手机与电脑处于同一网络
- 服务监听地址允许局域网访问

## 9.3 ATS 配置
如果是 HTTP 调试地址，需要在 iOS 工程的 `Info.plist` 中添加 ATS 例外。
开发期可以放开测试域名；上线前必须切 HTTPS。

---

## 十、推荐迁移顺序

### 第一轮（最小可跑）
- [ ] 新增 `AppConfig.swift`
- [ ] 新增 `APIClient.swift`
- [ ] 定义 DTO
- [ ] `RecordView` 改为调用 `/api/transcripts/create`
- [ ] `HomeView` 改为读取 `/api/transcripts` 和 `/api/reports/daily`
- [ ] `LibraryView` 改为读取 `/api/ideas`

### 第二轮（训练闭环）
- [ ] `TrainingView` 接 `/api/train/evaluate`
- [ ] `TrainingView` 接 `/api/training`
- [ ] `ResultView` 接“归档灵感”动作

### 第三轮（真能力）
- [ ] 补真实录音
- [ ] 补音频上传 `POST /transcribe`
- [ ] 用真实转写结果替换文本输入

---

## 十一、最关键的工程建议

### 建议 1
**先对接现有文本版 API，不要一上来就接音频。**

原因：
- 页面流已经有了
- 数据流先跑通最重要
- 音频接入是第二复杂层

### 建议 2
**DTO 和页面模型分开。**

原因：
- 后端字段未来会变
- UI 模型要稳定
- 后期才好维护

### 建议 3
**所有网络调用放到 ViewModel / Service，页面只做展示。**

原因：
- SwiftUI 页面会更干净
- 更容易测试
- 更容易补 loading/error 状态

---

## 结论
最顺的落地方式是：

**先把现有 SwiftUI 骨架从 Mock 数据切到现有 Node API，再在这条线上继续接入真实录音与真实 AI 能力。**

别一口气跨两层，不然会同时卡在：
- 页面问题
- 网络问题
- 音频问题
- 模型问题

先把“文本版真接口”接通，SwiftUI 就会立刻从 Demo 骨架升级为“可联网原型”。
