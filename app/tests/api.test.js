const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs/promises');
const os = require('node:os');

const { createServer } = require('../src/server');
const { createDemoProviderServer } = require('../examples/http-provider-demo');

async function startTestServer(options = {}) {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'ckcz-app-'));
  const dataFile = path.join(tempDir, 'store.json');
  const publicDir = path.resolve(__dirname, '../public');
  const llmConfigFile = path.join(tempDir, 'llm-profiles.json');
  const llmSettingsFile = path.join(tempDir, 'llm-settings.json');

  if (options.llmProfiles) {
    await fs.writeFile(llmConfigFile, JSON.stringify(options.llmProfiles, null, 2), 'utf8');
  }

  const server = createServer({
    dataFile,
    publicDir,
    providerConfig: options.providerConfig,
    llmConfigFile,
    llmSettingsFile
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();

  return {
    baseUrl: `http://127.0.0.1:${address.port}`,
    tempDir,
    llmConfigFile,
    llmSettingsFile,
    close: () => new Promise((resolve, reject) => server.close((err) => (err ? reject(err) : resolve()))),
    cleanup: () => fs.rm(tempDir, { recursive: true, force: true })
  };
}

async function startDemoProvider() {
  const server = createDemoProviderServer();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  return {
    baseUrl: `http://127.0.0.1:${address.port}`,
    close: () => new Promise((resolve, reject) => server.close((err) => (err ? reject(err) : resolve())))
  };
}

async function request(baseUrl, pathname, options = {}) {
  const response = await fetch(`${baseUrl}${pathname}`, {
    method: options.method || 'GET',
    headers: {
      'Content-Type': 'application/json'
    },
    body: options.body ? JSON.stringify(options.body) : undefined
  });

  const data = await response.json();
  return { status: response.status, data };
}

test('完整主流程：local provider 支持语音来源元信息、训练、归档、报告、导入导出', async () => {
  const app = await startTestServer();

  try {
    const health = await request(app.baseUrl, '/api/health');
    assert.equal(health.status, 200);
    assert.equal(health.data.ok, true);
    assert.equal(health.data.provider, 'local');

    const create = await request(app.baseUrl, '/api/transcripts/create', {
      method: 'POST',
      body: {
        rawText: '我想做一个帮助用户把口头表达整理清楚的产品，还能通过复述训练提升表达能力。',
        scene: 'idea',
        mode: 'concise',
        inputSource: 'speech',
        captureMeta: {
          durationSeconds: 18,
          capturedBy: 'browser-speech-recognition'
        },
        transcriptionMeta: {
          provider: 'browser-web-speech'
        }
      }
    });
    assert.equal(create.status, 201);
    assert.ok(create.data.id);
    assert.ok(create.data.polishedText.includes('下一步建议'));
    assert.equal(create.data.inputSource, 'speech');
    assert.equal(create.data.captureMeta.durationSeconds, 18);

    const transcriptId = create.data.id;

    const list = await request(app.baseUrl, '/api/transcripts');
    assert.equal(list.status, 200);
    assert.equal(list.data.length, 1);
    assert.equal(list.data[0].inputSource, 'speech');

    const training = await request(app.baseUrl, '/api/train/evaluate', {
      method: 'POST',
      body: {
        transcriptId,
        attemptText: '这个产品会先整理口头表达，再通过复述训练帮助用户持续提升表达质量。',
        round: 1
      }
    });
    assert.equal(training.status, 201);
    assert.ok(training.data.clarityScore >= 35);
    assert.equal(training.data.transcriptId, transcriptId);

    const archive = await request(app.baseUrl, '/api/ideas/archive', {
      method: 'POST',
      body: { transcriptId }
    });
    assert.ok([200, 201].includes(archive.status));
    assert.equal(archive.data.transcriptId, transcriptId);

    const report = await request(app.baseUrl, '/api/reports/daily');
    assert.equal(report.status, 200);
    assert.equal(report.data.transcribeCount, 1);
    assert.equal(report.data.trainingCount, 1);
    assert.equal(report.data.polishCount, 1);
    assert.equal(report.data.speechInputCount, 1);
    assert.ok(report.data.bestSentence.length > 0);

    const providerStatus = await request(app.baseUrl, '/api/provider/status');
    assert.equal(providerStatus.status, 200);
    assert.equal(providerStatus.data.provider, 'local');
    assert.equal(providerStatus.data.ok, true);

    const bootstrap = await request(app.baseUrl, '/api/bootstrap');
    assert.equal(bootstrap.status, 200);
    assert.equal(bootstrap.data.providerStatus.provider, 'local');
    assert.equal(bootstrap.data.transcripts.length, 1);
    assert.equal(bootstrap.data.ideas.length, 1);
    assert.equal(bootstrap.data.report.trainingCount, 1);

    const exported = await request(app.baseUrl, '/api/export');
    assert.equal(exported.status, 200);
    assert.equal(exported.data.version, 1);
    assert.equal(exported.data.store.transcripts.length, 1);
    assert.equal(exported.data.store.ideas.length, 1);

    const imported = await request(app.baseUrl, '/api/import', {
      method: 'POST',
      body: {
        mode: 'merge',
        store: exported.data.store
      }
    });
    assert.equal(imported.status, 200);
    assert.equal(imported.data.counts.transcripts, 1);
    assert.equal(imported.data.counts.ideas, 1);
  } finally {
    await app.close();
    await app.cleanup();
  }
});

test('真实音频转写链路：支持通过本地 STT runner 从音频创建 transcript', async () => {
  const app = await startTestServer({
    providerConfig: {
      name: 'local',
      local: {
        stt: {
          mockResult: {
            text: '这是一段来自真实音频上传链路的测试转写。',
            language: 'zh-CN',
            duration: 6,
            segments: [{ start: 0, end: 1.2, text: '这是一段来自真实音频上传链路的测试转写。' }]
          }
        }
      }
    }
  });

  try {
    const providerStatus = await request(app.baseUrl, '/api/provider/status');
    assert.equal(providerStatus.status, 200);
    assert.equal(providerStatus.data.provider, 'local');
    assert.equal(providerStatus.data.stt.ok, true);
    assert.equal(providerStatus.data.stt.provider, 'mock-stt');

    const create = await request(app.baseUrl, '/api/transcripts/create', {
      method: 'POST',
      body: {
        scene: 'idea',
        mode: 'concise',
        inputSource: 'speech',
        audioBase64: 'ZHVtbXk=',
        audioMimeType: 'audio/webm',
        audioName: 'demo.webm',
        captureMeta: {
          capturedBy: 'audio-file-upload',
          sizeBytes: 5
        }
      }
    });

    assert.equal(create.status, 201);
    assert.equal(create.data.rawText, '这是一段来自真实音频上传链路的测试转写。');
    assert.equal(create.data.inputSource, 'speech');
    assert.equal(create.data.transcriptionMeta.provider, 'mock-stt');
    assert.equal(create.data.transcriptionMeta.duration, 6);
    assert.equal(create.data.transcriptionMeta.audioMeta.fileName, 'demo.webm');
  } finally {
    await app.close();
    await app.cleanup();
  }
});

test('双线并行：local provider 的音频 STT 可在本地失败时回退到 HTTP fallback', async () => {
  const upstream = await startDemoProvider();
  const app = await startTestServer({
    providerConfig: {
      name: 'local',
      local: {
        stt: {
          pythonBin: 'python3',
          scriptPath: path.resolve(__dirname, '../scripts/faster_whisper_transcribe.py'),
          model: 'small',
          timeoutMs: 50,
          healthTimeoutMs: 50
        },
        sttHttpFallback: {
          baseUrl: upstream.baseUrl,
          transcribePath: '/transcribe',
          healthPath: '/health'
        }
      }
    }
  });

  try {
    const providerStatus = await request(app.baseUrl, '/api/provider/status');
    assert.equal(providerStatus.status, 200);
    assert.equal(providerStatus.data.provider, 'local');
    assert.equal(providerStatus.data.sttFallback.enabled, true);
    assert.equal(providerStatus.data.sttFallback.ok, true);

    const create = await request(app.baseUrl, '/api/transcripts/create', {
      method: 'POST',
      body: {
        scene: 'idea',
        mode: 'concise',
        inputSource: 'speech',
        audioBase64: 'ZHVtbXk=',
        audioMimeType: 'audio/webm',
        audioName: 'fallback.webm',
        captureMeta: {
          capturedBy: 'audio-file-upload',
          sizeBytes: 5
        }
      }
    });

    assert.equal(create.status, 201);
    assert.equal(create.data.rawText, '这是通过 HTTP STT fallback 走出来的一段测试转写。');
    assert.equal(create.data.transcriptionMeta.provider, 'http-demo-stt');
    assert.equal(create.data.transcriptionMeta.audioMeta.fileName, 'fallback.webm');
  } finally {
    await app.close();
    await app.cleanup();
    await upstream.close();
  }
});

test('完整主流程：http provider 可真实联通上游 demo 服务', async () => {
  const upstream = await startDemoProvider();
  const app = await startTestServer({
    providerConfig: {
      name: 'http',
      http: {
        baseUrl: upstream.baseUrl,
        transcribePath: '/transcribe',
        polishPath: '/polish'
      }
    }
  });

  try {
    const health = await request(app.baseUrl, '/api/health');
    assert.equal(health.status, 200);
    assert.equal(health.data.provider, 'http');

    const providerStatus = await request(app.baseUrl, '/api/provider/status');
    assert.equal(providerStatus.status, 200);
    assert.equal(providerStatus.data.provider, 'http');
    assert.equal(providerStatus.data.ok, true);
    assert.equal(providerStatus.data.upstream.provider, 'http-demo-provider');

    const transcribe = await request(app.baseUrl, '/api/transcribe', {
      method: 'POST',
      body: {
        rawText: '这是一次通过 http provider 走的转写请求。',
        scene: 'general',
        inputSource: 'text'
      }
    });
    assert.equal(transcribe.status, 200);
    assert.equal(transcribe.data.provider, 'http-demo-stt');

    const create = await request(app.baseUrl, '/api/transcripts/create', {
      method: 'POST',
      body: {
        rawText: '这是一次通过 http provider 走的优化请求，用来验证上游服务真的打通了。',
        scene: 'idea',
        mode: 'concise',
        inputSource: 'text'
      }
    });
    assert.equal(create.status, 201);
    assert.equal(create.data.provider, 'http-demo-llm');
    assert.match(create.data.polishedText, /HTTP Provider 已处理/);
  } finally {
    await app.close();
    await app.cleanup();
    await upstream.close();
  }
});

test('LLM switch：支持读取多个 profile 并切换当前激活项', async () => {
  const app = await startTestServer({
    llmProfiles: {
      activeProfileId: 'openrouter',
      profiles: [
        {
          id: 'openrouter',
          name: 'OpenRouter',
          baseUrl: 'https://openrouter.ai/api',
          apiKey: 'sk-or-demo',
          model: 'openai/gpt-4.1-mini'
        },
        {
          id: 'siliconflow',
          name: 'SiliconFlow',
          baseUrl: 'https://api.siliconflow.cn/v1',
          apiKey: 'sk-sf-demo',
          model: 'deepseek-ai/DeepSeek-V3'
        }
      ]
    }
  });

  try {
    const status = await request(app.baseUrl, '/api/llm/status');
    assert.equal(status.status, 200);
    assert.equal(status.data.enabled, true);
    assert.equal(status.data.activeProfileId, 'openrouter');
    assert.equal(status.data.profiles.length, 2);

    const switched = await request(app.baseUrl, '/api/llm/switch', {
      method: 'POST',
      body: { profileId: 'siliconflow' }
    });
    assert.equal(switched.status, 200);
    assert.equal(switched.data.ok, true);
    assert.equal(switched.data.activeProfileId, 'siliconflow');

    const statusAfter = await request(app.baseUrl, '/api/llm/status');
    assert.equal(statusAfter.status, 200);
    assert.equal(statusAfter.data.activeProfileId, 'siliconflow');
  } finally {
    await app.close();
    await app.cleanup();
  }
});

test('静态页可访问', async () => {
  const app = await startTestServer();

  try {
    const response = await fetch(`${app.baseUrl}/`);
    const html = await response.text();
    assert.equal(response.status, 200);
    assert.match(html, /出口成章/);
    assert.match(html, /开始语音输入/);
    assert.match(html, /导入数据/);
    assert.match(html, /导出数据/);
    assert.match(html, /运行状态/);
    assert.match(html, /LLM 切换/);
    assert.match(html, /上传音频文件转写/);
    assert.match(html, /朗读优化稿/);
    assert.match(html, /朗读标准稿/);
  } finally {
    await app.close();
    await app.cleanup();
  }
});
