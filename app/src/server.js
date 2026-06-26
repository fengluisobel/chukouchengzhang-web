const http = require('node:http');
const path = require('node:path');
const fs = require('node:fs/promises');
const { URL } = require('node:url');

const { loadAppEnv } = require('./load-env');
loadAppEnv();

const { readStore, writeStore, defaultStore, ensureStore } = require('./storage');
const { evaluateAttempt, archiveIdea, buildDailyReport } = require('./domain');
const { createProviders } = require('./providers');
const { createLlmSwitch, DEFAULT_LLM_CONFIG_FILE, DEFAULT_LLM_SETTINGS_FILE } = require('./llm-switch');
const { createLocalStt } = require('./local-stt');
const { createSttHttpFallback } = require('./stt-http-fallback');
const { createXfyunStt } = require('./xfyun-stt');

const DEFAULT_PORT = Number(process.env.PORT || 4321);
const DEFAULT_DATA_FILE = process.env.CKCZ_DATA_FILE
  ? path.resolve(process.env.CKCZ_DATA_FILE)
  : path.resolve(__dirname, '../data/store.json');
const DEFAULT_PUBLIC_DIR = process.env.CKCZ_PUBLIC_DIR
  ? path.resolve(process.env.CKCZ_PUBLIC_DIR)
  : path.resolve(__dirname, '../public');

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store'
  });
  res.end(JSON.stringify(payload, null, 2));
}

function sendText(res, statusCode, text, contentType = 'text/plain; charset=utf-8') {
  res.writeHead(statusCode, {
    'Content-Type': contentType,
    'Cache-Control': 'no-store'
  });
  res.end(text);
}

async function readBody(req) {
  const chunks = [];
  let size = 0;
  const limitBytes = Number(process.env.CKCZ_BODY_LIMIT_MB || 25) * 1024 * 1024;

  for await (const chunk of req) {
    size += chunk.length;
    if (size > limitBytes) {
      throw new Error(`请求体过大，超过 ${Math.round(limitBytes / 1024 / 1024)}MB`);
    }
    chunks.push(chunk);
  }

  const raw = Buffer.concat(chunks).toString('utf8').trim();
  return raw ? JSON.parse(raw) : {};
}

function notFound(res) {
  sendJson(res, 404, { error: 'NOT_FOUND' });
}

function dedupeById(items) {
  const seen = new Set();
  const result = [];
  for (const item of items) {
    const key = item?.id || JSON.stringify(item);
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(item);
  }
  return result;
}

async function serveStatic(req, res, publicDir) {
  const requestUrl = new URL(req.url, 'http://localhost');
  const pathname = requestUrl.pathname === '/' ? '/index.html' : requestUrl.pathname;
  const filePath = path.normalize(path.join(publicDir, pathname));

  if (!filePath.startsWith(publicDir)) {
    sendJson(res, 403, { error: 'FORBIDDEN' });
    return;
  }

  try {
    const content = await fs.readFile(filePath);
    const ext = path.extname(filePath).toLowerCase();
    const contentType = ({
      '.html': 'text/html; charset=utf-8',
      '.css': 'text/css; charset=utf-8',
      '.js': 'text/javascript; charset=utf-8',
      '.json': 'application/json; charset=utf-8'
    })[ext] || 'application/octet-stream';

    sendText(res, 200, content, contentType);
  } catch {
    if (pathname === '/index.html') {
      sendText(res, 500, 'index.html 缺失');
      return;
    }
    notFound(res);
  }
}

