const state = {
  transcripts: [],
  ideas: [],
  trainingAttempts: [],
  report: null,
  providerStatus: null,
  llmStatus: null,
  selectedTranscriptId: null,
  section: 'home',
  activeInputSource: 'text',
  tts: {
    supported: false,
    speaking: false,
    voices: []
  },
  voice: {
    supported: false,
    recognition: null,
    isListening: false,
    finalText: '',
    interimText: '',
    startedAt: null,
    timer: null
  }
};

const sectionTitles = {
  home: ['首页', '今天先把主流程跑通，再继续打磨。'],
  record: ['开始录音', '现在已经支持浏览器语音识别，能直接开口试用。'],
  result: ['结果页', '原文、优化稿与问题分析都在这里。'],
  training: ['训练页', '复述一次，看看表达是否更清楚。'],
  ideas: ['灵感库', '把能继续发育的想法收进来。'],
  report: ['报告页', '把今天的表达行为量化出来。']
};

const els = {};

document.addEventListener('DOMContentLoaded', () => {
  bindElements();
  bindEvents();
  initVoiceRecognition();
  initSpeechSynthesis();
  boot();
});

function bindElements() {
  els.pageTitle = document.getElementById('page-title');
  els.pageSubtitle = document.getElementById('page-subtitle');
  els.navItems = Array.from(document.querySelectorAll('.nav-item'));
  els.sections = Array.from(document.querySelectorAll('.section'));
  els.sceneSelect = document.getElementById('scene-select');
  els.modeSelect = document.getElementById('mode-select');
  els.recordInput = document.getElementById('record-input');
  els.fillDemoButton = document.getElementById('fill-demo-button');
  els.generateButton = document.getElementById('generate-button');
  els.startVoiceButton = document.getElementById('start-voice-button');
  els.stopVoiceButton = document.getElementById('stop-voice-button');
  els.clearInputButton = document.getElementById('clear-input-button');
  els.voiceSupportText = document.getElementById('voice-support-text');
  els.voiceStatus = document.getElementById('voice-status');
  els.importButton = document.getElementById('import-button');
  els.importFileInput = document.getElementById('import-file-input');
  els.audioFileInput = document.getElementById('audio-file-input');
  els.uploadAudioButton = document.getElementById('upload-audio-button');
  els.audioUploadStatus = document.getElementById('audio-upload-status');
  els.exportButton = document.getElementById('export-button');
  els.recentList = document.getElementById('recent-list');
  els.recentCount = document.getElementById('recent-count');
  els.rawText = document.getElementById('raw-text');
  els.polishedText = document.getElementById('polished-text');
  els.speakPolishedButton = document.getElementById('speak-polished-button');
  els.stopSpeakButton = document.getElementById('stop-speak-button');
  els.speakTrainingButton = document.getElementById('speak-training-button');
  els.ttsStatus = document.getElementById('tts-status');
  els.resultScene = document.getElementById('result-scene');
  els.resultSource = document.getElementById('result-source');
  els.issuesList = document.getElementById('issues-list');
  els.resultEmpty = document.getElementById('result-empty');
  els.resultContent = document.getElementById('result-content');
  els.archiveButton = document.getElementById('archive-button');
  els.trainingEmpty = document.getElementById('training-empty');
  els.trainingContent = document.getElementById('training-content');
  els.trainingStandardText = document.getElementById('training-standard-text');
  els.attemptInput = document.getElementById('attempt-input');
  els.fillAttemptButton = document.getElementById('fill-attempt-button');
  els.evaluateButton = document.getElementById('evaluate-button');
  els.trainingList = document.getElementById('training-list');
  els.ideasList = document.getElementById('ideas-list');
  els.ideaCountLabel = document.getElementById('idea-count-label');
  els.reportTranscribeCount = document.getElementById('report-transcribe-count');
  els.reportPolishCount = document.getElementById('report-polish-count');
  els.reportCatchphraseCount = document.getElementById('report-catchphrase-count');
  els.reportSpeechCount = document.getElementById('report-speech-count');
  els.reportBestSentence = document.getElementById('report-best-sentence');
  els.statTotalWords = document.getElementById('stat-total-words');
  els.statTrainingCount = document.getElementById('stat-training-count');
  els.statSpeechCount = document.getElementById('stat-speech-count');
  els.statIdeaCount = document.getElementById('stat-idea-count');
  els.providerStatusChip = document.getElementById('provider-status-chip');
  els.providerStatusText = document.getElementById('provider-status-text');
  els.llmStatusChip = document.getElementById('llm-status-chip');
  els.llmStatusText = document.getElementById('llm-status-text');
  els.llmProfileSelect = document.getElementById('llm-profile-select');
  els.llmSwitchButton = document.getElementById('llm-switch-button');
  els.toast = document.getElementById('toast');
  els.resetButton = document.getElementById('reset-button');
}

