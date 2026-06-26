const fs = require('node:fs');
const path = require('node:path');

function parseEnv(content) {
  const result = {};
  const lines = String(content || '').split(/\r?\n/);

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const index = trimmed.indexOf('=');
    if (index <= 0) continue;
    const key = trimmed.slice(0, index).trim();
    let value = trimmed.slice(index + 1).trim();

    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }

    result[key] = value;
  }

  return result;
}

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return;
  const parsed = parseEnv(fs.readFileSync(filePath, 'utf8'));
  for (const [key, value] of Object.entries(parsed)) {
    if (process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}

function loadAppEnv(baseDir = path.resolve(__dirname, '..')) {
  loadEnvFile(path.join(baseDir, '.env'));
  loadEnvFile(path.join(baseDir, '.env.local'));
}

module.exports = {
  parseEnv,
  loadAppEnv
};
