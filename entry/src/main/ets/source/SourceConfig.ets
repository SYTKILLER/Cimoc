/** 配置化源模型：SourceConfig（对齐 model/SourceConfig.java 的 JSON 字段）。 */

import { Parser, ParserRequest } from './Parser';
import { HttpHeader } from '../network/HttpClient';
import { Comic, Chapter, ImageInfo } from '../model/Model';
import { HtmlNode } from '../html/HtmlNode';
import { JsonObj } from '../common/Json';
import { StringUtils } from '../common/StringUtils';

const GENERIC_UA: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

export class SourceConfig {
  readonly key: string;
  readonly type: number;
  readonly title: string;
  readonly baseUrl: string;
  readonly serverUrl: string;
  readonly search: string;
  readonly searchKey: string;
  readonly searchInfoList: string;
  readonly searchInfoCid: string;
  readonly searchInfoTitle: string;
  readonly searchInfoCover: string;
  readonly searchInfoAuthor: string;
  readonly searchInfoUpdate: string;
  readonly parseInfoTitle: string;
  readonly parseInfoCover: string;
  readonly parseInfoIntro: string;
  readonly parseInfoAuthor: string;
  readonly parseInfoUpdate: string;
  readonly parseInfoStatus: string;
  readonly parseChapterList1: string;
  readonly parseChapterList2: string;
  readonly parseChapterList3: string;
  readonly parseChapterPath: string;
  readonly parseChapterTitle: string;
  readonly parseImageList: string;
  readonly parseImageUrl: string;
  readonly parseImageFaultImage: string;
  readonly parseImagePages: string;
  readonly imageServerUrl: string;

  constructor(key: string, type: number, title: string, obj: JsonObj) {
    this.key = key;
    this.type = type;
    this.title = title;
    this.baseUrl = SourceConfig.trimSlash(obj.optString('baseUrl'));
    this.serverUrl = obj.optString('serverUrl');
    this.search = obj.optString('search');
    this.searchKey = obj.optString('searchKey');
    this.searchInfoList = obj.optString('searchInfoList');
    this.searchInfoCid = obj.optString('searchInfoCid');
    this.searchInfoTitle = obj.optString('searchInfoTitle');
    this.searchInfoCover = obj.optString('searchInfoCover');
    this.searchInfoAuthor = obj.optString('searchInfoAuthor');
    this.searchInfoUpdate = obj.optString('searchInfoUpdate');
    this.parseInfoTitle = obj.optString('parseInfoTitle');
    this.parseInfoCover = obj.optString('parseInfoCover');
    this.parseInfoIntro = obj.optString('parseInfoIntro');
    this.parseInfoAuthor = obj.optString('parseInfoAuthor');
    this.parseInfoUpdate = obj.optString('parseInfoUpdate');
    this.parseInfoStatus = obj.optString('parseInfoStatus');
    this.parseChapterList1 = obj.optString('parseChapterList1');
    this.parseChapterList2 = obj.optString('parseChapterList2');
    this.parseChapterList3 = obj.optString('parseChapterList3');
    this.parseChapterPath = obj.optString('parseChapterPath');
    this.parseChapterTitle = obj.optString('parseChapterTitle');
    this.parseImageList = obj.optString('parseImageList');
    const imgUrl = obj.optString('parseImageUrl');
    const imgSrc = obj.optString('parseImageSrc');
    this.parseImageUrl = imgUrl.length > 0 ? imgUrl : imgSrc;
    this.parseImageFaultImage = obj.optString('parseImageFaultImage');
    // 多页拼接模板（如包子漫画 "%s_%d.html"）：源站把一章拆成每页 N 张图片
    this.parseImagePages = obj.optString('parseImagePages');
    const isu = obj.optString('imageServerUrl');
    this.imageServerUrl = isu.length > 0 ? isu : this.serverUrl;
  }

  static trimSlash(url: string): string {
    if (url.endsWith('/')) {
      return url.substring(0, url.length - 1);
    }
    return url;
  }

  isComplete(): boolean {
    return this.baseUrl.length > 0
      && (this.search.length > 0 || this.searchKey.length > 0)
      && this.searchInfoList.length > 0;
  }
}

/**
 * 配置化通用源（移植 GenericHtmlParser.java）。
 * 搜索/详情/章节/图片全部由 CSS 选择器配置驱动；图片列表支持 CSS 或正则两种模式。
 */
export class GenericHtmlParser extends Parser {
  private readonly config: SourceConfig;

