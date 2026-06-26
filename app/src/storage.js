const fs = require('node:fs/promises');
const path = require('node:path');

const defaultStore = () => ({
  transcripts: [],
  trainingAttempts: [],
  ideas: []
});

async function ensureStore(filePath) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  try {
    await fs.access(filePath);
  } catch {
    await fs.writeFile(filePath, JSON.stringify(defaultStore(), null, 2), 'utf8');
  }
}

async function readStore(filePath) {
  await ensureStore(filePath);
  const raw = await fs.readFile(filePath, 'utf8');
  const parsed = JSON.parse(raw || '{}');
  return {
    ...defaultStore(),
    ...parsed,
    transcripts: Array.isArray(parsed.transcripts) ? parsed.transcripts : [],
    trainingAttempts: Array.isArray(parsed.trainingAttempts) ? parsed.trainingAttempts : [],
    ideas: Array.isArray(parsed.ideas) ? parsed.ideas : []
  };
}

async function writeStore(filePath, data) {
  await ensureStore(filePath);
  await fs.writeFile(filePath, JSON.stringify(data, null, 2), 'utf8');
}

async function updateStore(filePath, updater) {
  const current = await readStore(filePath);
  const next = await updater(current);
  await writeStore(filePath, next);
  return next;
}

module.exports = {
  defaultStore,
  ensureStore,
  readStore,
  writeStore,
  updateStore
};