function bindEvents() {
  els.navItems.forEach((button) => {
    button.addEventListener('click', () => setSection(button.dataset.section));
  });

  document.querySelectorAll('[data-goto]').forEach((button) => {
    button.addEventListener('click', () => setSection(button.dataset.goto));
  });

  els.fillDemoButton.addEventListener('click', () => {
    state.activeInputSource = 'demo';
    els.recordInput.value = '我想做一个结合语音转写和表达训练的产品，它不只是把你说的话记下来，还会帮你整理成更有逻辑的版本，并且让你重新说一遍，看看表达有没有进步。';
    els.sceneSelect.value = 'idea';
    els.modeSelect.value = 'concise';
  });

  els.recordInput.addEventListener('input', () => {
    if (!state.voice.isListening) {
      state.activeInputSource = els.recordInput.value.trim() ? 'text' : state.activeInputSource;
    }
  });

  els.generateButton.addEventListener('click', createTranscript);
  els.archiveButton.addEventListener('click', archiveIdea);
  els.fillAttemptButton.addEventListener('click', () => {
    els.attemptInput.value = '这个产品的核心是把用户的口头表达整理成更清晰的内容，再通过复述训练帮助用户持续提升表达能力。';
  });
  els.evaluateButton.addEventListener('click', evaluateTraining);
  els.resetButton.addEventListener('click', resetDemoData);
  els.startVoiceButton.addEventListener('click', startVoiceInput);
  els.stopVoiceButton.addEventListener('click', stopVoiceInput);
  els.clearInputButton.addEventListener('click', clearRecordInput);
  els.importButton.addEventListener('click', () => els.importFileInput.click());
  els.importFileInput.addEventListener('change', importDataFromFile);
  els.uploadAudioButton.addEventListener('click', () => els.audioFileInput.click());
  els.audioFileInput.addEventListener('change', uploadAudioFile);
  els.exportButton.addEventListener('click', exportData);
  els.llmSwitchButton.addEventListener('click', switchLlmProfile);
  els.speakPolishedButton.addEventListener('click', () => speakText(selectedTranscript()?.polishedText || ''));
  els.speakTrainingButton.addEventListener('click', () => speakText(selectedTranscript()?.polishedText || ''));
  els.stopSpeakButton.addEventListener('click', stopSpeaking);
}

function initSpeechSynthesis() {
  const synth = window.speechSynthesis;
  if (!synth) {
    state.tts.supported = false;
    syncTtsStatus('当前浏览器不支持原生朗读');
    return;
  }

  state.tts.supported = true;
  const loadVoices = () => {
    state.tts.voices = synth.getVoices() || [];
  };
  loadVoices();
  if (typeof synth.onvoiceschanged !== 'undefined') {
    synth.onvoiceschanged = loadVoices;
  }
  syncTtsStatus('浏览器朗读就绪。');
}