  constructor(config: SourceConfig) {
    super(config.type, config.title);
    this.config = config;
  }

  getHeader(): HttpHeader | null {
    const h = new HttpHeader();
    h.set('Referer', `${this.config.baseUrl}/`);
    h.set('User-Agent', GENERIC_UA);
    return h;
  }

  private absUrl(path: string): string {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    if (path.startsWith('//')) {
      return `https:${path}`;
    }
    if (path.length === 0) {
      return this.config.baseUrl;
    }
    if (!path.startsWith('/')) {
      path = `/${path}`;
    }
    return this.config.baseUrl + path;
  }

  getSearchRequest(keyword: string, page: number): ParserRequest | null {
    const encoded = StringUtils.urlEncode(keyword);
    const path = this.config.search;
    if (this.config.searchKey.length > 0) {
      // POST 表单搜索（searchKey 站点）基础版未支持，不发起无效 GET
      return null;
    }
    let url: string;
    if (path.includes('%s') && path.includes('%d')) {
      url = this.absUrl(StringUtils.format(path, encoded, String(page)));
    } else if (path.includes('%s')) {
      if (page !== 1) {
        return null;
      }
      url = this.absUrl(StringUtils.format(path, encoded));
    } else {
      if (page !== 1) {
        return null;
      }
      url = this.absUrl(path + encoded);
    }
    return new ParserRequest(url, this.getHeader());
  }

  /** href → 相对 path（剥域名、去 #fragment），对齐 extractPath。 */
  private extractPath(href: string): string {
    href = href.trim();
    if (href.length === 0 || href.startsWith('javascript:')) {
      return '';
    }
    if (href.startsWith(this.config.baseUrl)) {
      href = href.substring(this.config.baseUrl.length);
    } else if (href.startsWith('http://') || href.startsWith('https://') || href.startsWith('//')) {
      const schemeEnd = href.indexOf('//');
      const rest = href.substring(schemeEnd + 2);
      const slash = rest.indexOf('/');
      href = slash >= 0 ? rest.substring(slash) : '';
    }
    const hash = href.indexOf('#');
    if (hash >= 0) {
      href = href.substring(0, hash);
    }
    return href;
  }

  /** cid 提取：href(selector) → attr(selector,'href') → href()，再转相对 path。 */
  private attrOrHref(node: HtmlNode, selector: string): string {
    if (selector.length === 0) {
      const h = node.hrefOf('a');
      return h !== null ? h : (node.href() ?? '');
    }
    let v = node.hrefOf(selector);
    if (v === null || v.length === 0) {
      v = node.attrOf(selector, 'href');
    }
    if (v === null || v.length === 0) {
      v = node.attr('href');
    }
    return v ?? '';
  }

  private extractCid(node: HtmlNode): string {
    const href = this.attrOrHref(node, this.config.searchInfoCid);
    return this.extractPath(href);
  }

  parseSearch(html: string, page: number): Comic[] {
    const out: Comic[] = [];
    const body = HtmlNode.parse(html);
    for (const node of body.list(this.config.searchInfoList)) {
      const cid = this.extractCid(node);
      if (cid.length === 0) {
        continue;
      }
      let title = this.textOrAttr(node, this.config.searchInfoTitle);
      if (title.length === 0) {
        title = node.text();
      }
      const cover = this.coverOf(node, this.config.searchInfoCover, null);
      const author = this.textOrAttr(node, this.config.searchInfoAuthor);
      const update = this.textOrAttr(node, this.config.searchInfoUpdate);
      out.push(new Comic(this.config.type, cid, title, cover, update, author));
    }
    return out;
  }

  private textOrAttr(node: HtmlNode, selector: string): string {
    if (selector.length === 0) {
      return node.text();
    }
    const t = node.textOf(selector);
    if (t !== null && t.length > 0) {
      return t;
    }
    return node.attrOf(selector, 'title') ?? '';
  }

  getInfoRequest(cid: string): ParserRequest | null {
    return new ParserRequest(this.absUrl(cid), this.getHeader());
  }

  private firstText(body: HtmlNode, selector: string): string {
    if (selector.length === 0) {
      return '';
    }
    const v = body.textOf(selector);
    return v === null ? '' : v;
  }

