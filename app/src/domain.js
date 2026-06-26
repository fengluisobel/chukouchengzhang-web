const crypto = require('node:crypto');

const fillerWords = ['就是', '然后', '那个', '其实', '怎么说', '有点', '可能', '感觉', '我觉得'];

const sceneLabels = {
  general: '通用',
  report: '汇报',
  pitch: '口播',
  interview: '面试',
  idea: '灵感'
};

const scenePrefixes = {
  general: '我想表达的是',
  report: '本次汇报的核心结论是',
  pitch: '这次想讲清楚的是',
  interview: '我的回答可以概括为',
  idea: '这个产品灵感的核心是'
};

const modeSuffix = {
  concise: '整体改为短句优先，突出重点。',
  formal: '表达风格更稳，更适合正式场景。',
  spoken: '保留口语感，但去掉明显赘述。',
  executive: '按结论先行方式组织，适合管理沟通。'
};

function uid(prefix) {
  return `${prefix}_${crypto.randomUUID()}`;
}

function normalizeText(text = '') {
  return String(text)
    .replace(/\r/g, '')
    .replace(/\s+/g, ' ')
    .replace(/[，,]{2,}/g, '，')
    .replace(/[。.!！?？]{2,}/g, '。')
    .trim();
}

function splitSentences(text) {
  return normalizeText(text)
    .split(/[。！？!?；;\n]/)
    .map((item) => item.trim().replace(/^，+|，+$/g, ''))
    .filter(Boolean);
}

function findFillerHits(text) {
  return fillerWords.filter((word) => text.includes(word));
}

function summarizeTitle(text) {
  const clean = normalizeText(text).replace(/[，。！？!?；;]/g, '');
  if (!clean) return '未命名表达';
  return clean.slice(0, 14) + (clean.length > 14 ? '…' : '');
}

function suggestTags(scene, rawText) {
  const tags = new Set([sceneLabels[scene] || '表达']);
  const text = normalizeText(rawText);

  if (/产品|功能|用户|需求|增长|Demo/i.test(text)) tags.add('产品表达');
  if (/汇报|结论|进度|目标/i.test(text)) tags.add('汇报');
  if (/训练|提升|复述|表达/i.test(text)) tags.add('表达训练');
  if (/灵感|点子|想法|方案/i.test(text)) tags.add('灵感');
  if (text.length > 80) tags.add('长表达');

  return Array.from(tags).slice(0, 4);
}

function buildIssues(rawText) {
  const text = normalizeText(rawText);
  const sentences = splitSentences(text);
  const issues = [];
  const fillerHits = findFillerHits(text);

  if (fillerHits.length) {
    issues.push({
      title: '口头填充词偏多',
      detail: `检测到 ${fillerHits.join('、')} 等口头填充词，建议删掉后再突出重点。`
    });
  }

  if (text.length > 80 || sentences.some((item) => item.length > 35)) {
    issues.push({
      title: '句子偏长',
      detail: '当前表达承载信息较多，适合拆成 2~3 个短句，降低听感负担。'
    });
  }

  if (sentences.length <= 1) {
    issues.push({
      title: '结构层次不明显',
      detail: '建议使用“先结论、再解释、最后行动”的结构，听感会更稳。'
    });
  }

  if (!/因为|所以|目标|价值|结果|下一步/.test(text)) {
    issues.push({
      title: '价值点未被点亮',
      detail: '可以补一层“为什么重要 / 带来什么结果”，让表达更完整。'
    });
  }

  if (issues.length === 0) {
    issues.push({
      title: '还可以更利落',
      detail: '整体已经比较清楚，下一步可继续压缩冗词并强化结论句。'
    });
  }

  return issues.slice(0, 4);
}

function polishText(rawText, scene = 'general', mode = 'concise') {
  const text = normalizeText(rawText);
  const sentences = splitSentences(text);
  const main = sentences.length ? sentences : [text];
  const first = main[0] || text;
  const rest = main.slice(1);
  const prefix = scenePrefixes[scene] || scenePrefixes.general;
  const suffix = modeSuffix[mode] || modeSuffix.concise;

  const rebuilt = [
    `${prefix}：${first.replace(/^我想|^我觉得|^就是|^其实/, '')}`,
    ...rest.map((item, index) => `补充点 ${index + 1}：${item}`),
    `下一步建议：先把核心观点压成 1 句话，再补 2 个支撑点。${suffix}`
  ]
    .filter(Boolean)
    .join(' ')
    .replace(/：\s+/g, '：')
    .replace(/\s+/g, ' ')
    .trim();

  return rebuilt;
}

function transcribePayload(rawText, scene = 'general', meta = {}) {
  const text = normalizeText(rawText);
  const inputSource = meta.inputSource || 'text';
  const captureMeta = meta.captureMeta || null;

  return {
    text,
    language: meta.language || 'zh-CN',
    duration: meta.duration ?? captureMeta?.durationSeconds ?? Math.max(3, Math.ceil(text.length / 4)),
    wordCount: meta.wordCount ?? text.length,
    scene,
    inputSource,
    captureMeta,
    provider: meta.provider || 'local',
    audioMeta: meta.audioMeta || null,
    segments: Array.isArray(meta.segments) ? meta.segments : []
  };
}