function initVoiceRecognition() {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRecognition) {
    state.voice.supported = false;
    els.voiceSupportText.textContent = '当前浏览器不支持原生语音识别。你仍然可以直接输入文本，或换 Chrome 再试。';
    els.startVoiceButton.disabled = true;
    els.voiceStatus.textContent = '语音识别不可用';
    return;
  }

  state.voice.supported = true;
  els.voiceSupportText.textContent = '当前浏览器支持语音识别。点击“开始语音输入”后，直接说话，识别结果会实时进入输入框。';

  const recognition = new SpeechRecognition();
  recognition.lang = 'zh-CN';
  recognition.continuous = true;
  recognition.interimResults = true;

  recognition.onstart = () => {
    state.voice.isListening = true;
    state.voice.startedAt = Date.now();
    state.activeInputSource = 'speech';
    state.voice.finalText = '';
    state.voice.interimText = '';
    els.startVoiceButton.disabled = true;
    els.stopVoiceButton.disabled = false;
    syncVoiceStatus();
    startVoiceTimer();
  };

  recognition.onresult = (event) => {
    let finalText = '';
    let interimText = '';

    for (let index = 0; index < event.results.length; index += 1) {
      const result = event.results[index];
      const text = result[0]?.transcript || '';
      if (result.isFinal) {
        finalText += text;
      } else {
        interimText += text;
      }
    }

    if (finalText) {
      state.voice.finalText = mergeSpeechText(state.voice.finalText, finalText);
    }
    state.voice.interimText = interimText.trim();
    updateRecordInputFromVoice();
    syncVoiceStatus();
  };

  recognition.onerror = (event) => {
    syncVoiceStatus(`语音识别出错：${event.error}`);
  };

  recognition.onend = () => {
    state.voice.isListening = false;
    els.startVoiceButton.disabled = false;
    els.stopVoiceButton.disabled = true;
    stopVoiceTimer();
    updateRecordInputFromVoice();
    syncVoiceStatus(state.voice.finalText ? '语音输入已结束，可直接生成结果。' : '语音输入已停止。');
  };

  state.voice.recognition = recognition;
  syncVoiceStatus('准备就绪');
}

async function boot() {
  await refreshAll();
  setSection('home');
}

async function refreshAll() {
  const [transcripts, ideas, report, providerStatus, llmStatus] = await Promise.all([
    api('/api/transcripts'),
    api('/api/ideas'),
    api('/api/reports/daily'),
    api('/api/provider/status').catch((error) => ({ ok: false, provider: 'unknown', message: error.message })),
    api('/api/llm/status').catch((error) => ({ enabled: false, profiles: [], message: error.message }))
  ]);

  state.transcripts = transcripts;
  state.ideas = ideas;
  state.report = report;
  state.providerStatus = providerStatus;
  state.llmStatus = llmStatus;

  if (!state.selectedTranscriptId && state.transcripts[0]) {
    state.selectedTranscriptId = state.transcripts[0].id;
  }

  if (state.selectedTranscriptId) {
    state.trainingAttempts = await api(`/api/training?transcriptId=${encodeURIComponent(state.selectedTranscriptId)}`);
  } else {
    state.trainingAttempts = [];
  }

  render();
}

function setSection(section) {
  state.section = section;
  const [title, subtitle] = sectionTitles[section] || ['出口成章', ''];
  els.pageTitle.textContent = title;
  els.pageSubtitle.textContent = subtitle;

  els.navItems.forEach((item) => item.classList.toggle('active', item.dataset.section === section));
  els.sections.forEach((item) => item.classList.toggle('active', item.id === `${section}-section`));
  render();
}

function render() {
  renderHome();
  renderResult();
  renderTraining();
  renderIdeas();
  renderReport();
  renderTtsControls();
}

function renderHome() {
  els.statTotalWords.textContent = String(state.report?.totalWords || 0);
  els.statTrainingCount.textContent = String(state.report?.trainingCount || 0);
  els.statSpeechCount.textContent = String(state.report?.speechInputCount || 0);
  els.statIdeaCount.textContent = String(state.ideas.length || 0);
  els.recentCount.textContent = state.transcripts.length ? `${state.transcripts.length} 条记录` : '暂无记录';

  const providerOk = state.providerStatus?.ok !== false;
  const providerName = state.providerStatus?.provider || 'unknown';
  els.providerStatusChip.textContent = providerOk ? `${providerName} 正常` : `${providerName} 异常`;
  els.providerStatusChip.classList.toggle('is-live', providerOk);
  els.providerStatusText.textContent = providerOk
    ? providerStatusMessage(state.providerStatus)
    : `Provider 检查失败：${state.providerStatus?.message || '未知错误'}`;

  renderLlmStatus();
  renderAudioStatus();

  if (!state.transcripts.length) {
    els.recentList.className = 'stack empty-state';
    els.recentList.textContent = '还没有内容，去录一段吧。';
    return;
  }

  els.recentList.className = 'stack';
  els.recentList.innerHTML = state.transcripts
    .slice(0, 5)
    .map((item) => `
      <div class="transcript-item">
        <div class="card-header">
          <strong>${escapeHtml(item.summaryTitle || '未命名')}</strong>
          <span class="pill">${escapeHtml(sceneLabel(item.scene))}</span>
        </div>
        <div class="meta-row">
          <span>来源：${escapeHtml(inputSourceLabel(item.inputSource))}</span>
          <span>${escapeHtml(formatDateTime(item.createdAt))}</span>
        </div>
        <p>${escapeHtml(item.polishedText)}</p>
        <button class="ghost-button" data-select-transcript="${item.id}">查看这条结果</button>
      </div>
    `)
    .join('');

  els.recentList.querySelectorAll('[data-select-transcript]').forEach((button) => {
    button.addEventListener('click', async () => {
      state.selectedTranscriptId = button.dataset.selectTranscript;
      state.trainingAttempts = await api(`/api/training?transcriptId=${encodeURIComponent(state.selectedTranscriptId)}`);
      setSection('result');
    });
  });
}

