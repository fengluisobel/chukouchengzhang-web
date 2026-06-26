const crypto = require('node:crypto');
const { requestJson } = require('./http-client');

/**
 * 讯飞语音听写 WebAPI 封装
 * 文档：https://www.xfyun.cn/doc/asr/voicedictation/WebSocket.html
 *
 * 鉴权方式：HMAC-SHA256 签名
 * 接口：wss://iat-api.xfyun.cn/v2/iat
 *
 * 当前实现：Node.js 22+ 内置 WebSocket 支持
 */

function generateAuthUrl(appId, apiKey, apiSecret) {
  const date = new Date().toUTCString();
  const host = 'iat-api.xfyun.cn';
  const requestLine = 'GET /v2/iat HTTP/1.1';

  const signatureOrigin = `host: ${host}\ndate: ${date}\n${requestLine}`;
  const signature = crypto
    .createHmac('sha256', apiSecret)
    .update(signatureOrigin)
    .digest('base64');

  const authorizationOrigin = `api_key="${apiKey}", algorithm="hmac-sha256", headers="host date request-line", signature="${signature}"`;
  const authorization = Buffer.from(authorizationOrigin).toString('base64');

  return {
    url: `wss://iat-api.xfyun.cn/v2/iat?authorization=${encodeURIComponent(authorization)}&date=${encodeURIComponent(date)}&host=${encodeURIComponent(host)}`,
    authorization,
    date,
    host
  };
}

function createXfyunStt(config = {}) {
  const appId = config.appId || process.env.CKCZ_XFYUN_APPID || '';
  const apiKey = config.apiKey || process.env.CKCZ_XFYUN_API_KEY || '';
  const apiSecret = config.apiSecret || process.env.CKCZ_XFYUN_API_SECRET || '';
  const enabled = Boolean(appId && apiKey && apiSecret);

  return {
    enabled,

    async healthCheck() {
      if (!enabled) {
        return {
          ok: false,
          provider: 'xfyun-stt',
          enabled: false,
          error: '讯飞STT未配置（缺少appId/apiKey/apiSecret）'
        };
      }

      try {
        const auth = generateAuthUrl(appId, apiKey, apiSecret);
        // 只做鉴权URL生成测试，不实际连接WebSocket（避免长连接开销）
        return {
          ok: true,
          provider: 'xfyun-stt',
          enabled: true,
          appId: appId.slice(0, 4) + '****',
          checkedAt: new Date().toISOString()
        };
      } catch (error) {
        return {
          ok: false,
          provider: 'xfyun-stt',
          enabled: true,
          error: error instanceof Error ? error.message : '鉴权生成失败'
        };
      }
    },

    async transcribeAudio({ audioBase64, audioMimeType, audioName }) {
      if (!enabled) {
        throw new Error('讯飞STT未配置');
      }

      if (!audioBase64) {
        throw new Error('AUDIO_BASE64_REQUIRED');
      }

      // TODO: 实现完整的WebSocket语音听写流程
      // 1. 将音频转为PCM 16kHz 16bit单声道
      // 2. WebSocket分片发送（每片约1280字节）
      // 3. 接收服务端返回的识别结果
      // 4. 拼接完整文本

      // 当前阶段：返回友好提示，引导使用浏览器Speech API
      throw new Error('讯飞STT WebSocket实现开发中，当前请使用浏览器Speech API');
    }
  };
}

module.exports = {
  createXfyunStt,
  generateAuthUrl
};