function createServer({
  dataFile = DEFAULT_DATA_FILE,
  publicDir = DEFAULT_PUBLIC_DIR,
  providerConfig,
  llmConfigFile = DEFAULT_LLM_CONFIG_FILE,
  llmSettingsFile = DEFAULT_LLM_SETTINGS_FILE
} = {}) {
  const llmSwitch = createLlmSwitch({ configFile: llmConfigFile, settingsFile: llmSettingsFile });
  const localStt = createLocalStt((providerConfig && providerConfig.local && providerConfig.local.stt) || {});
  const sttHttpFallback = createSttHttpFallback((providerConfig && providerConfig.local && providerConfig.local.sttHttpFallback) || {});
  const xfyunStt = createXfyunStt((providerConfig && providerConfig.local && providerConfig.local.xfyun) || {});
  const provider = createProviders(providerConfig || {}, { llmSwitch, localStt, sttHttpFallback, xfyunStt });
  const server = http.createServer(async (req, res) => {
    const requestUrl = new URL(req.url, 'http://localhost');
    const { pathname, searchParams } = requestUrl;

    try {
      if (pathname === '/api/health' && req.method === 'GET') {
        sendJson(res, 200, { ok: true, service: '出口成章-app', provider: provider.name });
        return;
      }

      if (pathname === '/api/provider/status' && req.method === 'GET') {
        const result = await provider.healthCheck();
        sendJson(res, 200, result);
        return;
      }

      if (pathname === '/api/bootstrap' && req.method === 'GET') {
        const [providerStatus, store] = await Promise.all([
          provider.healthCheck(),
          readStore(dataFile)
        ]);
        sendJson(res, 200, {
          providerStatus,
          transcripts: store.transcripts,
          ideas: store.ideas,
          report: buildDailyReport(store)
        });
        return;
      }

      if (pathname === '/api/llm/status' && req.method === 'GET') {
        const result = await llmSwitch.status();
        sendJson(res, 200, result);
        return;
      }

      if (pathname === '/api/stt/status' && req.method === 'GET') {
        const providerStatus = await provider.healthCheck();
        sendJson(res, 200, {
          stt: providerStatus.stt || null,
          sttFallback: providerStatus.sttFallback || null,
          xfyun: providerStatus.xfyun || null
        });
        return;
      }

      if (pathname === '/api/llm/switch' && req.method === 'POST') {
        const body = await readBody(req);
        if (!String(body.profileId || '').trim()) {
          sendJson(res, 400, { error: 'PROFILE_ID_REQUIRED' });
          return;
        }
        const result = await llmSwitch.switchProfile(String(body.profileId).trim());
        sendJson(res, 200, { ok: true, ...result });
        return;
      }

      if (pathname === '/api/reset' && req.method === 'POST') {
        await writeStore(dataFile, defaultStore());
        sendJson(res, 200, { ok: true });
        return;
      }

      if (pathname === '/api/export' && req.method === 'GET') {
        const store = await readStore(dataFile);
        sendJson(res, 200, {
          exportedAt: new Date().toISOString(),
          version: 1,
          store
        });
        return;
      }

      if (pathname === '/api/import' && req.method === 'POST') {
        const body = await readBody(req);
        const incomingStore = body?.store;
        if (!incomingStore || typeof incomingStore !== 'object') {
          sendJson(res, 400, { error: 'STORE_REQUIRED' });
          return;
        }

        const mode = body?.mode === 'replace' ? 'replace' : 'merge';
        const current = await readStore(dataFile);
        const imported = {
          transcripts: Array.isArray(incomingStore.transcripts) ? incomingStore.transcripts : [],
          trainingAttempts: Array.isArray(incomingStore.trainingAttempts) ? incomingStore.trainingAttempts : [],
          ideas: Array.isArray(incomingStore.ideas) ? incomingStore.ideas : []
        };

        const next = mode === 'replace'
          ? imported
          : {
              transcripts: dedupeById([...imported.transcripts, ...current.transcripts]),
              trainingAttempts: dedupeById([...imported.trainingAttempts, ...current.trainingAttempts]),
              ideas: dedupeById([...imported.ideas, ...current.ideas])
            };

        await writeStore(dataFile, next);
        sendJson(res, 200, {
          ok: true,
          mode,
          counts: {
            transcripts: next.transcripts.length,
            trainingAttempts: next.trainingAttempts.length,
            ideas: next.ideas.length
          }
        });
        return;
      }

      if (pathname === '/api/transcribe' && req.method === 'POST') {
        const body = await readBody(req);
        const result = await provider.transcribe({
          rawText: body.rawText || '',
          scene: body.scene || 'general',
          inputSource: body.inputSource || (body.audioBase64 ? 'speech' : 'text'),
          captureMeta: body.captureMeta || null,
          audioBase64: body.audioBase64 || '',
          audioMimeType: body.audioMimeType || '',
          audioName: body.audioName || '',
          prompt: body.prompt || ''
        });
        sendJson(res, 200, result);
        return;
      }

      if (pathname === '/api/polish' && req.method === 'POST') {
        const body = await readBody(req);
        const result = await provider.polish({
          rawText: body.rawText || '',
          scene: body.scene || 'general',
          mode: body.mode || 'concise',
          inputSource: body.inputSource || 'text',
          captureMeta: body.captureMeta || null,
          transcriptionMeta: body.transcriptionMeta || null
        });
        sendJson(res, 200, result);
        return;
      }

      if (pathname === '/api/transcripts/create' && req.method === 'POST') {
        const body = await readBody(req);
        let rawText = String(body.rawText || '').trim();
        let transcriptionMeta = body.transcriptionMeta || null;
        const inputSource = body.inputSource || (body.audioBase64 ? 'speech' : 'text');

        if (!rawText && body.audioBase64) {
          const transcribed = await provider.transcribe({
            rawText: '',
            scene: body.scene || 'general',
            inputSource,
            captureMeta: body.captureMeta || null,
            audioBase64: body.audioBase64,
            audioMimeType: body.audioMimeType || '',
            audioName: body.audioName || '',
            prompt: body.prompt || ''
          });
          rawText = String(transcribed.text || '').trim();
          transcriptionMeta = {
            ...(transcriptionMeta || {}),
            provider: transcribed.provider || 'local-stt',
            language: transcribed.language || 'zh-CN',
            duration: transcribed.duration ?? null,
            audioMeta: transcribed.audioMeta || null,
            segments: transcribed.segments || []
          };
        }

        if (!rawText) {
          sendJson(res, 400, { error: 'RAW_TEXT_REQUIRED' });
          return;
        }

        const transcript = await provider.createTranscript({
          rawText,
          scene: body.scene || 'general',
          mode: body.mode || 'concise',
          inputSource,
          captureMeta: body.captureMeta || null,
          transcriptionMeta
        });
        const store = await readStore(dataFile);
        store.transcripts.unshift(transcript);
        await writeStore(dataFile, store);
        sendJson(res, 201, transcript);
        return;
      }

      if (pathname === '/api/transcripts' && req.method === 'GET') {
        const store = await readStore(dataFile);
        sendJson(res, 200, store.transcripts);
        return;
      }

      if (pathname === '/api/train/evaluate' && req.method === 'POST') {
        const body = await readBody(req);
        const store = await readStore(dataFile);
        const transcript = store.transcripts.find((item) => item.id === body.transcriptId);
        if (!transcript) {
          sendJson(res, 404, { error: 'TRANSCRIPT_NOT_FOUND' });
          return;
        }
        if (!String(body.attemptText || '').trim()) {
          sendJson(res, 400, { error: 'ATTEMPT_REQUIRED' });
          return;
        }

        const round = Number(body.round || (store.trainingAttempts.filter((item) => item.transcriptId === transcript.id).length + 1));
        const attempt = evaluateAttempt({
          polishedText: transcript.polishedText,
          rawText: transcript.rawText,
          attemptText: body.attemptText,
          round
        });
        const storedAttempt = { ...attempt, transcriptId: transcript.id };
        store.trainingAttempts.unshift(storedAttempt);
        await writeStore(dataFile, store);
        sendJson(res, 201, storedAttempt);
        return;
      }

      if (pathname === '/api/training' && req.method === 'GET') {
        const transcriptId = searchParams.get('transcriptId');
        const store = await readStore(dataFile);
        const items = transcriptId
          ? store.trainingAttempts.filter((item) => item.transcriptId === transcriptId)
          : store.trainingAttempts;
        sendJson(res, 200, items);
        return;
      }

      if (pathname === '/api/ideas/archive' && req.method === 'POST') {
        const body = await readBody(req);
        const store = await readStore(dataFile);
        const transcript = store.transcripts.find((item) => item.id === body.transcriptId);
        if (!transcript) {
          sendJson(res, 404, { error: 'TRANSCRIPT_NOT_FOUND' });
          return;
        }

        const exists = store.ideas.find((item) => item.transcriptId === transcript.id);
        if (exists) {
          sendJson(res, 200, exists);
          return;
        }

        const idea = archiveIdea(transcript);
        store.ideas.unshift(idea);
        await writeStore(dataFile, store);
        sendJson(res, 201, idea);
        return;
      }

      if (pathname === '/api/ideas' && req.method === 'GET') {
        const store = await readStore(dataFile);
        sendJson(res, 200, store.ideas);
        return;
      }

      if (pathname === '/api/reports/daily' && req.method === 'GET') {
        const store = await readStore(dataFile);
        sendJson(res, 200, buildDailyReport(store));
        return;
      }

      if (pathname.startsWith('/api/')) {
        notFound(res);
        return;
      }

      await serveStatic(req, res, publicDir);
    } catch (error) {
      sendJson(res, 500, {
        error: 'INTERNAL_ERROR',
        message: error instanceof Error ? error.message : '未知错误'
      });
    }
  });

  return server;
}

async function start() {
  await ensureStore(DEFAULT_DATA_FILE);
  const server = createServer();
  server.listen(DEFAULT_PORT, () => {
    console.log(`出口成章 app 已启动: http://127.0.0.1:${DEFAULT_PORT}`);
  });
}

if (require.main === module) {
  start();
}

module.exports = {
  createServer,
  DEFAULT_DATA_FILE,
  DEFAULT_PUBLIC_DIR
};
