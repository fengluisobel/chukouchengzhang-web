const DEFAULT_TIMEOUT_MS = Number(process.env.CKCZ_HTTP_TIMEOUT_MS || 15000);
const DEFAULT_RETRIES = Number(process.env.CKCZ_HTTP_RETRIES || 1);

async function sleep(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function requestJson(url, options = {}) {
  const timeoutMs = Number(options.timeoutMs || DEFAULT_TIMEOUT_MS);
  const retries = Number(options.retries ?? DEFAULT_RETRIES);
  const method = options.method || 'GET';
  let lastError;

  for (let attempt = 0; attempt <= retries; attempt += 1) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);

    try {
      const response = await fetch(url, {
        method,
        headers: {
          'Content-Type': 'application/json',
          ...(options.headers || {})
        },
        body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
        signal: controller.signal
      });

      const text = await response.text();
      let data = null;
      try {
        data = text ? JSON.parse(text) : null;
      } catch {
        data = { raw: text };
      }

      if (!response.ok) {
        const error = new Error(data?.message || data?.error || `HTTP ${response.status}`);
        error.status = response.status;
        error.payload = data;
        throw error;
      }

      return data;
    } catch (error) {
      lastError = error;
      const shouldRetry = attempt < retries && (error.name === 'AbortError' || !error.status || error.status >= 500);
      if (!shouldRetry) break;
      await sleep(400 * (attempt + 1));
    } finally {
      clearTimeout(timer);
    }
  }

  throw lastError;
}

async function postJson(url, payload, options = {}) {
  return requestJson(url, {
    ...options,
    method: 'POST',
    body: payload || {}
  });
}

async function getJson(url, options = {}) {
  return requestJson(url, {
    ...options,
    method: 'GET'
  });
}

module.exports = {
  requestJson,
  postJson,
  getJson
};
