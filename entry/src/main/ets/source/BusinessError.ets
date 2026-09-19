/** 源站业务错误：HTTP 200 但业务码非 0/200（如拷贝 210 反盗版拦截）。 */

export class BusinessError extends Error {
  readonly code: number;

  constructor(code: number, message: string) {
    super(message);
    this.code = code;
  }

  /** 检查 JSON API 响应的业务码，异常时抛出（对齐 Cimoc 对 code 字段的处理）。 */
  static checkApi(html: string): void {
    const trimmed = html.trim();
    if (trimmed.length === 0 || trimmed.charAt(0) !== '{') {
      return;
    }
    const root = JSON.parse(trimmed) as Record<string, Object | null>;
    const codeVal = root['code'];
    if (typeof codeVal === 'number') {
      const code = codeVal as number;
      if (code !== 200 && code !== 0) {
        const msg = root['message'];
        let msgText = typeof msg === 'string' ? msg as string : `业务错误 ${code}`;
        if (code === 210) {
          // 拷贝漫画反第三方封锁：需在同一网络安装官方APP并等待1小时解封
          msgText = '拷贝漫画已封锁第三方客户端。解锁方法：在同一网络下安装并打开官方APP一次，等待1小时后重试（期间请勿用本应用请求该源）';
        }
        throw new BusinessError(code, msgText);
      }
    }
    const errno = root['errno'];
    if (typeof errno === 'number' && (errno as number) !== 0) {
      const msg2 = root['errmsg'];
      const msgText2 = typeof msg2 === 'string' ? msg2 as string : `业务错误 ${errno as number}`;
      throw new BusinessError(errno as number, msgText2);
    }
  }
}
