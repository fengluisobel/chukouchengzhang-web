const path = require('node:path');
const fs = require('node:fs/promises');

const { requestJson } = require('./http-client');

const DEFAULT_LLM_CONFIG_FILE = path.resolve(__dirname, '../config/llm-profiles.json');
const DEFAULT_LLM_SETTINGS_FILE = path.resolve(__dirname, '../data/llm-settings.json');

function clip(value, size = 48) {
  const text = String(value || '');
  return text.length <= size ? text : `${text.slice(0, size)}…`;
}

function sanitizeProfile(profile = {}) {
  return {
    id: profile.id,
    name: profile.name || profile.id,
    baseUrl: profile.baseUrl,
    model: profile.model,
    chatPath: profile.chatPath || '/v1/chat/completions',
    enabled: profile.enabled !== false,
    hasKey: Boolean(profile.apiKey),
    note: profile.note || ''
  };
}

async function readJsonFile(filePath, fallback) {
  try {
    const text = await fs.readFile(filePath, 'utf8');
    return JSON.parse(text);
  } catch (error) {
    if (error && error.code === 'ENOENT') return fallback;
    throw error;
  }
}

async function writeJsonFile(filePath, payload) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, JSON.stringify(payload, null, 2), 'utf8');
}

function normalizeProfilesDocument(doc) {
  if (!doc) {
    return { activeProfileId: null, profiles: [] };
  }

  if (Array.isArray(doc)) {
    return { activeProfileId: null, profiles: doc };
  }

  return {
    activeProfileId: doc.activeProfileId || doc.defaultProfileId || null,
    profiles: Array.isArray(doc.profiles) ? doc.profiles : []
  };
}

function normalizeProfile(profile = {}) {
  return {
    id: String(profile.id || '').trim(),
    name: String(profile.name || profile.id || '').trim(),
    baseUrl: String(profile.baseUrl || '').trim(),
    apiKey: String(profile.apiKey || '').trim(),
    model: String(profile.model || '').trim(),
    chatPath: String(profile.chatPath || '/v1/chat/completions').trim(),
    enabled: profile.enabled !== false,
    headers: profile.headers && typeof profile.headers === 'object' ? profile.headers : {},
    authType: profile.authType || 'bearer',
    note: String(profile.note || '').trim()
  };
}

function extractMessageContent(payload) {
  const content = payload?.choices?.[0]?.message?.content;
  if (typeof content === 'string') return content.trim();
  if (Array.isArray(content)) {
    return content
      .map((item) => (typeof item?.text === 'string' ? item.text : ''))
      .join(' ')
      .trim();
  }
  return '';
}

