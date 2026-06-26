const path = require('node:path');
const fs = require('node:fs/promises');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');

const DEFAULT_SCRIPT = path.resolve(__dirname, '../scripts/faster_whisper_transcribe.py');
const DEFAULT_TIMEOUT_MS = Number(process.env.CKCZ_STT_TIMEOUT_MS || 600000);
const DEFAULT_MODEL = process.env.CKCZ_STT_MODEL || 'small';
const DEFAULT_DEVICE = process.env.CKCZ_STT_DEVICE || 'cpu';
const DEFAULT_COMPUTE_TYPE = process.env.CKCZ_STT_COMPUTE_TYPE || 'int8';
const DEFAULT_PYTHON = process.env.CKCZ_STT_PYTHON || 'python3';
const DEFAULT_MODEL_PATH = process.env.CKCZ_STT_MODEL_PATH || '';

function extFromMime(mimeType = '') {
  const map = {
    'audio/webm': '.webm',
    'audio/wav': '.wav',
    'audio/x-wav': '.wav',
    'audio/wave': '.wav',
    'audio/mpeg': '.mp3',
    'audio/mp3': '.mp3',
    'audio/mp4': '.m4a',
    'audio/x-m4a': '.m4a',
    'audio/ogg': '.ogg',
    'audio/aac': '.aac'
  };
  return map[mimeType] || '';
}

function stripDataUrlPrefix(value = '') {
  return String(value).replace(/^data:[^;]+;base64,/, '');
}

function parseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function spawnJson(command, args, { timeoutMs = DEFAULT_TIMEOUT_MS } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    const stdout = [];
    const stderr = [];
    let finished = false;

    const timer = setTimeout(() => {
      if (finished) return;
      finished = true;
      child.kill('SIGTERM');
      reject(new Error(`STT 执行超时（>${timeoutMs}ms）`));
    }, timeoutMs);

    child.stdout.on('data', (chunk) => stdout.push(chunk));
    child.stderr.on('data', (chunk) => stderr.push(chunk));
    child.on('error', (error) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      reject(error);
    });
    child.on('close', (code) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      const out = Buffer.concat(stdout).toString('utf8').trim();
      const err = Buffer.concat(stderr).toString('utf8').trim();
      if (code !== 0) {
        reject(new Error(err || out || `STT 脚本退出码 ${code}`));
        return;
      }
      const data = parseJson(out);
      if (!data) {
        reject(new Error(`STT 返回非 JSON：${out.slice(0, 200)}`));
        return;
      }
      resolve(data);
    });
  });
}

async function writeAudioTempFile({ audioBase64, audioMimeType, audioName }) {
  const raw = stripDataUrlPrefix(audioBase64 || '');
  if (!raw) {
    throw new Error('AUDIO_BASE64_REQUIRED');
  }

  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'ckcz-audio-'));
  const ext = path.extname(audioName || '') || extFromMime(audioMimeType) || '.webm';
  const filePath = path.join(dir, `${crypto.randomUUID()}${ext}`);
  const buffer = Buffer.from(raw, 'base64');
  await fs.writeFile(filePath, buffer);
  return { dir, filePath, sizeBytes: buffer.length };
}

function createLocalStt(config = {}) {
  const scriptPath = config.scriptPath || DEFAULT_SCRIPT;
  const pythonBin = config.pythonBin || DEFAULT_PYTHON;
  const model = config.model || DEFAULT_MODEL;
  const modelPath = config.modelPath || DEFAULT_MODEL_PATH;
  const device = config.device || DEFAULT_DEVICE;
  const computeType = config.computeType || DEFAULT_COMPUTE_TYPE;
  const timeoutMs = Number(config.timeoutMs || DEFAULT_TIMEOUT_MS);
  const healthTimeoutMs = Number(config.healthTimeoutMs || 10000);
  const mockResult = config.mockResult || null;

  return {
    async healthCheck() {
      if (mockResult) {
        return {
          ok: true,
          provider: 'mock-stt',
          mode: 'test-double',
          checkedAt: new Date().toISOString()
        };
      }

      const status = await spawnJson(pythonBin, [
        scriptPath,
        '--check',
        ...(modelPath ? ['--model-path', modelPath] : []),
        '--model', model
      ], { timeoutMs: healthTimeoutMs });
      return {
        ok: status?.ok !== false,
        provider: status?.provider || 'faster-whisper',
        installed: Boolean(status?.installed),
        model,
        modelPath: modelPath || null,
        device,
        computeType,
        checkedAt: new Date().toISOString(),
        details: status
      };
    },

    async transcribeAudio({ audioBase64, audioMimeType, audioName, language = 'zh', prompt = '' }) {
      if (mockResult) {
        const text = mockResult.text || '这是测试音频转写结果。';
        return {
          text,
          language: mockResult.language || 'zh-CN',
          duration: mockResult.duration || 3,
          wordCount: (mockResult.wordCount || text.length),
          provider: 'mock-stt',
          segments: mockResult.segments || [],
          audioMeta: {
            mimeType: audioMimeType || null,
            fileName: audioName || 'mock-audio.webm',
            sizeBytes: mockResult.sizeBytes || Buffer.from(stripDataUrlPrefix(audioBase64 || ''), 'base64').length
          }
        };
      }

      const temp = await writeAudioTempFile({ audioBase64, audioMimeType, audioName });
      try {
        const result = await spawnJson(pythonBin, [
          scriptPath,
          '--audio', temp.filePath,
          '--model', model,
          ...(modelPath ? ['--model-path', modelPath] : []),
          '--device', device,
          '--compute-type', computeType,
          '--language', language,
          ...(prompt ? ['--initial-prompt', prompt] : [])
        ], { timeoutMs });

        return {
          text: result.text || '',
          language: result.language || 'zh-CN',
          duration: result.duration ?? null,
          wordCount: result.wordCount ?? String(result.text || '').length,
          provider: result.provider || 'faster-whisper',
          segments: Array.isArray(result.segments) ? result.segments : [],
          model: result.model || model,
          audioMeta: {
            mimeType: audioMimeType || null,
            fileName: audioName || path.basename(temp.filePath),
            sizeBytes: temp.sizeBytes
          }
        };
      } finally {
        await fs.rm(temp.dir, { recursive: true, force: true });
      }
    }
  };
}

module.exports = {
  createLocalStt
};