  parseInfo(html: string, comic: Comic): Comic {
    const body = HtmlNode.parse(html);
    const title = this.firstText(body, this.config.parseInfoTitle);
    const cover = this.coverOf(body, this.config.parseInfoCover, html);
    const intro = this.firstText(body, this.config.parseInfoIntro);
    const author = this.firstText(body, this.config.parseInfoAuthor);
    const update = this.firstText(body, this.config.parseInfoUpdate);
    const status = this.firstText(body, this.config.parseInfoStatus);
    comic.setInfo(title, cover, update, intro, author, StringUtils.isFinish(status));
    return comic;
  }

  parseChapter(html: string, comic: Comic, sourceComic: number): Chapter[] {
    const list: Chapter[] = [];
    // 多个列表选择器的命中可能相互重叠（如站点"最新章节"块与完整目录），
    // 按 path 去重，保持首次出现顺序，避免同一章节重复入库
    const seen: Set<string> = new Set();
    const body = HtmlNode.parse(html);
    const selectors: string[] =
      [this.config.parseChapterList1, this.config.parseChapterList2, this.config.parseChapterList3];
    for (const sel of selectors) {
      if (sel.length === 0) {
        continue;
      }
      for (const node of body.list(sel)) {
        let path: string;
        if (this.config.parseChapterPath.length > 0) {
          path = this.attrOrHref(node, this.config.parseChapterPath);
        } else {
          const h = node.hrefOf('a');
          path = h !== null && h.length > 0 ? h : (node.href() ?? '');
        }
        path = this.extractPath(path);
        if (path.length === 0 || seen.has(path)) {
          continue;
        }
        seen.add(path);
        let title = this.config.parseChapterTitle.length > 0
          ? this.textOrAttr(node, this.config.parseChapterTitle) : node.text();
        if (title.length === 0) {
          title = path;
        }
        list.push(new Chapter(0, sourceComic, title, path));
      }
    }
    return list;
  }

  getImagesRequest(cid: string, path: string): ParserRequest | null {
    return new ParserRequest(this.absUrl(this.canonicalImagesPath(path, cid)), this.getHeader());
  }

  /** 多页拼接：按模板生成第 page 页（page≥2）请求，未配置模板则无续页。 */
  nextImagesRequest(cid: string, path: string, page: number): ParserRequest | null {
    if (page < 2 || this.config.parseImagePages.length === 0) {
      return null;
    }
    const base = this.canonicalImagesPath(path, cid);
    const dot = base.lastIndexOf('.');
    const slash = base.lastIndexOf('/');
    const stem = dot > slash ? base.substring(0, dot) : base;
    const next = StringUtils.format(this.config.parseImagePages, stem, String(page));
    return new ParserRequest(this.absUrl(next), this.getHeader());
  }

  /**
   * 章节路径归一化：page_direct 跳转链接还原为真实章节页地址，
   * 使多页拼接的 _N.html 模板可以直接套用；非 page_direct 路径原样返回。
   */
  private canonicalImagesPath(path: string, cid: string): string {
    if (!path.includes('page_direct')) {
      return path;
    }
    const comicId = this.queryParam(path, 'comic_id');
    const section = this.queryParam(path, 'section_slot');
    const chapter = this.queryParam(path, 'chapter_slot');
    if (comicId.length === 0 || section.length === 0 || chapter.length === 0) {
      return path;
    }
    return `/comic/chapter/${comicId}/${section}_${chapter}.html`;
  }

  private queryParam(path: string, key: string): string {
    const m = new RegExp(`[?&]${key}=([^&#]+)`).exec(path);
    return m !== null && m.length > 1 && m[1] !== undefined ? m[1] : '';
  }

  parseImages(html: string, chapter: Chapter): ImageInfo[] | null {
    const list: ImageInfo[] = [];
    if (chapter.id === 0 && chapter.path.length === 0) {
      return list;
    }
    if (this.isRegex(this.config.parseImageList)) {
      this.parseRegexImages(html, chapter, list);
    } else {
      this.parseCssImages(html, chapter, list);
    }
    return list;
  }

  private parseCssImages(html: string, chapter: Chapter, list: ImageInfo[]): void {
    let selector = this.config.parseImageList;
    if (selector.length === 0) {
      selector = this.config.parseImageUrl;
    }
    if (selector.length === 0) {
      return;
    }
    let num = 0;
    for (const node of HtmlNode.parse(html).list(selector)) {
      const url = this.absImage(this.imageAttr(node, this.config.parseImageUrl));
      if (url.length === 0 || this.isFault(url)) {
        continue;
      }
      num++;
      list.push(new ImageInfo(0, chapter.id, num, url, false));
    }
  }