function stripCodeFence(text = '') {
  return String(text)
    .replace(/^```json\s*/i, '')
    .replace(/^```\s*/i, '')
    .replace(/```$/i, '')
    .trim();
}

function buildAuthHeaders(profile) {
  const headers = { ...(profile.headers || {}) };
  if (!profile.apiKey) return headers;

  if (profile.authType === 'x-api-key') {
    headers['x-api-key'] = profile.apiKey;
    return headers;
  }

  if (!headers.Authorization && !headers.authorization) {
    headers.Authorization = `Bearer ${profile.apiKey}`;
  }

  return headers;
}

function buildPrompt({ rawText, scene, mode }) {
  return [
    '你是一个中文表达优化助手。',
    '请把用户原始表达整理成更清晰、更有结构、更适合真实沟通的版本。',
    '必须只输出 JSON，不要输出额外解释。',
    'JSON 格式如下：',
    '{',
    '  "polishedText": "优化后的完整文本",',
    '  "summaryTitle": "14字以内标题",',
    '  "issues": [{"title":"问题标题","detail":"问题说明"}],',
    '  "suggestedTags": ["标签1", "标签2"],',
    '  "nextAction": "一句明确的下一步建议"',
    '}',
    `当前场景：${scene}`,
    `当前风格：${mode}`,
    `用户原文：${rawText}`
  ].join('\n');
}

function createLlmSwitch({ configFile = DEFAULT_LLM_CONFIG_FILE, settingsFile = DEFAULT_LLM_SETTINGS_FILE } = {}) {
  async function loadProfiles() {
    const doc = normalizeProfilesDocument(await readJsonFile(configFile, null));
    const profiles = doc.profiles.map(normalizeProfile).filter((item) => item.id && item.baseUrl && item.model);
    const settings = await readJsonFile(settingsFile, {});
    const activeProfileId = settings.activeProfileId || doc.activeProfileId || null;

    return { profiles, activeProfileId };
  }

  async function getActiveProfile() {
    const { profiles, activeProfileId } = await loadProfiles();
    const enabledProfiles = profiles.filter((item) => item.enabled !== false);
    if (!enabledProfiles.length) return null;
    return enabledProfiles.find((item) => item.id === activeProfileId) || enabledProfiles[0];
  }

  async function status() {
    const { profiles, activeProfileId } = await loadProfiles();
    const activeProfile = profiles.find((item) => item.id === activeProfileId)
      || profiles.find((item) => item.enabled !== false)
      || null;

    return {
      enabled: profiles.some((item) => item.enabled !== false),
      configuredCount: profiles.length,
      activeProfileId: activeProfile?.id || null,
      activeProfile: activeProfile ? sanitizeProfile(activeProfile) : null,
      profiles: profiles.map(sanitizeProfile),
      configFile,
      settingsFile
    };
  }

  async function switchProfile(profileId) {
    const { profiles } = await loadProfiles();
    const matched = profiles.find((item) => item.id === profileId && item.enabled !== false);
    if (!matched) {
      throw new Error(`未找到可用 LLM profile：${profileId}`);
    }

    await writeJsonFile(settingsFile, { activeProfileId: matched.id, updatedAt: new Date().toISOString() });
    return status();
  }

  async function generatePolish(input) {
    const activeProfile = await getActiveProfile();
    if (!activeProfile) {
      throw new Error('当前未配置可用 LLM profile');
    }

    if (!activeProfile.apiKey) {
      throw new Error(`LLM profile ${activeProfile.id} 缺少 apiKey`);
    }

    const payload = await requestJson(new URL(activeProfile.chatPath, activeProfile.baseUrl).toString(), {
      method: 'POST',
      headers: buildAuthHeaders(activeProfile),
      body: {
        model: activeProfile.model,
        temperature: 0.3,
        response_format: { type: 'json_object' },
        messages: [
          {
            role: 'system',
            content: '你是一个严格按 JSON 输出的中文表达优化助手。'
          },
          {
            role: 'user',
            content: buildPrompt(input)
          }
        ]
      }
    });

    const rawContent = stripCodeFence(extractMessageContent(payload));
    if (!rawContent) {
      throw new Error(`LLM 返回为空：${activeProfile.id}`);
    }

    let parsed;
    try {
      parsed = JSON.parse(rawContent);
    } catch (error) {
      throw new Error(`LLM 返回非 JSON，profile=${activeProfile.id}，content=${clip(rawContent)}`);
    }

    return {
      polishedText: parsed.polishedText,
      summaryTitle: parsed.summaryTitle,
      issues: Array.isArray(parsed.issues) ? parsed.issues : [],
      suggestedTags: Array.isArray(parsed.suggestedTags) ? parsed.suggestedTags : [],
      nextAction: parsed.nextAction,
      provider: `llm:${activeProfile.id}`,
      model: activeProfile.model
    };
  }

  return {
    status,
    switchProfile,
    getActiveProfile,
    generatePolish
  };
}

module.exports = {
  createLlmSwitch,
  DEFAULT_LLM_CONFIG_FILE,
  DEFAULT_LLM_SETTINGS_FILE
};
