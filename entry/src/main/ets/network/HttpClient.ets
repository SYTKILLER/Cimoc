/**
 * HTTP 客户端（移植自 OkHttp + Manga.getResponseBody 语义）：
 * - 默认 Chrome UA（可被每源 headers 覆盖）
 * - 正文 charset 自适应探测解码（GBK 等旧站）
 * - X-Cimoc-Fallback 多域名容灾链
 */

import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';

/** 网络异常。 */
export class HttpError extends Error {
  readonly isNetwork: boolean;

  constructor(message: string, isNetwork: boolean = true) {
    super(message);
    this.isNetwork = isNetwork;
  }
}

export class HttpHeader {
  private readonly map: Map<string, string> = new Map();

  static of(pairs: string[][]): HttpHeader {
    const h = new HttpHeader();
    for (const p of pairs) {
      h.set(p[0], p[1]);
    }
    return h;
  }

  set(name: string, value: string): void {
    this.map.set(name, value);
  }

  get(name: string): string | undefined {
    return this.map.get(name);
  }

  has(name: string): boolean {
    return this.map.has(name);
  }

  remove(name: string): void {
    this.map.delete(name);
  }

  names(): string[] {
    return Array.from(this.map.keys());
  }

  entries(): string[][] {
    const out: string[][] = [];
    this.map.forEach((v: string, k: string) => {
      out.push([k, v]);
    });
    return out;
  }

  clone(): HttpHeader {
    const h = new HttpHeader();
    this.map.forEach((v: string, k: string) => {
      h.set(k, v);
    });
    return h;
  }
}

export interface RawResponse {
  code: number;
  bytes: ArrayBuffer;
  finalUrl: string;
}

const DEFAULT_UA: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const CONNECT_TIMEOUT_MS = 15000;
const READ_TIMEOUT_MS = 20000;

export class HttpClient {
  /** 单例。 */
  private static instance: HttpClient | null = null;

  static get(): HttpClient {
    if (HttpClient.instance === null) {
      HttpClient.instance = new HttpClient();
    }
    return HttpClient.instance;
  }

  private constructor() {
  }

  /** 原始字节请求。headers 中键为 X-Cimoc-Fallback 时自动容灾重试。 */
  async fetchBytes(url: string, headers: HttpHeader | null = null): Promise<RawResponse> {
    const resp = await this.doFetch(url, headers, true);
    return resp;
  }

  /** 文本请求：charset 探测 + 容灾。 */
  async fetchText(url: string, headers: HttpHeader | null = null): Promise<string> {
    const resp = await this.doFetch(url, headers, false);
    return this.decodeBody(resp.bytes);
  }

  decodeBody(bytes: ArrayBuffer): string {
    const head = this.headString(bytes, 1024);
    const m = /charset=([\w\-]+)/.exec(head);
    let encoding = 'utf-8';
    if (m !== null) {
      encoding = m[1].toLowerCase();
    }
    try {
      const decoder = util.TextDecoder.create(encoding);
      return decoder.decodeToString(new Uint8Array(bytes));
    } catch (e) {
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(new Uint8Array(bytes));
    }
  }

  private headString(bytes: ArrayBuffer, max: number): string {
    const u8 = new Uint8Array(bytes.slice(0, Math.min(max, bytes.byteLength)));
    let s = '';
    for (let i = 0; i < u8.length; i++) {
      s += String.fromCharCode(u8[i]);
    }
    return s;
  }

  private async doFetch(url: string, headers: HttpHeader | null, binary: boolean): Promise<RawResponse> {
    let current = url;
    let fallbacks: string = headers !== null ? (headers.get('X-Cimoc-Fallback') ?? '') : '';
    let lastError: HttpError | null = null;

    for (let attempt = 0; attempt < 8; attempt++) {
      try {
        const resp = await this.requestOnce(current, headers, binary);
        if (resp.code >= 200 && resp.code < 400) {
          return resp;
        }
        lastError = new HttpError(`HTTP ${resp.code} ${current}`);
      } catch (e) {
        lastError = new HttpError(String(e));
      }
      // 容灾链切换
      const next = this.nextFallback(fallbacks);
      if (next === null) {
        break;
      }
      current = next.url;
      fallbacks = next.rest;
    }
    throw lastError !== null ? lastError : new HttpError('network error');
  }

  private nextFallback(fallbacks: string): Fallback | null {
    if (fallbacks === null || fallbacks.length === 0) {
      return null;
    }
    const comma = fallbacks.indexOf(',');
    if (comma < 0) {
      return new Fallback(fallbacks, '');
    }
    return new Fallback(fallbacks.substring(0, comma), fallbacks.substring(comma + 1));
  }

  private async requestOnce(url: string, headers: HttpHeader | null, binary: boolean): Promise<RawResponse> {
    const req = http.createHttp();
    try {
      const headerRecord: Record<string, string> = {};
      let hasUa = false;
      if (headers !== null) {
        for (const pair of headers.entries()) {
          headerRecord[pair[0]] = pair[1];
          if (pair[0].toLowerCase() === 'user-agent') {
            hasUa = true;
          }
        }
      }
      if (!hasUa) {
        headerRecord['User-Agent'] = DEFAULT_UA;
      }
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headerRecord,
        expectDataType: binary ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
        usingCache: true,
      };
      const resp = await req.request(url, options);
      const bytes = resp.result instanceof ArrayBuffer ? resp.result as ArrayBuffer : new ArrayBuffer(0);
      return new RawResponseImpl(resp.responseCode, bytes, url);
    } finally {
      req.destroy();
    }
  }
}

class Fallback {
  readonly url: string;
  readonly rest: string;

  constructor(url: string, rest: string) {
    this.url = url;
    this.rest = rest;
  }
}

class RawResponseImpl implements RawResponse {
  readonly code: number;
  readonly bytes: ArrayBuffer;
  readonly finalUrl: string;

  constructor(code: number, bytes: ArrayBuffer, url: string) {
    this.code = code;
    this.bytes = bytes;
    this.finalUrl = url;
  }
}
