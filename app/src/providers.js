const { createTranscript, transcribePayload } = require('./domain');
const { postJson, getJson } = require('./http-client');

function pickValue(value, fallback) {
  if (Array.isArray(value)) return value.length ? value : fallback;
  return value || fallback;
}

function buildLocalSttUnavailable() {
  return {
    ok: false,
    provider: 'local-stt',
    installed: false,
    error: 'LOCAL_STT_NOT_CONFIGURED'
  };
}

function buildFallbackUnavailable() {
  return {
    ok: false,
    provider: 'stt-http-fallback',
    enabled: false
  };
}

function createLocalProvider({ llmSwitch, localStt, sttHttpFallback, xfyunStt } = {}) {
  return {
    name: 'local',
    async healthCheck() {
      const llmStatus = llmSwitch ? await llmSwitch.status() : null;
      let sttStatus = buildLocalSttUnavailable();
      if (localStt) {
        try {
          sttStatus = await localStt.healthCheck();
        } catch (error) {
          sttStatus = {
            ok: false,
            provider: 'local-stt',
            installed: false,
            error: error instanceof Error ? error.message : '未知错误'
          };
        }
      }
      let sttFallbackStatus = buildFallbackUnavailable();
      if (sttHttpFallback) {
        try {
          sttFallbackStatus = { ...(await sttHttpFallback.healthCheck()), enabled: true };
        } catch (error) {
          sttFallbackStatus = {
            ok: false,
            provider: 'stt-http-fallback',
            enabled: true,
            error: error instanceof Error ? error.message : '未知错误'
          };
        }
      }

      let xfyunStatus = { ok: false, provider: 'xfyun-stt', enabled: false };
      if (xfyunStt) {
        try {
          xfyunStatus = await xfyunStt.healthCheck();
        } catch (error) {
          xfyunStatus = {
            ok: false,
            provider: 'xfyun-stt',
            enabled: xfyunStt.enabled || false,
            error: error instanceof Error ? error.message : '未知错误'
          };
        }
      }

      return {
        ok: true,
        provider: 'local',
        mode: 'embedded',
        stt: sttStatus,
        sttFallback: sttFallbackStatus,
        xfyun: xfyunStatus,
        llm: llmStatus
          ? {
              enabled: llmStatus.enabled,
              activeProfileId: llmStatus.activeProfileId,
              activeModel: llmStatus.activeProfile?.model || null
            }
          : { enabled: false },
        checkedAt: new Date().toISOString()
      };
    },
    async transcribe({ rawText, scene, inputSource, captureMeta, audioBase64, audioMimeType, audioName, prompt }) {
      if (audioBase64) {
        let lastError = null;

        // 1. 优先尝试讯飞STT
        if (xfyunStt && xfyunStt.enabled) {
          try {
            const result = await xfyunStt.transcribeAudio({
              audioBase64,
              audioMimeType,
              audioName
            });
            return transcribePayload(result.text || '', scene || 'general', {
              inputSource: inputSource || 'speech',
              captureMeta: captureMeta || null,
              language: result.language || 'zh-CN',
              duration: result.duration,
              wordCount: result.wordCount,
              provider: result.provider || 'xfyun-stt',
              audioMeta: result.audioMeta,
              segments: result.segments
            });
          } catch (error) {
            lastError = error;
            console.warn('[出口成章] 讯飞STT失败，尝试fallback:', error.message);
          }
        }

        // 2. 本地 faster-whisper
        if (localStt) {
          try {
            const result = await localStt.transcribeAudio({
              audioBase64,
              audioMimeType,
              audioName,
              prompt
            });
            return transcribePayload(result.text || '', scene || 'general', {
              inputSource: inputSource || 'speech',
              captureMeta: captureMeta || null,
              language: result.language,
              duration: result.duration,
              wordCount: result.wordCount,
              provider: result.provider || 'local-stt',
              audioMeta: result.audioMeta,
              segments: result.segments
            });
          } catch (error) {
            lastError = error;
          }
        }

        // 3. HTTP fallback
        if (sttHttpFallback) {
          const result = await sttHttpFallback.transcribeAudio({
            scene,
            inputSource: inputSource || 'speech',
            captureMeta,
            audioBase64,
            audioMimeType,
            audioName,
            prompt
          });
          return transcribePayload(result.text || '', scene || 'general', {
            inputSource: inputSource || 'speech',
            captureMeta: captureMeta || null,
            language: result.language,
            duration: result.duration,
            wordCount: result.wordCount,
            provider: result.provider || 'stt-http-fallback',
            audioMeta: result.audioMeta,
            segments: result.segments
          });
        }

        throw lastError || new Error('本地 STT 未配置，请先安装 faster-whisper 或配置 HTTP fallback');
      }

      return transcribePayload(rawText || '', scene || 'general', {
        inputSource,
        captureMeta,
        provider: 'local'
      });
    },
    async polish({ rawText, scene, mode, inputSource, captureMeta, transcriptionMeta }) {
      const fallback = createTranscript(rawText || '', scene || 'general', mode || 'concise', {
        inputSource,
        captureMeta,
        transcriptionMeta
      });

      if (!llmSwitch) {
        return {
          polishedText: fallback.polishedText,
          summaryTitle: fallback.summaryTitle,
          issues: fallback.issues,
          suggestedTags: fallback.suggestedTags,
          nextAction: fallback.nextAction,
          provider: 'local'
        };
      }

      try {
        const remote = await llmSwitch.generatePolish({ rawText, scene, mode });
        return {
          polishedText: pickValue(remote.polishedText, fallback.polishedText),
          summaryTitle: pickValue(remote.summaryTitle, fallback.summaryTitle),
          issues: pickValue(remote.issues, fallback.issues),
          suggestedTags: pickValue(remote.suggestedTags, fallback.suggestedTags),
          nextAction: pickValue(remote.nextAction, fallback.nextAction),
          provider: remote.provider || 'llm',
          model: remote.model || null
        };
      } catch (error) {
        return {
          polishedText: fallback.polishedText,
          summaryTitle: fallback.summaryTitle,
          issues: fallback.issues,
          suggestedTags: fallback.suggestedTags,
          nextAction: fallback.nextAction,
          provider: 'local-fallback',
          llmError: error instanceof Error ? error.message : '未知 LLM 错误'
        };
      }
    },
    async createTranscript(input) {
      const base = createTranscript(input.rawText || '', input.scene || 'general', input.mode || 'concise', {
        inputSource: input.inputSource,
        captureMeta: input.captureMeta,
        transcriptionMeta: input.transcriptionMeta
      });
      const polished = await this.polish(input);
      return {
        ...base,
        polishedText: polished.polishedText || base.polishedText,
        summaryTitle: polished.summaryTitle || base.summaryTitle,
        issues: Array.isArray(polished.issues) && polished.issues.length ? polished.issues : base.issues,
        suggestedTags: Array.isArray(polished.suggestedTags) && polished.suggestedTags.length ? polished.suggestedTags : base.suggestedTags,
        nextAction: polished.nextAction || base.nextAction,
        provider: polished.provider || 'local',
        llmError: polished.llmError || null,
        model: polished.model || null
      };
    }
  };
}

