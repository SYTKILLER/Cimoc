/** 字符串工具（移植自 Cimoc StringUtils）。 */

export class StringUtils {
  /** 类似 Java String.format 的 %s/%d 简易实现。 */
  static format(format: string, ...args: string[]): string {
    let out = '';
    let argIndex = 0;
    for (let i = 0; i < format.length; i++) {
      const c = format.charAt(i);
      if (c === '%' && i + 1 < format.length) {
        const next = format.charAt(i + 1);
        if (next === 's' || next === 'd') {
          out += argIndex < args.length ? args[argIndex++] : '';
          i++;
          continue;
        }
        if (next === '%') {
          out += '%';
          i++;
          continue;
        }
      }
      out += c;
    }
    return out;
  }

  /** 正则取第 group 组，失败返回 null。 */
  static match(pattern: string, input: string | null, group: number): string | null {
    if (input === null || input === undefined) {
      return null;
    }
    try {
      const m = new RegExp(pattern).exec(input);
      if (m !== null && group < m.length) {
        const v = m[group];
        return v === undefined ? null : v;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static split(input: string | null, regex: string, index: number): string | null {
    if (input === null || input === undefined) {
      return null;
    }
    const arr = input.split(new RegExp(regex));
    if (index >= 0 && index < arr.length) {
      return arr[index];
    }
    return null;
  }

  static substring(input: string | null, start: number, end: number = -1): string | null {
    if (input === null || input === undefined) {
      return null;
    }
    const len = input.length;
    const s = start < 0 ? len + start : start;
    const e = end < 0 ? len + end + 1 : end;
    if (s < 0 || s >= len || e <= s) {
      return '';
    }
    return input.substring(s, e);
  }

  static isBlank(s: string | null | undefined): boolean {
    return s === null || s === undefined || (s as string).trim().length === 0;
  }

  static isNotBlank(s: string | null | undefined): boolean {
    return !StringUtils.isBlank(s);
  }

  static emptyTo(s: string | null, def: string): string {
    return StringUtils.isBlank(s) ? def : (s as string);
  }

  static urlEncode(s: string): string {
    return encodeURIComponent(s);
  }

  /** 文件名非法字符清洗（移植自 Download 的清洗正则）。 */
  static cleanFileName(s: string): string {
    return s.replace(/[:\/\\?<>\"|\.]/g, '_');
  }

  static isFinish(text: string | null): boolean {
    if (text === null) {
      return false;
    }
    return text.includes('完结') || text.includes('Completed') || text.includes('完結');
  }
}
