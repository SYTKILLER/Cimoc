/**
 * DM5 系站点专用解析器（漫本 www.manben.com / 极速漫画 m.1kkk.com）。
 * 搜索/详情/章节列表沿用 GenericHtmlParser 的 CSS 配置；差异仅在章节图片：
 * - fun 模式（漫本）：图片由 chapterfun.ashx 分页接口下发，每页 2 张（滑窗重叠 1 张），
 *   依赖 ComicService 既有跨页去重与"整页 0 张新图"停止条件；
 * - eval 模式（极速漫画）：全部图片内联在章节页的 packer 加密脚本 newImgs 数组中。
 * 解包逻辑见 Decryption.unpackEval（对齐 CimocPlus DM5.java + DecryptionUtils）。
 */

import { GenericHtmlParser, SourceConfig } from './SourceConfig';
import { ParserRequest } from './Parser';
import { ImageInfo, Chapter } from '../model/Model';
import { Decryption } from '../common/Decryption';

export class Dm5Parser extends GenericHtmlParser {
  private readonly funMode: boolean;

  constructor(config: SourceConfig, funMode: boolean) {
    super(config);
    this.funMode = funMode;
  }

  /** 章节路径取末段数字：/m426476/ → 426476，/ch1-426475/ → 426475。 */
  private chapterIdOf(path: string): string {
    let out = '';
    const re = /\d+/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(path)) !== null) {
      out = m[0];
    }
    return out;
  }

  private funRequest(path: string, page: number): ParserRequest | null {
    const id = this.chapterIdOf(path);
    if (id.length === 0) {
      return null;
    }
    const url = `${this.getBaseUrl()}/chapterfun.ashx?cid=${id}&page=${page}&language=1&key=`;
    const h = this.getHeader();
    if (h !== null) {
      h.set('Referer', `${this.getBaseUrl()}${path}`);
    }
    return new ParserRequest(url, h);
  }

  getImagesRequest(cid: string, path: string): ParserRequest | null {
    if (this.funMode) {
      return this.funRequest(path, 1);
    }
    return super.getImagesRequest(cid, path);
  }

  nextImagesRequest(cid: string, path: string, page: number): ParserRequest | null {
    if (this.funMode && page >= 2) {
      return this.funRequest(path, page);
    }
    return super.nextImagesRequest(cid, path, page);
  }

  parseImages(html: string, chapter: Chapter): ImageInfo[] | null {
    const code = Decryption.unpackEval(html);
    if (code === null) {
      return [];
    }
    const list: ImageInfo[] = [];
    const chapterId = this.chapterIdOf(chapter.path);
    // eval 模式：var newImgs=["https://...",...]（全量绝对地址）
    const arr = this.firstArray(code, 'newImgs');
    if (arr.length > 0) {
      let num = 0;
      for (const item of arr) {
        const url = item.trim().replace(/^["']|["']$/g, '');
        if (url.length === 0) {
          continue;
        }
        num++;
        list.push(new ImageInfo(0, chapter.id, num, this.absImage(url), false));
      }
      return list;
    }
    // fun 模式：pix="https://.../父目录"、key='...'、pvalue=["/xx.jpg",...]
    const pix = this.firstString(code, 'pix');
    const key = this.firstString(code, 'key');
    const pvalue = this.firstArray(code, 'pvalue');
    if (pix.length > 0 && pvalue.length > 0) {
      let num = 0;
      for (const item of pvalue) {
        let url = item.trim().replace(/^["']|["']$/g, '');
        if (url.length === 0) {
          continue;
        }
        if (!url.startsWith('http')) {
          url = pix + url + `?cid=${chapterId}&key=${key}`;
        }
        num++;
        list.push(new ImageInfo(0, chapter.id, num, url, false));
      }
    }
    return list;
  }

  private firstString(code: string, name: string): string {
    const re = new RegExp(`var\\s+${name}\\s*=\\s*['"]([^'"]*)['"]`);
    const m = re.exec(code);
    return m !== null && m[1] !== undefined ? m[1] : '';
  }

  private firstArray(code: string, name: string): string[] {
    const re = new RegExp(`(?:var\\s+)?${name}\\s*=\\s*\\[([^\\]]*)\\]`);
    const m = re.exec(code);
    if (m === null || m[1] === undefined) {
      return [];
    }
    return m[1].split(',');
  }
}