  private parseRegexImages(html: string, chapter: Chapter, list: ImageInfo[]): void {
    let re: RegExp;
    try {
      re = new RegExp(this.config.parseImageList, 'g');
    } catch (e) {
      return;
    }
    let num = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(html)) !== null) {
      let captured = m.length > 1 && m[1] !== undefined ? m[1] : m[0];
      if (captured === null) {
        continue;
      }
      captured = captured.trim();
      if (captured.startsWith('[') || captured.startsWith('{')) {
        const added = this.appendJsonImages(captured, chapter, list);
        if (added) {
          return;
        }
        continue;
      }
      for (const part of captured.split(/[,;]/)) {
        const url = this.absImage(part.replace(/"/g, '').replace(/'/g, '').trim());
        if (url.length === 0 || this.isFault(url)) {
          continue;
        }
        num++;
        list.push(new ImageInfo(0, chapter.id, num, url, false));
      }
    }
  }

  /** 正则捕获到 JSON 数组时批量展开；成功后整章结束（对齐 Java return）。 */
  private appendJsonImages(captured: string, chapter: Chapter, list: ImageInfo[]): boolean {
    try {
      const text = captured.startsWith('[') ? captured : `[${captured}]`;
      const arr = JSON.parse(text) as Array<Object>;
      if (!Array.isArray(arr)) {
        return false;
      }
      let num = list.length;
      for (const it of arr) {
        const u = typeof it === 'string' ? it as string : '';
        const url = this.absImage(u);
        if (url.length === 0 || this.isFault(url)) {
          continue;
        }
        num++;
        list.push(new ImageInfo(0, chapter.id, num, url, false));
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 对齐 isRegex：含捕获组特征时图片列表按正则处理。 */
  private isRegex(value: string): boolean {
    return value.includes('(.*') || value.includes('(.+') || value.includes('=\\') || value.includes("='");
  }

  private absImage(url: string): string {
    url = url.trim();
    if (url.length === 0) {
      return '';
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('//')) {
      return `https:${url}`;
    }
    if (url.startsWith('/')) {
      return this.config.baseUrl + url;
    }
    if (this.config.imageServerUrl.length > 0) {
      const server = this.config.imageServerUrl;
      if (!server.endsWith('/') && !url.startsWith('/')) {
        return `${server}/${url}`;
      }
      return server + url;
    }
    return `${this.config.baseUrl}/${url}`;
  }

  /** 图片属性链：data-original → data-src → data-echo → srcset → src（对齐 imageAttr）。 */
  private imageAttr(node: HtmlNode, attrHint: string): string {
    let attrs: string[] = ['data-original', 'data-src', 'data-echo', 'srcset', 'src'];
    const hint = attrHint.trim();
    if (hint.length > 0 && !hint.includes(' ') && !hint.includes('>') && !hint.includes('.')) {
      attrs = [hint, ...attrs];
    }
    for (const a of attrs) {
      let v = node.attr(a);
      if (v === null || v.length === 0 || v.startsWith('data:')) {
        continue;
      }
      if (a === 'srcset') {
        const space = v.indexOf(' ');
        if (space > 0) {
          v = v.substring(0, space);
        }
        const comma = v.indexOf(',');
        if (comma > 0) {
          v = v.substring(0, comma);
        }
      }
      return v;
    }
    return node.src() ?? '';
  }

  private coverOf(node: HtmlNode, selector: string, html: string | null): string {
    if (this.isRegex(selector) && html !== null) {
      const found = this.regexFirst(html, selector);
      if (found.length > 0) {
        return this.absImage(found);
      }
    }
    let child = node;
    if (selector.length > 0) {
      const c = node.getChild(selector);
      if (c !== null) {
        child = c;
      }
    }
    return this.absImage(this.imageAttr(child, ''));
  }

  private regexFirst(html: string, pattern: string): string {
    try {
      const m = new RegExp(pattern).exec(html);
      if (m !== null) {
        return m.length > 1 && m[1] !== undefined ? m[1] : m[0];
      }
    } catch (e) {
      return '';
    }
    return '';
  }

  private isFault(url: string): boolean {
    return this.config.parseImageFaultImage.length > 0 && url.includes(this.config.parseImageFaultImage);
  }

  parseCheck(html: string): string {
    return this.firstText(HtmlNode.parse(html), this.config.parseInfoUpdate);
  }
}