function renderLlmStatus() {
  const llmStatus = state.llmStatus || { enabled: false, profiles: [] };
  const profiles = Array.isArray(llmStatus.profiles) ? llmStatus.profiles : [];
  const activeProfileId = llmStatus.activeProfileId || profiles[0]?.id || '';
  const activeProfile = profiles.find((item) => item.id === activeProfileId) || llmStatus.activeProfile || null;

  els.llmProfileSelect.innerHTML = profiles.length
    ? profiles
        .map((profile) => `<option value="${escapeHtml(profile.id)}" ${profile.id === activeProfileId ? 'selected' : ''}>${escapeHtml(profile.name || profile.id)} / ${escapeHtml(profile.model || '')}</option>`)
        .join('')
    : '<option value="">未配置 LLM profile</option>';

  const llmReady = Boolean(llmStatus.enabled && activeProfile);
  els.llmStatusChip.textContent = llmReady ? `当前：${activeProfile.id}` : '未配置';
  els.llmStatusChip.classList.toggle('is-live', llmReady);
  els.llmStatusText.textContent = llmReady
    ? `已加载 ${profiles.length} 个 profile，当前模型：${activeProfile.model || '未填写'}，地址：${activeProfile.baseUrl || '未填写'}`
    : (llmStatus.message || '当前还没有可用 LLM profile，优化稿会先走本地规则。');
  els.llmProfileSelect.disabled = !profiles.length;
  els.llmSwitchButton.disabled = !profiles.length;
}

function renderAudioStatus() {
  const stt = state.providerStatus?.stt;
  if (!els.audioUploadStatus) return;
  if (!stt) {
    els.audioUploadStatus.textContent = '可上传音频文件，但当前 provider 没有返回本地 STT 状态。';
    els.uploadAudioButton.disabled = false;
    return;
  }
  if (stt.ok) {
    const details = [stt.provider || 'STT', stt.model || stt.details?.model].filter(Boolean).join(' / ');
    els.audioUploadStatus.textContent = `音频上传可用：${details}`;
    els.uploadAudioButton.disabled = false;
  } else {
    els.audioUploadStatus.textContent = `音频上传已准备好，但本地 STT 还没装好：${stt.error || stt.details?.error || '未配置 faster-whisper'}`;
    els.uploadAudioButton.disabled = false;
  }
}

function renderResult() {
  const transcript = selectedTranscript();
  if (!transcript) {
    els.resultEmpty.classList.remove('hidden');
    els.resultContent.classList.add('hidden');
    els.resultScene.textContent = '未选择';
    els.resultSource.textContent = '文本输入';
    return;
  }

  els.resultEmpty.classList.add('hidden');
  els.resultContent.classList.remove('hidden');
  els.resultScene.textContent = sceneLabel(transcript.scene);
  els.resultSource.textContent = inputSourceLabel(transcript.inputSource);
  els.rawText.textContent = transcript.rawText;
  els.polishedText.textContent = transcript.polishedText;
  els.issuesList.innerHTML = transcript.issues
    .map((issue) => `
      <div class="issue-item">
        <strong>${escapeHtml(issue.title)}</strong>
        <p>${escapeHtml(issue.detail)}</p>
      </div>
    `)
    .join('');
}

