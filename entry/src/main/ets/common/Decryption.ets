/**
 * 站点脚本解密工具。
 * unpack：标准 packer `eval(function(p,a,c,k,e,d){...})` 自解包
 * （DM5 系站点漫本/极速漫画的章节图片脚本，对齐 CimocPlus DecryptionUtils.unpack）。
 */

const PACKER_HEAD: RegExp =
  /}\s*\(\s*'([\s\S]*?)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'([\s\S]*?)'\.split\(\s*'\|'\s*\)/;

function radixEncode(value: number, radix: number): string {
  let out = '';
  let n = value;
  while (true) {
    const r = n % radix;
    out = (r > 35 ? String.fromCharCode(r + 29) : '0123456789abcdefghijklmnopqrstuvwxyz'.charAt(r)) + out;
    n = Math.floor(n / radix);
    if (n === 0) {
      break;
    }
  }
  return out;
}

export class Decryption {
  /** 从 HTML/脚本中提取并解包第一个 packer 块；无 packer 或解包失败返回 null。 */
  static unpackEval(html: string): string | null {
    const start = html.indexOf('eval(function(p,a,c,k,e,d');
    if (start < 0) {
      return null;
    }
    const m = PACKER_HEAD.exec(html);
    if (m === null) {
      return null;
    }
    const payload = (m[1] !== undefined ? m[1] : '').replace(/\\'/g, "'");
    const radix = m[2] !== undefined ? Number(m[2]) : 32;
    const count = m[3] !== undefined ? Number(m[3]) : 0;
    const dict = m[4] !== undefined ? m[4] : '';
    const words = dict.split('|');
    const table: Map<string, string> = new Map();
    for (let i = count - 1; i >= 0; i--) {
      if (i < words.length && words[i].length > 0) {
        table.set(radixEncode(i, radix), words[i]);
      }
    }
    return payload.replace(/\b\w+\b/g, (w: string) => {
      const hit = table.get(w);
      return hit !== undefined ? hit : w;
    });
  }
}
