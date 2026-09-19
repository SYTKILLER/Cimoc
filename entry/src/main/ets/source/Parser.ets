/**
 * Parser 契约：与 Android 版 parser/Parser.java 一一对应（迭代器语义简化为返回数组）。
 * MangaParser 提供与 Java 版 MangaParser 基类等价的默认实现。
 */

import { HttpHeader } from '../network/HttpClient';
import { Comic, Chapter, ImageInfo } from '../model/Model';
import { StringUtils } from '../common/StringUtils';

export class ParserRequest {
  readonly url: string;
  readonly headers: HttpHeader | null;
  readonly body: string;

  constructor(url: string, headers: HttpHeader | null = null, body: string = '') {
    this.url = url;
    this.headers = headers;
    this.body = body;
  }
}

export class UrlFilter {
  readonly filter: string;
  readonly regex: string;
  readonly group: number;

  constructor(filter: string, regex: string = '', group: number = 0) {
    this.filter = filter;
    this.regex = regex;
    this.group = group;
  }
}

export abstract class Parser {
  protected mTitle: string;
  protected readonly mType: number;
  protected mFilters: UrlFilter[] = [];

  protected constructor(type: number, title: string) {
    this.mType = type;
    this.mTitle = title;
  }

  getType(): number {
    return this.mType;
  }

  getTitle(): string {
    return this.mTitle;
  }

  protected initUrlFilterList(): void {
  }

  protected isHere(url: string): boolean {
    for (const f of this.mFilters) {
      if (url.indexOf(f.filter) !== -1) {
        return true;
      }
    }
    return false;
  }

  /** 浏览器 URL → cid（链接嗅探用，基础版预留）。 */
  getComicId(url: string): string | null {
    for (const f of this.mFilters) {
      if (url.indexOf(f.filter) !== -1 && f.regex.length > 0) {
        return StringUtils.match(f.regex, url, f.group);
      }
    }
    return null;
  }

  // ---- 默认实现（对应 Java 基类） ----

  getHeader(): HttpHeader | null {
    return null;
  }

  getSearchRequest(keyword: string, page: number): ParserRequest | null {
    return null;
  }

  parseSearch(html: string, page: number): Comic[] {
    return [];
  }

  getInfoRequest(cid: string): ParserRequest | null {
    return null;
  }

  parseInfo(html: string, comic: Comic): Comic {
    return comic;
  }

  /** 详情页解析后若已含章节返回 null（不再二次请求）。 */
  getChapterRequest(html: string, cid: string): ParserRequest | null {
    return null;
  }

  parseChapter(html: string, comic: Comic, sourceComic: number): Chapter[] {
    return [];
  }

  getImagesRequest(cid: string, path: string): ParserRequest | null {
    return null;
  }

  /** 多页拼接源的第 page 页图片请求（page 从 2 起）；返回 null 表示无更多页。 */
  nextImagesRequest(cid: string, path: string, page: number): ParserRequest | null {
    return null;
  }

  parseImages(html: string, chapter: Chapter): ImageInfo[] | null {
    return null;
  }

  getLazyRequest(url: string): ParserRequest | null {
    return null;
  }

  parseLazy(html: string, url: string): string | null {
    return null;
  }

  getCheckRequest(cid: string): ParserRequest | null {
    return this.getInfoRequest(cid);
  }

  parseCheck(html: string): string {
    return '';
  }

  /** 图片 URL 需要的请求头（防盗链），基础版与 getHeader 相同。 */
  imageHeaders(): HttpHeader | null {
    return this.getHeader();
  }

  /** 章节列表是否倒序（对齐 interpretationUtils.isReverseOrder）。 */
  isReverseOrder(): boolean {
    return false;
  }

  protected static isFinishText(text: string | null): boolean {
    return StringUtils.isFinish(text);
  }
}