function createTranscript(rawText, scene = 'general', mode = 'concise', meta = {}) {
  const normalized = normalizeText(rawText);
  const polished = polishText(normalized, scene, mode);
  const inputSource = meta.inputSource || 'text';
  const captureMeta = meta.captureMeta || null;
  const transcriptionMeta = meta.transcriptionMeta || null;

  return {
    id: uid('ts'),
    createdAt: new Date().toISOString(),
    scene,
    mode,
    inputSource,
    captureMeta,
    transcriptionMeta,
    rawText: normalized,
    polishedText: polished,
    summaryTitle: summarizeTitle(polished),
    suggestedTags: suggestTags(scene, normalized),
    nextAction: '用优化稿复述 1 次，再对照训练结果继续收紧表达。',
    issues: buildIssues(normalized),
    stats: transcribePayload(normalized, scene, { inputSource, captureMeta })
  };
}

function charSet(text) {
  return new Set(normalizeText(text).replace(/[\s，。！？!?；;：:,]/g, '').split(''));
}

function similarity(a, b) {
  const setA = charSet(a);
  const setB = charSet(b);
  if (!setA.size || !setB.size) return 0;
  let overlap = 0;
  for (const ch of setA) {
    if (setB.has(ch)) overlap += 1;
  }
  return overlap / Math.max(setA.size, setB.size);
}

function evaluateAttempt({ polishedText, rawText, attemptText, round = 1 }) {
  const attempt = normalizeText(attemptText);
  const structureCueCount = ['首先', '然后', '最后', '总结', '核心', '所以', '下一步'].filter((cue) => attempt.includes(cue)).length;
  const simToPolished = similarity(polishedText, attempt);
  const simToRaw = similarity(rawText, attempt);

  const clarityScore = Math.min(100, Math.max(35, Math.round(55 + simToPolished * 35 + structureCueCount * 2)));
  const structureScore = Math.min(100, Math.max(30, Math.round(50 + structureCueCount * 8 + simToPolished * 18)));
  const polishScore = Math.min(100, Math.max(28, Math.round(48 + simToPolished * 28 + simToRaw * 12)));

  const improvedPoints = [];
  if (simToPolished > 0.55) improvedPoints.push('复述已经贴近优化稿主线');
  if (structureCueCount >= 2) improvedPoints.push('已经开始主动使用结构词组织表达');
  if (attempt.length <= polishedText.length * 1.2) improvedPoints.push('表达更收敛，没有明显发散');
  if (improvedPoints.length === 0) improvedPoints.push('核心观点已经出现，继续压缩表达会更稳');

  const feedback = structureCueCount >= 2
    ? '这轮复述比上一版更成型，主线更稳，继续把开头结论再说得更硬一点。'
    : '核心意思已经出来了，但结构提示词还不够，建议用“结论 - 原因 - 下一步”再说一遍。';

  return {
    id: uid('tr'),
    createdAt: new Date().toISOString(),
    round,
    text: attempt,
    clarityScore,
    structureScore,
    polishScore,
    feedback,
    improvedPoints
  };
}

function categorizeIdea(scene, text) {
  if (scene === 'idea') return '产品点子';
  if (/功能|需求|改版|模块/.test(text)) return '功能需求';
  if (/商业|变现|定价|订阅/.test(text)) return '商业模式';
  if (/验证|假设|实验/.test(text)) return '待验证假设';
  return '内容选题';
}

function archiveIdea(transcript) {
  const titleBase = summarizeTitle(transcript.polishedText).replace(/…$/, '');
  return {
    id: uid('idea'),
    createdAt: new Date().toISOString(),
    transcriptId: transcript.id,
    title: titleBase || '新的灵感卡片',
    rawInput: transcript.rawText,
    normalizedText: transcript.polishedText,
    category: categorizeIdea(transcript.scene, transcript.rawText),
    tags: transcript.suggestedTags,
    nextAction: transcript.nextAction,
    status: '已归档'
  };
}

function buildDailyReport(store) {
  const totalWords = store.transcripts.reduce((sum, item) => sum + (item?.stats?.wordCount || item.rawText?.length || 0), 0);
  const catchphraseCount = store.transcripts.reduce((sum, item) => sum + findFillerHits(item.rawText || '').length, 0);
  const bestTranscript = [...store.transcripts].sort((a, b) => (b.polishedText?.length || 0) - (a.polishedText?.length || 0))[0];
  const speechInputCount = store.transcripts.filter((item) => item.inputSource === 'speech').length;

  return {
    totalWords,
    transcribeCount: store.transcripts.length,
    trainingCount: store.trainingAttempts.length,
    polishCount: store.transcripts.length,
    catchphraseCount,
    speechInputCount,
    bestSentence: bestTranscript?.polishedText || '今天先开口，明天再打磨。'
  };
}

module.exports = {
  normalizeText,
  transcribePayload,
  createTranscript,
  evaluateAttempt,
  archiveIdea,
  buildDailyReport,
  sceneLabels
};
