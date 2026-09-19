/** 拷贝漫画 CopyMH (TYPE=26)：JSON API，多域名容灾（移植自 CopyMH.java）。 */

import { Parser, ParserRequest, UrlFilter } from './Parser';
import { HttpHeader } from '../network/HttpClient';
import { Comic, Chapter, ImageInfo } from '../model/Model';
import { JsonObj } from '../common/Json';
import { StringUtils } from '../common/StringUtils';
import { BusinessError } from './BusinessError';

const API_HOSTS: string[] = [
  'https://mapi.copy2000.site',
  'https://api.copy2000.online',
  'https://www.copy3000.com',
];

const WEB_HOSTS: string[] = [
  'https://www.2026copy.com',
  'https://www.copy3000.com',
  'https://www.mangacopy.com',
  'https://www.copy20.com',
  'https://www.2025copy.com',
];

const COPY_VERSION = '2025.11.21';

export class CopyMangaParser extends Parser {
  constructor() {
    super(26, '拷贝漫画');
    this.mFilters = [
      new UrlFilter('copy3000.com', '\\w+', 0),
      new UrlFilter('2026copy.com', '\\w+', 0),
      new UrlFilter('2025copy.com', '\\w+', 0),
      new UrlFilter('mangacopy.com', '\\w+', 0),
      new UrlFilter('copymanga.com', '\\w+', 0),
      new UrlFilter('copy20.com', '\\w+', 0),
      new UrlFilter('copy2000.site', '\\w+', 0),
      new UrlFilter('copy2000.online', '\\w+', 0),
    ];
  }

  private apiRequest(path: string): ParserRequest {
    const headers = new HttpHeader();
    headers.set('User-Agent', 'COPY/3.0.0');
    headers.set('Accept', 'application/json');
    headers.set('version', COPY_VERSION);
    headers.set('platform', '1');
    headers.set('webp', '1');
    headers.set('region', '1');
    if (API_HOSTS.length > 1) {
      const rest: string[] = [];
      for (let i = 1; i < API_HOSTS.length; i++) {
        rest.push(API_HOSTS[i] + path);
      }
      headers.set('X-Cimoc-Fallback', rest.join(','));
    }
    return new ParserRequest(API_HOSTS[0] + path, headers);
  }

  getHeader(): HttpHeader | null {
    const headers = new HttpHeader();
    headers.set('Referer', WEB_HOSTS[1] + '/');
    headers.set('User-Agent', 'COPY/3.0.0');
    return headers;
  }

  getSearchRequest(keyword: string, page: number): ParserRequest | null {
    const path = StringUtils.format('/api/v3/search/comic?platform=1&limit=30&offset=%s&q=%s',
      String((page - 1) * 30), StringUtils.urlEncode(keyword));
    return this.apiRequest(path);
  }

  parseSearch(html: string, page: number): Comic[] {
    BusinessError.checkApi(html);
    const out: Comic[] = [];
    const root = JsonObj.parse(html);
    const results = root !== null ? root.optObj('results') : null;
    const list = results !== null ? results.optArray('list') : null;
    if (list === null) {
      return out;
    }
    for (let i = 0; i < list.length(); i++) {
      const o = list.optObj(i);
      if (o === null) {
        continue;
      }
      const cid = o.optString('path_word');
      const title = o.optString('name');
      if (cid.length === 0 || title.length === 0) {
        continue;
      }
      let author = '';
      const authors = o.optArray('author');
      if (authors !== null && authors.length() > 0) {
        const a0 = authors.optObj(0);
        if (a0 !== null) {
          author = a0.optString('name').trim();
        }
      }
      out.push(new Comic(26, cid, title, o.optString('cover'), o.optString('datetime_updated'), author));
    }
    return out;
  }

  getInfoRequest(cid: string): ParserRequest | null {
    return this.apiRequest(`/api/v3/comic2/${cid}?platform=1`);
  }

  parseInfo(html: string, comic: Comic): Comic {
    BusinessError.checkApi(html);
    const root = JsonObj.parse(html);
    const info = root !== null ? root.optObj('results') : null;
    const body = info !== null ? info.optObj('comic') : null;
    if (body === null) {
      return comic;
    }
    let author = '';
    const authors = body.optArray('author');
    if (authors !== null && authors.length() > 0) {
      const a0 = authors.optObj(0);
      if (a0 !== null) {
        author = a0.optString('name');
      }
    }
    const status = body.optObj('status');
    const finish = status !== null ? status.optInt('value') !== 0 : false;
    comic.setInfo(body.optString('name'), body.optString('cover'),
      body.optString('datetime_updated'), body.optString('brief'), author, finish);
    return comic;
  }

  getChapterRequest(html: string, cid: string): ParserRequest | null {
    return this.apiRequest(`/api/v3/comic/${cid}/group/default/chapters?limit=500&offset=0&platform=1`);
  }

  parseChapter(html: string, comic: Comic, sourceComic: number): Chapter[] {
    BusinessError.checkApi(html);
    const list: Chapter[] = [];
    const root = JsonObj.parse(html);
    const results = root !== null ? root.optObj('results') : null;
    const arr = results !== null ? results.optArray('list') : null;
    if (arr !== null) {
      for (let i = 0; i < arr.length(); i++) {
        const o = arr.optObj(i);
        if (o === null) {
          continue;
        }
        list.push(new Chapter(0, sourceComic, o.optString('name'), o.optString('uuid'), '默认'));
      }
    }
    return list.reverse();
  }

  getImagesRequest(cid: string, path: string): ParserRequest | null {
    return this.apiRequest(`/api/v3/comic/${cid}/chapter2/${path}?platform=1`);
  }

  parseImages(html: string, chapter: Chapter): ImageInfo[] | null {
    BusinessError.checkApi(html);
    const list: ImageInfo[] = [];
    const root = JsonObj.parse(html);
    const results = root !== null ? root.optObj('results') : null;
    const ch = results !== null ? results.optObj('chapter') : null;
    const arr = ch !== null ? ch.optArray('contents') : null;
    if (arr === null) {
      return list;
    }
    for (let i = 0; i < arr.length(); i++) {
      const o = arr.optObj(i);
      if (o === null) {
        continue;
      }
      const url = o.optString('url');
      if (url.length === 0) {
        continue;
      }
      list.push(new ImageInfo(0, chapter.id, i + 1, url, false));
    }
    return list;
  }

  parseCheck(html: string): string {
    const root = JsonObj.parse(html);
    const info = root !== null ? root.optObj('results') : null;
    const body = info !== null ? info.optObj('comic') : null;
    return body !== null ? body.optString('datetime_updated') : '';
  }

  /** 分类（发现页）。args 由 UI 传入 ordering/theme 等。 */
  categoryRequest(ordering: string, theme: string, page: number): ParserRequest {
    let path = `/api/v3/comics?limit=30&offset=${Math.max(page - 1, 0) * 30}&platform=1&ordering=${ordering}`;
    if (theme.length > 0) {
      path += `&theme=${theme}`;
    }
    return this.apiRequest(path);
  }

  parseCategory(html: string, page: number): Comic[] {
    return this.parseSearch(html, page);
  }
}