function renderTraining() {
  const transcript = selectedTranscript();
  if (!transcript) {
    els.trainingEmpty.classList.remove('hidden');
    els.trainingContent.classList.add('hidden');
    return;
  }

  els.trainingEmpty.classList.add('hidden');
  els.trainingContent.classList.remove('hidden');
  els.trainingStandardText.textContent = transcript.polishedText;

  if (!state.trainingAttempts.length) {
    els.trainingList.className = 'stack empty-state';
    els.trainingList.textContent = '还没有训练记录。';
    return;
  }

  els.trainingList.className = 'stack';
  els.trainingList.innerHTML = state.trainingAttempts
    .map((item) => `
      <div class="training-item">
        <div class="card-header">
          <strong>第 ${item.round} 轮</strong>
          <span class="pill">清晰度 ${item.clarityScore}</span>
        </div>
        <p>${escapeHtml(item.text)}</p>
        <p class="muted">结构 ${item.structureScore} · 成章 ${item.polishScore}</p>
        <p>${escapeHtml(item.feedback)}</p>
        <div class="stack">
          ${(item.improvedPoints || []).map((point) => `<div class="muted">• ${escapeHtml(point)}</div>`).join('')}
        </div>
      </div>
    `)
    .join('');
}

function renderIdeas() {
  els.ideaCountLabel.textContent = `${state.ideas.length} 条`;

  if (!state.ideas.length) {
    els.ideasList.className = 'stack empty-state';
    els.ideasList.textContent = '还没有归档内容。';
    return;
  }

  els.ideasList.className = 'stack';
  els.ideasList.innerHTML = state.ideas
    .map((item) => `
      <div class="idea-item">
        <div class="card-header">
          <strong>${escapeHtml(item.title)}</strong>
          <span class="pill">${escapeHtml(item.category)}</span>
        </div>
        <p>${escapeHtml(item.normalizedText)}</p>
        <p class="muted">下一步：${escapeHtml(item.nextAction)}</p>
        <p class="muted">标签：${escapeHtml((item.tags || []).join(' / ') || '无')}</p>
      </div>
    `)
    .join('');
}

function renderReport() {
  els.reportTranscribeCount.textContent = String(state.report?.transcribeCount || 0);
  els.reportPolishCount.textContent = String(state.report?.polishCount || 0);
  els.reportCatchphraseCount.textContent = String(state.report?.catchphraseCount || 0);
  els.reportSpeechCount.textContent = String(state.report?.speechInputCount || 0);
  els.reportBestSentence.textContent = state.report?.bestSentence || '今天先开口，明天再打磨。';
}

function renderTtsControls() {
  const transcript = selectedTranscript();
  const hasText = Boolean(transcript?.polishedText);
  const supported = state.tts.supported;
  els.speakPolishedButton.disabled = !supported || !hasText;
  els.speakTrainingButton.disabled = !supported || !hasText;
  els.stopSpeakButton.disabled = !supported || !state.tts.speaking;

  if (!supported) {
    syncTtsStatus('当前浏览器不支持原生朗读');
  } else if (!hasText && !state.tts.speaking) {
    syncTtsStatus('先生成一条优化稿，再试试听回放。');
  }
}

async function createTranscript() {
  const rawText = els.recordInput.value.trim();
  if (!rawText) {
    toast('先输入一段表达内容。');
    return;
  }

  if (state.voice.isListening) {
    stopVoiceInput();
  }

  const captureMeta = buildCaptureMeta();
  const transcriptionMeta = buildTranscriptionMeta();

  const created = await api('/api/transcripts/create', {
    method: 'POST',
    body: {
      rawText,
      scene: els.sceneSelect.value,
      mode: els.modeSelect.value,
      inputSource: state.activeInputSource || 'text',
      captureMeta,
      transcriptionMeta
    }
  });

  state.selectedTranscriptId = created.id;
  els.recordInput.value = '';
  resetVoiceBuffer();
  state.activeInputSource = 'text';
  await refreshAll();
  setSection('result');
  toast('已经生成转写与优化稿。');
}

async function uploadAudioFile(event) {
  const [file] = Array.from(event.target.files || []);
  if (!file) return;

  try {
    const audioBase64 = await fileToBase64(file);
    state.activeInputSource = 'speech';
    els.audioUploadStatus.textContent = `正在转写：${file.name}`;

    const created = await api('/api/transcripts/create', {
      method: 'POST',
      body: {
        scene: els.sceneSelect.value,
        mode: els.modeSelect.value,
        inputSource: 'speech',
        audioBase64,
        audioMimeType: file.type || 'audio/webm',
        audioName: file.name,
        captureMeta: {
          capturedBy: 'audio-file-upload',
          sizeBytes: file.size
        }
      }
    });

    state.selectedTranscriptId = created.id;
    event.target.value = '';
    await refreshAll();
    setSection('result');
    toast('音频已转写并生成优化稿。');
  } catch (error) {
    els.audioUploadStatus.textContent = `音频转写失败：${error.message}`;
    toast(`音频转写失败：${error.message}`);
  }
}

