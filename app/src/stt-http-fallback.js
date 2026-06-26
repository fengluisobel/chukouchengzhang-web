const { postJson, getJson } = require('./http-client');

function createSttHttpFallback(config = {}) {
  const baseUrl = config.baseUrl || process.env.CKCZ_STT_HTTP_BASE_URL || process.env.CKCZ_HTTP_BASE_URL;
  if (!baseUrl) return null;

  const transcribePath = config.transcribePath || process.env.CKCZ_STT_HTTP_TRANSCRIBE_PATH || process.env.CKCZ_HTTP_TRANSCRIBE_PATH || '/transcribe';
  const healthPath = config.healthPath || process.env.CKCZ_STT_HTTP_HEALTH_PATH || process.env.CKCZ_HTTP_HEALTH_PATH || '/health';

  return {
    async healthCheck() {
      const result = await getJson(new URL(healthPath, baseUrl).toString());
      return {
        ok: result?.ok !== false,
        provider: 'stt-http-fallback',
        baseUrl,
        upstream: result,
        checkedAt: new Date().toISOString()
      };
    },

    async transcribeAudio({ scene, inputSource, captureMeta, audioBase64, audioMimeType, audioName, prompt }) {
      const result = await postJson(new URL(transcribePath, baseUrl).toString(), {
        scene,
        inputSource,
        captureMeta,
        audioBase64,
        audioMimeType,
        audioName,
        prompt
      });

      return {
        text: result.text || '',
        language: result.language || 'zh-CN',
        duration: result.duration ?? null,
        wordCount: result.wordCount ?? String(result.text || '').length,
        provider: result.provider || 'http-stt',
        segments: Array.isArray(result.segments) ? result.segments : [],
        audioMeta: result.audioMeta || {
          mimeType: audioMimeType || null,
          fileName: audioName || null,
          sizeBytes: captureMeta?.sizeBytes || null
        }
      };
    }
  };
}

module.exports = {
  createSttHttpFallback
};
