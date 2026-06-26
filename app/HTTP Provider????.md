# 出口成章｜HTTP Provider 接入契约

## 目标
当 `CKCZ_PROVIDER=http` 时，当前 App 会把转写和优化请求转发到外部 HTTP 服务。

相关文件：
- `/home/gem/workspace/agent/workspace/projects/出口成章/app/src/providers.js`
- `/home/gem/workspace/agent/workspace/projects/出口成章/app/src/http-client.js`
- `/home/gem/workspace/agent/workspace/projects/出口成章/app/.env.example`

---

## 一、环境变量

```bash
CKCZ_PROVIDER=http
CKCZ_HTTP_BASE_URL=http://127.0.0.1:8000
CKCZ_HTTP_HEALTH_PATH=/health
CKCZ_HTTP_TRANSCRIBE_PATH=/transcribe
CKCZ_HTTP_POLISH_PATH=/polish
CKCZ_HTTP_TIMEOUT_MS=15000
CKCZ_HTTP_RETRIES=1
```

---

## 二、上游接口要求

### 0）GET /health
响应：
```json
{
  "ok": true,
  "provider": "your-provider-name"
}
```

### 1）POST /transcribe
请求：
```json
{
  "rawText": "用户原始输入",
  "scene": "idea",
  "inputSource": "speech",
  "captureMeta": {
    "durationSeconds": 18,
    "capturedBy": "browser-speech-recognition"
  }
}
```

响应：
```json
{
  "text": "转写后的文本",
  "language": "zh-CN",
  "duration": 18,
  "wordCount": 42,
  "scene": "idea",
  "inputSource": "speech",
  "captureMeta": {
    "durationSeconds": 18,
    "capturedBy": "browser-speech-recognition"
  },
  "provider": "your-stt-provider"
}
```

### 2）POST /polish
请求：
```json
{
  "rawText": "用户原始输入",
  "scene": "idea",
  "mode": "concise",
  "inputSource": "speech",
  "captureMeta": {
    "durationSeconds": 18,
    "capturedBy": "browser-speech-recognition"
  },
  "transcriptionMeta": {
    "provider": "browser-web-speech"
  }
}
```

响应：
```json
{
  "polishedText": "整理后的优化稿",
  "summaryTitle": "一句标题",
  "issues": [
    {
      "title": "句子偏长",
      "detail": "建议拆成两句"
    }
  ],
  "suggestedTags": ["表达训练", "产品表达"],
  "nextAction": "先用优化稿复述一遍",
  "provider": "your-llm-provider"
}
```

---

## 三、当前 App 的消费方式

- `/api/transcribe`：直接转发到上游 `/transcribe`
- `/api/polish`：直接转发到上游 `/polish`
- `/api/transcripts/create`：先生成本地 transcript 骨架，再调用上游 `/polish` 覆盖优化结果

也就是说：
- 如果你先只接 `/polish`
- `create transcript` 这条主流程就已经能切到外部 LLM

---

## 四、返回约束

建议上游返回：
- JSON
- UTF-8
- HTTP 2xx 表示成功
- HTTP 4xx/5xx 表示失败

失败时建议结构：
```json
{
  "error": "UPSTREAM_ERROR",
  "message": "模型服务暂时不可用"
}
```

---

## 五、验证方式

可直接使用演示上游服务：
- `/home/gem/workspace/agent/workspace/projects/出口成章/app/examples/http-provider-demo.js`

它实现了：
- `/transcribe`
- `/polish`

用于验证 App 的 http provider 链路是否打通。