async function archiveIdea() {
  const transcript = selectedTranscript();
  if (!transcript) {
    toast('先生成一条内容。');
    return;
  }

  await api('/api/ideas/archive', {
    method: 'POST',
    body: {
      transcriptId: transcript.id
    }
  });

  await refreshAll();
  setSection('ideas');
  toast('已归档到灵感库。');
}

async function evaluateTraining() {
  const transcript = selectedTranscript();
  if (!transcript) {
    toast('先生成结果，再开始训练。');
    return;
  }

  const attemptText = els.attemptInput.value.trim();
  if (!attemptText) {
    toast('先输入你的复述稿。');
    return;
  }

  await api('/api/train/evaluate', {
    method: 'POST',
    body: {
      transcriptId: transcript.id,
      attemptText,
      round: state.trainingAttempts.length + 1
    }
  });

  els.attemptInput.value = '';
  state.trainingAttempts = await api(`/api/training?transcriptId=${encodeURIComponent(transcript.id)}`);
  render();
  toast('训练评分已生成。');
}

async function resetDemoData() {
  if (state.voice.isListening) {
    stopVoiceInput();
  }
  await api('/api/reset', { method: 'POST' });
  state.selectedTranscriptId = null;
  state.activeInputSource = 'text';
  els.recordInput.value = '';
  els.attemptInput.value = '';
  resetVoiceBuffer();
  await refreshAll();
  setSection('home');
  toast('演示数据已重置。');
}

async function switchLlmProfile() {
  const profileId = els.llmProfileSelect.value;
  if (!profileId) {
    toast('先配置至少一个 LLM profile。');
    return;
  }

  await api('/api/llm/switch', {
    method: 'POST',
    body: { profileId }
  });

  await refreshAll();
  toast(`已切换到 LLM：${profileId}`);
}

async function exportData() {
  const payload = await api('/api/export');
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = `出口成章-数据导出-${new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-')}.json`;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
  toast('数据已导出到本地。');
}

async function importDataFromFile(event) {
  const [file] = Array.from(event.target.files || []);
  if (!file) return;

  try {
    const content = await file.text();
    const payload = JSON.parse(content);
    const result = await api('/api/import', {
      method: 'POST',
      body: {
        mode: 'merge',
        store: payload.store || payload
      }
    });

    await refreshAll();
    toast(`导入完成：${result.counts.transcripts} 条表达 / ${result.counts.ideas} 条灵感`);
  } catch (error) {
    toast(`导入失败：${error.message}`);
  } finally {
    event.target.value = '';
  }
}

function startVoiceInput() {
  if (!state.voice.supported || !state.voice.recognition || state.voice.isListening) return;
  try {
    resetVoiceBuffer();
    state.activeInputSource = 'speech';
    state.voice.recognition.start();
  } catch (error) {
    toast(`语音识别启动失败：${error.message}`);
  }
}

function stopVoiceInput() {
  if (!state.voice.recognition || !state.voice.isListening) return;
  state.voice.recognition.stop();
}

function clearRecordInput() {
  if (state.voice.isListening) {
    stopVoiceInput();
  }
  els.recordInput.value = '';
  resetVoiceBuffer();
  state.activeInputSource = 'text';
  syncVoiceStatus(state.voice.supported ? '输入已清空' : '当前浏览器不支持语音识别');
}

function updateRecordInputFromVoice() {
  const content = [state.voice.finalText, state.voice.interimText].filter(Boolean).join(' ');
  els.recordInput.value = content.trim();
}

