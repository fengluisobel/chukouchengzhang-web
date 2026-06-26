const http = require('node:http');
const { createTranscript, transcribePayload } = require('../src/domain');

function readJson(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => {
      try {
        const raw = Buffer.concat(chunks).toString('utf8').trim();
        resolve(raw ? JSON.parse(raw) : {});
      } catch (error) {
        reject(error);
      }
    });
    req.on('error', reject);
  });
}

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(payload, null, 2));
}

function createDemoProviderServer() {
  return http.createServer(async (req, res) => {
    try {
      if (req.method === 'GET' && req.url === '/health') {
        sendJson(res, 200, {
          ok: true,
          provider: 'http-demo-provider',
          checkedAt: new Date().toISOString()
        });
        return;
      }

      if (req.method === 'POST' && req.url === '/transcribe') {
        const body = await readJson(req);
        const text = body.audioBase64
          ? '这是通过 HTTP STT fallback 走出来的一段测试转写。'
          : (body.rawText || '');
        const result = transcribePayload(text, body.scene || 'general', {
          inputSource: body.inputSource || (body.audioBase64 ? 'speech' : 'text'),
          captureMeta: body.captureMeta || null,
          provider: 'http-demo-stt',
          audioMeta: body.audioBase64
            ? {
                mimeType: body.audioMimeType || null,
                fileName: body.audioName || 'audio.webm',
                sizeBytes: body.captureMeta?.sizeBytes || null
              }
            : null,
          segments: body.audioBase64
            ? [{ start: 0, end: 1.5, text }]
            : []
        });
        sendJson(res, 200, { ...result, provider: 'http-demo-stt' });
        return;
      }

      if (req.method === 'POST' && req.url === '/polish') {
        const body = await readJson(req);
        const transcript = createTranscript(body.rawText || '', body.scene || 'general', body.mode || 'concise', {
          inputSource: body.inputSource || 'text',
          captureMeta: body.captureMeta || null,
          transcriptionMeta: body.transcriptionMeta || null
        });
        sendJson(res, 200, {
          polishedText: `${transcript.polishedText} [HTTP Provider 已处理]`,
          summaryTitle: transcript.summaryTitle,
          issues: transcript.issues,
          suggestedTags: transcript.suggestedTags,
          nextAction: transcript.nextAction,
          provider: 'http-demo-llm'
        });
        return;
      }

      sendJson(res, 404, { error: 'NOT_FOUND' });
    } catch (error) {
      sendJson(res, 500, { error: 'INTERNAL_ERROR', message: error.message });
    }
  });
}

if (require.main === module) {
  const port = Number(process.env.PORT || 8000);
  const server = createDemoProviderServer();
  server.listen(port, () => {
    console.log(`HTTP demo provider 已启动: http://127.0.0.1:${port}`);
  });
}

module.exports = {
  createDemoProviderServer
};