function createHttpProvider(config = {}) {
  const baseUrl = config.baseUrl || process.env.CKCZ_HTTP_BASE_URL;
  if (!baseUrl) {
    throw new Error('CKCZ_HTTP_BASE_URL 未配置，无法启用 http provider');
  }

  const transcribePath = config.transcribePath || process.env.CKCZ_HTTP_TRANSCRIBE_PATH || '/transcribe';
  const polishPath = config.polishPath || process.env.CKCZ_HTTP_POLISH_PATH || '/polish';
  const healthPath = config.healthPath || process.env.CKCZ_HTTP_HEALTH_PATH || '/health';

  return {
    name: 'http',
    async healthCheck() {
      const result = await getJson(new URL(healthPath, baseUrl).toString());
      return {
        ok: result?.ok !== false,
        provider: 'http',
        upstream: result,
        checkedAt: new Date().toISOString()
      };
    },
    async transcribe({ rawText, scene, inputSource, captureMeta, audioBase64, audioMimeType, audioName, prompt }) {
      return postJson(new URL(transcribePath, baseUrl).toString(), {
        rawText,
        scene,
        inputSource,
        captureMeta,
        audioBase64,
        audioMimeType,
        audioName,
        prompt
      });
    },
    async polish({ rawText, scene, mode, inputSource, captureMeta, transcriptionMeta }) {
      return postJson(new URL(polishPath, baseUrl).toString(), {
        rawText,
        scene,
        mode,
        inputSource,
        captureMeta,
        transcriptionMeta
      });
    },
    async createTranscript(input) {
      const base = createTranscript(input.rawText || '', input.scene || 'general', input.mode || 'concise', {
        inputSource: input.inputSource,
        captureMeta: input.captureMeta,
        transcriptionMeta: input.transcriptionMeta
      });

      const polished = await this.polish(input);
      return {
        ...base,
        polishedText: polished.polishedText || base.polishedText,
        summaryTitle: polished.summaryTitle || base.summaryTitle,
        issues: Array.isArray(polished.issues) ? polished.issues : base.issues,
        suggestedTags: Array.isArray(polished.suggestedTags) ? polished.suggestedTags : base.suggestedTags,
        nextAction: polished.nextAction || base.nextAction,
        provider: polished.provider || 'http'
      };
    }
  };
}

function createProviders(config = {}, extras = {}) {
  const providerName = config.name || process.env.CKCZ_PROVIDER || 'local';

  if (providerName === 'local') {
    return createLocalProvider({
      llmSwitch: extras.llmSwitch,
      localStt: extras.localStt,
      sttHttpFallback: extras.sttHttpFallback,
      xfyunStt: extras.xfyunStt
    });
  }

  if (providerName === 'http') {
    return createHttpProvider(config.http || {});
  }

  console.warn(`[出口成章] 未识别的 provider: ${providerName}，已回退到 local`);
  return createLocalProvider({
    llmSwitch: extras.llmSwitch,
    localStt: extras.localStt,
    sttHttpFallback: extras.sttHttpFallback,
    xfyunStt: extras.xfyunStt
  });
}

module.exports = {
  createProviders
};