function mergeSpeechText(previous, incoming) {
  return [previous, incoming]
    .filter(Boolean)
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function buildCaptureMeta() {
  if (state.activeInputSource !== 'speech') return null;
  const durationSeconds = state.voice.startedAt ? Math.max(1, Math.round((Date.now() - state.voice.startedAt) / 1000)) : null;
  return {
    durationSeconds,
    capturedBy: 'browser-speech-recognition'
  };
}

function buildTranscriptionMeta() {
  if (state.activeInputSource !== 'speech') return null;
  return {
    provider: 'browser-web-speech',
    recognizedAt: new Date().toISOString()
  };
}

function startVoiceTimer() {
  stopVoiceTimer();
  state.voice.timer = window.setInterval(() => syncVoiceStatus(), 500);
}

function stopVoiceTimer() {
  if (state.voice.timer) {
    window.clearInterval(state.voice.timer);
    state.voice.timer = null;
  }
}

function syncVoiceStatus(customText) {
  if (!els.voiceStatus) return;
  if (customText) {
    els.voiceStatus.textContent = customText;
    els.voiceStatus.classList.toggle('is-live', state.voice.isListening);
    return;
  }

  if (state.voice.isListening) {
    const seconds = state.voice.startedAt ? Math.max(1, Math.round((Date.now() - state.voice.startedAt) / 1000)) : 0;
    els.voiceStatus.textContent = `语音识别中 · ${seconds}s`;
    els.voiceStatus.classList.add('is-live');
  } else {
    els.voiceStatus.textContent = state.voice.supported ? '准备就绪' : '语音识别不可用';
    els.voiceStatus.classList.remove('is-live');
  }
}

function resetVoiceBuffer() {
  state.voice.finalText = '';
  state.voice.interimText = '';
  state.voice.startedAt = null;
  stopVoiceTimer();
}

function selectedTranscript() {
  return state.transcripts.find((item) => item.id === state.selectedTranscriptId) || state.transcripts[0] || null;
}

function sceneLabel(scene) {
  return ({
    general: '通用',
    report: '汇报',
    pitch: '口播',
    interview: '面试',
    idea: '灵感'
  })[scene] || '表达';
}

function inputSourceLabel(source) {
  return ({
    text: '文本输入',
    speech: '语音输入',
    demo: 'Demo 示例'
  })[source] || '文本输入';
}

function providerStatusMessage(status) {
  if (!status) return '尚未拿到 provider 状态';
  if (status.provider === 'local') {
    return '当前使用内置本地 provider，适合演示与离线开发。';
  }
  if (status.provider === 'http') {
    const upstreamName = status.upstream?.provider || '外部服务';
    return `当前通过 HTTP provider 连接上游：${upstreamName}`;
  }
  return `当前 provider：${status.provider || 'unknown'}`;
}

function pickChineseVoice() {
  const voices = state.tts.voices || [];
  return voices.find((voice) => /zh|中文|Chinese/i.test(`${voice.lang || ''} ${voice.name || ''}`)) || voices[0] || null;
}

function syncTtsStatus(message) {
  if (!els.ttsStatus) return;
  els.ttsStatus.textContent = message;
}

function stopSpeaking() {
  if (!window.speechSynthesis) return;
  window.speechSynthesis.cancel();
  state.tts.speaking = false;
  renderTtsControls();
  syncTtsStatus('已停止朗读。');
}

function speakText(text) {
  const content = String(text || '').trim();
  if (!content) {
    toast('先生成一条优化稿。');
    return;
  }
  if (!window.speechSynthesis) {
    toast('当前浏览器不支持朗读。');
    return;
  }

  window.speechSynthesis.cancel();
  const utterance = new SpeechSynthesisUtterance(content);
  utterance.lang = 'zh-CN';
  utterance.rate = 1;
  utterance.pitch = 1;
  const voice = pickChineseVoice();
  if (voice) utterance.voice = voice;

  utterance.onstart = () => {
    state.tts.speaking = true;
    renderTtsControls();
    syncTtsStatus(`正在朗读：${voice?.name || '默认中文语音'}`);
  };
  utterance.onend = () => {
    state.tts.speaking = false;
    renderTtsControls();
    syncTtsStatus('朗读完成。');
  };
  utterance.onerror = () => {
    state.tts.speaking = false;
    renderTtsControls();
    syncTtsStatus('朗读失败，请换浏览器或语音源再试。');
  };

  window.speechSynthesis.speak(utterance);
}

function formatDateTime(value) {
  if (!value) return '未知时间';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat('zh-CN', {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit'
  }).format(date);
}

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ''));
    reader.onerror = () => reject(new Error('文件读取失败'));
    reader.readAsDataURL(file);
  });
}

async function api(url, options = {}) {
  const response = await fetch(url, {
    method: options.method || 'GET',
    headers: {
      'Content-Type': 'application/json'
    },
    body: options.body ? JSON.stringify(options.body) : undefined
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.message || data.error || '请求失败');
  }
  return data;
}

function toast(message) {
  els.toast.textContent = message;
  els.toast.classList.remove('hidden');
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => els.toast.classList.add('hidden'), 2200);
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
