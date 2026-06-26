# 出口成章｜可运行 App 原型

这是一个可直接在当前环境运行的 MVP 原型，目标是先把主流程跑通，并开始具备真实可用性：

1. 输入一段表达（支持文本输入）
2. 使用浏览器语音识别直接说话输入（Chrome 系兼容更好）
3. 上传真实音频文件并走本地 STT 转写
4. 生成转写与优化稿
5. 用浏览器原生 TTS 朗读优化稿 / 标准稿
6. 查看表达问题分析
7. 进行复述训练并得到评分
8. 一键归档到灵感库
9. 查看日报统计
10. 导出本地数据
11. 在首页快速切换 LLM profile（类似 CC switch）

## 运行方式

以下命令都按“先进入交接包里的 `app/` 目录”来写，这样把目录解压到任意 Mac 路径后也能直接照抄：

### 前台启动

```bash
cd app
npm start
```

> 启动时会自动读取：
> - `app/.env`
> - `app/.env.local`

### 后台启动（更适合本地长期挂着）

```bash
cd app
bash scripts/start.sh
bash scripts/status.sh
bash scripts/stop.sh
```

> 上面这组脚本现在已经改成相对路径解析，不再绑死当前 Linux 工作区绝对路径；把整个 `app/` 带到别的 Mac 目录后，也能继续直接跑。

### HTTP provider 烟测

```bash
cd app
bash scripts/smoke-http-provider.sh
```

该脚本会：
- 启动演示上游 provider
- 用 `CKCZ_PROVIDER=http` 启动 App
- 调用健康检查
- 调用一次 `transcripts/create`
- 自动清理进程

默认启动地址：

- `http://127.0.0.1:4321`
- 后台日志：`app/runtime/app.log`

## 自测

```bash
cd app
npm test
```

如果你想把“单测 + 隔离全链路烟测”一把跑完，现在也可以：

```bash
cd app
npm run verify
```

它会先跑 `npm test`，再执行 `bash scripts/smoke-api-flow.sh`；除 `transcribe / create / train / archive / report` 写链路外，还会回读 `transcripts / training / ideas` 列表，并顺手复核 `bootstrap` / `reports/daily` 与 iOS 客户端依赖的关键返回字段。

## 当前实现

- Node 原生 HTTP 服务，无额外依赖
- Provider 适配层已就位：`src/providers.js`
- HTTP 请求封装：`src/http-client.js`
- 多 LLM 快切配置：`src/llm-switch.js`
- LLM profile 示例：`config/llm-profiles.example.json`
- 本地 STT runner：`src/local-stt.js`
- faster-whisper 脚本：`scripts/faster_whisper_transcribe.py`
- 本地 STT 安装脚本：`scripts/setup-local-stt.sh`
- 本地 STT 预热脚本：`scripts/faster_whisper_warmup.py`
- STT HTTP fallback：`src/stt-http-fallback.js`
- 本地 JSON 数据存储：`data/store.json`
- 前端为原生 HTML/CSS/JS 单页应用
- 浏览器语音识别入口（Chrome 系浏览器兼容更好）
- 演示上游 provider：`examples/http-provider-demo.js`
- HTTP provider 契约文档：`HTTP Provider接入契约.md`
- 已实现 API：
  - `GET /api/health`
  - `GET /api/provider/status`
  - `GET /api/bootstrap`（iOS 首屏聚合入口，返回 provider 状态、transcripts、ideas、report）
  - `GET /api/llm/status`
  - `POST /api/llm/switch`
  - `POST /api/transcribe`
  - `POST /api/polish`
  - `POST /api/transcripts/create`
  - `GET /api/transcripts`
  - `POST /api/train/evaluate`
  - `GET /api/training`
  - `POST /api/ideas/archive`
  - `GET /api/ideas`
  - `GET /api/reports/daily`
  - `GET /api/export`
  - `POST /api/import`
  - `POST /api/reset`

## Provider 配置

默认使用本地 provider：
- 配置示例：`.env.example`

当前支持：
- `CKCZ_PROVIDER=local`
- `CKCZ_PROVIDER=http`

当使用 `http` provider 时，需要配置：
- `CKCZ_HTTP_BASE_URL`
- `CKCZ_HTTP_HEALTH_PATH`
- `CKCZ_HTTP_TRANSCRIBE_PATH`
- `CKCZ_HTTP_POLISH_PATH`
- `CKCZ_HTTP_TIMEOUT_MS`
- `CKCZ_HTTP_RETRIES`

后续接入真实 STT / LLM 时，优先在 provider 层扩展，不要直接把外部调用散落进路由处理器。

### LLM 快切（类似 CC switch）

1. 复制示例文件：

```bash
cp config/llm-profiles.example.json config/llm-profiles.json
```

2. 在 `config/llm-profiles.json` 里填入多个 provider 的：
- `baseUrl`
- `apiKey`
- `model`
- 可选 `chatPath`

> 除了 OpenRouter / SiliconFlow，这里也可以放 **本地 OpenAI-compatible 端点**，例如 Ollama、vLLM、TGI 等。
> 已在 `config/llm-profiles.example.json` 里预留了一个 **Local Gemma** 样板位；等联网确认 Gemma 4 的实际模型名后，直接替换 `model` 并启用即可。

3. 启动后可通过：
- 首页的 **LLM 切换** 卡片快速切换
- `GET /api/llm/status` 查看当前状态
- `POST /api/llm/switch` 切换当前 profile

如果没有配置任何 profile，系统会自动回退到本地启发式优化逻辑，不会把主流程跑崩。

### 本地 STT 与双线 fallback

当前支持两条 STT 路线并行：

1. **本地 free 线**：`faster-whisper`
2. **HTTP 兜底线**：当本地 STT 超时 / 拉模型失败时，自动回退到外部 HTTP STT

推荐先做这几步：

```bash
bash scripts/setup-local-stt.sh
python3 scripts/faster_whisper_warmup.py
```

如果当前环境无法从 HuggingFace 下载模型，有两个办法：

- 直接设置本地模型目录：
  - `CKCZ_STT_MODEL_PATH=/absolute/path/to/your/whisper-model`
- 或配置 HTTP fallback：
  - `CKCZ_STT_HTTP_BASE_URL=...`
  - `CKCZ_STT_HTTP_TRANSCRIBE_PATH=/transcribe`

这样本地 free 线和快速落地线可以同时保留，不会因为单点卡死整个闭环。

## 下一步

- 补真实 Mac / iPhone 联调下的音频上传、局域网访问与本地 STT 依赖验证
- 将当前启发式优化逻辑替换为真实 LLM 服务
- 增加用户体系与历史记录筛选
- 迁移为 iOS / Flutter / React Native 客户端时，可直接复用 API 设计
