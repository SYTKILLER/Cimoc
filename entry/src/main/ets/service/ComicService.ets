/** 业务编排层（对齐 core/MangaService.kt + Manga.java）：网络+解析+入库。 */

import { HttpClient, HttpError, HttpHeader } from '../network/HttpClient';
import { Storage } from '../data/Storage';
import { fileIo as fs } from '@kit.CoreFileKit';
import { SourceManager } from '../source/SourceManager';
import { Parser, ParserRequest } from '../source/Parser';
import { Comic, Chapter, ImageInfo, IdUtils } from '../model/Model';
import { ComicDao, ChapterDao, ImageDao, SourceDao } from '../data/Daos';
import { common } from '@kit.AbilityKit';

export class SourceResult {
  readonly type: number;
  readonly title: string;
  comics: Comic[] = [];
  error: string;
  /** 源站结果已按相关度排序（searchRanked 源），聚合本地排序时保序。 */
  ranked: boolean = false;

  constructor(type: number, title: string) {
    this.type = type;
    this.title = title;
    this.error = '';
  }
}

export class ComicService {
  private static instance: ComicService | null = null;

  private readonly client: HttpClient;
  private readonly comicDao: ComicDao;
  private readonly chapterDao: ChapterDao;
  private readonly imageDao: ImageDao;
  private readonly sourceDao: SourceDao;

  static get(context: common.UIAbilityContext): ComicService {
    if (ComicService.instance === null) {
      ComicService.instance = new ComicService(context);
    }
    return ComicService.instance;
  }

  private constructor(context: common.UIAbilityContext) {
    this.client = HttpClient.get();
    this.comicDao = new ComicDao(context);
    this.chapterDao = new ChapterDao(context);
    this.imageDao = new ImageDao(context);
    this.sourceDao = new SourceDao(context);
    this.storage = new Storage(context);
  }

  private async executeText(request: ParserRequest): Promise<string> {
    if (request.body.length > 0) {
      // POST 场景基础版未用到；保留扩展点
    }
    return this.client.fetchText(request.url, request.headers);
  }

  /** 单源搜索。 */
  async searchOne(type: number, keyword: string, page: number): Promise<SourceResult> {
    const parser = SourceManager.get().getParser(type);
    const result = new SourceResult(type, parser !== null ? parser.getTitle() : String(type));
    if (parser === null) {
      result.error = 'parser not found';
      return result;
    }
    result.ranked = parser.isSearchRanked();
    try {
      const request = parser.getSearchRequest(keyword, page);
      if (request === null) {
        return result;
      }
      const html = await this.executeText(request);
      result.comics = parser.parseSearch(html, page);
    } catch (e) {
      result.error = e instanceof Error ? e.message : String(e);
    }
    return result;
  }

  /** 启用源 type 列表（从 DB 读）。 */
  async enabledSourceTypes(): Promise<number[]> {
    const list = await this.sourceDao.list();
    const out: number[] = [];
    for (const s of list) {
      if (s.enable) {
        out.push(s.type);
      }
    }
    return out;
  }

  /** 多源聚合搜索：单源失败不影响其他源。 */
  async searchAll(keyword: string, page: number, types: number[]): Promise<SourceResult[]> {
    const tasks: Promise<SourceResult>[] = [];
    for (const t of types) {
      tasks.push(this.searchOne(t, keyword, page));
    }
    const settled = await Promise.allSettled(tasks);
    const out: SourceResult[] = [];
    for (const s of settled) {
      if (s.status === 'fulfilled') {
        out.push(s.value);
      }
    }
    return out;
  }

  /**
   * 详情+章节：库里有收藏/历史记录则复用，否则新建。
   * 返回 comic（含 id）与全部章节。
   */
  async getComicInfo(type: number, cid: string): Promise<[Comic, Chapter[]] | null> {
    const parser = SourceManager.get().getParser(type);
    if (parser === null) {
      return null;
    }
    let comic = await this.comicDao.load(type, cid);
    if (comic === null) {
      comic = new Comic(type, cid, '');
    }
    // 先入库拿到 id（章节的 sourceComic 依赖它）
    await this.comicDao.insertOrReplace(comic);
    let detailHtml = '';
    const request = parser.getInfoRequest(cid);
    if (request !== null) {
      detailHtml = await this.executeText(request);
      parser.parseInfo(detailHtml, comic);
      await this.comicDao.insertOrReplace(comic);
    }
    let chapters: Chapter[] = [];
    const chRequest = parser.getChapterRequest(detailHtml, cid);
    if (chRequest !== null) {
      const chHtml = await this.executeText(chRequest);
      chapters = parser.parseChapter(chHtml, comic, comic.id);
    } else {
      chapters = parser.parseChapter(detailHtml, comic, comic.id);
    }
    if (parser.isReverseOrder()) {
      chapters = chapters.reverse();
    }
    if (chapters.length > 0) {
      chapters = await this.chapterDao.updateOrInsert(comic.id, chapters);
    } else {
      chapters = await this.chapterDao.list(comic.id);
    }
    return [comic, chapters];
  }

  /** 追更检查：返回最新章节描述（无更新返回 ''）。 */
  async checkUpdate(type: number, cid: string, oldUpdate: string): Promise<string> {
    const parser = SourceManager.get().getParser(type);
    if (parser === null) {
      return '';
    }
    try {
      const request = parser.getCheckRequest(cid);
      if (request === null) {
        return '';
      }
      const html = await this.executeText(request);
      const update = parser.parseCheck(html);
      return update.length > 0 && update !== oldUpdate ? update : '';
    } catch (e) {
      return '';
    }
  }

  private readonly storage: Storage;

  /**
   * 章节图片列表：已下载则离线读取 → 缓存表 → 网络解析。
   * offlineOnly=true（"本地"页离线阅读）时只允许本地文件，缺失即返回空，绝不发起网络请求。
   */
  async loadChapterImages(comic: Comic, chapter: Chapter, forceRefresh: boolean = false,
                          offlineOnly: boolean = false): Promise<ImageInfo[]> {
    // 离线优先
    if (chapter.download) {
      const offline = this.offlineImages(comic, chapter);
      if (offline.length > 0) {
        return offline;
      }
      if (offlineOnly) {
        return [];
      }
    }
    if (!forceRefresh) {
      const cached = await this.imageDao.list(chapter.id);
      if (cached.length > 0) {
        return cached;
      }
    }
    return this.parseImagesOnline(comic, chapter);
  }

  /**
   * 在线解析章节图片列表（含分页拼接、跨页去重、入库）。
   * 下载任务专用入口：不做离线/缓存表回退——部分旧任务/旧缓存只有第一分页的 50 张，
   * 回退会让下载永远停在 50 张；这里强制拿全量真值。
   *
   * 失败语义：任一环节失败只保留已抓部分，且 COMPLETE 落 false（不把截断结果
   * 伪装成完整章节）；站点越界分页会重发已有页（有图全重复）视为正常结束。
   */
  async parseImagesOnline(comic: Comic, chapter: Chapter): Promise<ImageInfo[]> {
    const parser = SourceManager.get().getParser(comic.source);
    if (parser === null) {
      return [];
    }
    const request = parser.getImagesRequest(comic.cid, chapter.path);
    if (request === null) {
      return [];
    }
    let html: string;
    try {
      html = await this.executeText(request);
    } catch (e) {
      // 首页瞬时失败（弱网/降级链路实测超时后立即重发多半可恢复），重试一次
      html = await this.executeText(request);
    }
    let images = parser.parseImages(html, chapter);
    if (images === null || images.length === 0) {
      images = [];
    }
    // 多页拼接：配置了 parseImagePages 的源会把一章拆成每页 N 张图，
    // 后续页可能与前页尾部重叠，按图片路径去重后顺序追加，直到没有新图。
    // 按窗口并行抓取（仅当整个窗口都 0 新图才停），与逐页串行语义等价：
    // 按页号序合并去重；失败页立即串行重试一次——真机上站点连接可能被降级为
    // 近似串行，窗口内排队请求的排队时间计入读超时会成批误杀，单独重发即可恢复。
    // 停止窗口多抓的越界页只会重发末页/首页内容（有图但全重复），不引入新图。
    let sawFailure = false;
    if (images.length > 0 && parser.nextImagesRequest(comic.cid, chapter.path, 2) !== null) {
      const seen = new Set<string>();
      for (const img of images) {
        seen.add(ComicService.imageKey(img.url()));
      }
      const MAX_IMAGE_PAGES = 30;
      const PAGE_WINDOW = 4;
      for (let base = 2; base <= MAX_IMAGE_PAGES; base += PAGE_WINDOW) {
        const requests: ParserRequest[] = [];
        for (let page = base; page < base + PAGE_WINDOW && page <= MAX_IMAGE_PAGES; page++) {
          const nextReq = parser.nextImagesRequest(comic.cid, chapter.path, page);
          if (nextReq === null) {
            break;
          }
          requests.push(nextReq);
        }
        if (requests.length === 0) {
          break;
        }
        const results: Array<ImageInfo[] | null> =
          await Promise.all(requests.map(async (req: ParserRequest): Promise<ImageInfo[] | null> => {
            return this.fetchImagesPage(parser, chapter, req);
          }));
        for (let i = 0; i < results.length; i++) {
          if (results[i] === null) {
            results[i] = await this.fetchImagesPage(parser, chapter, requests[i]);
          }
        }
        let windowFresh = 0;
        let windowParsed = 0;
        let failed = false;
        for (const pageImages of results) {
          if (pageImages === null) {
            failed = true;
            break;
          }
          windowParsed += pageImages.length;
          let num = images.length;
          for (const img of pageImages) {
            const key = ComicService.imageKey(img.url());
            if (seen.has(key)) {
              continue;
            }
            seen.add(key);
            num++;
            windowFresh++;
            images.push(new ImageInfo(0, chapter.id, num, img.url(), img.lazy));
          }
        }
        if (failed) {
          sawFailure = true;
          break;
        }
        // 整窗 0 新图：越界（重发页有图）→ 正常结束；整窗连图都解析不出
        // （反爬/挑战/错误页）→ 异常截断，标记未完成
        if (windowFresh === 0) {
          if (windowParsed === 0) {
            sawFailure = true;
          }
          break;
        }
      }
    }
    await this.imageDao.insertOrReplaceAll(chapter.id, images);
    chapter.count = images.length;
    chapter.complete = !sawFailure && images.length > 0;
    await this.chapterDao.updateCount(chapter);
    return images;
  }

  /** 抓取并解析单个分页；失败返回 null（不抛出），由调用方决定重试/终止。 */
  private async fetchImagesPage(parser: Parser, chapter: Chapter, req: ParserRequest): Promise<ImageInfo[] | null> {
    try {
      const pageHtml = await this.executeText(req);
      const parsed = parser.parseImages(pageHtml, chapter);
      return parsed !== null ? parsed : [];
    } catch (e) {
      return null;
    }
  }

  /** 图片身份：去 scheme/host（分页间 CDN 域名可能不同）与缓存参数后的路径。 */
  private static imageKey(url: string): string {
    let u = url.trim();
    const scheme = u.indexOf('://');
    if (scheme > 0) {
      u = u.substring(scheme + 3);
    }
    const slash = u.indexOf('/');
    if (slash >= 0) {
      u = u.substring(slash);
    }
    const cut = u.search(/[?#]/);
    if (cut >= 0) {
      u = u.substring(0, cut);
    }
    return u;
  }

  private offlineImages(comic: Comic, chapter: Chapter): ImageInfo[] {
    const dir = `${this.storage.downloadDir()}/${comic.source}/${Storage.cleanCid(comic.cid)}/${Storage.cleanCid(chapter.path)}`;
    const out: ImageInfo[] = [];
    try {
      if (!fs.accessSync(dir)) {
        return out;
      }
      const names = this.storage.listImages(dir);
      let num = 0;
      for (const n of names) {
        num++;
        const img = new ImageInfo(0, chapter.id, num, `${dir}/${n}`, false);
        out.push(img);
      }
    } catch (e) {
      return out;
    }
    return out;
  }

  /** 惰性图片二次解析（DM5 类站点）。 */
  async resolveLazy(parserType: number, url: string): Promise<string | null> {
    const parser = SourceManager.get().getParser(parserType);
    if (parser === null) {
      return null;
    }
    const request = parser.getLazyRequest(url);
    if (request === null) {
      return null;
    }
    const html = await this.executeText(request);
    return parser.parseLazy(html, url);
  }

  comicDaoRef(): ComicDao {
    return this.comicDao;
  }

  chapterDaoRef(): ChapterDao {
    return this.chapterDao;
  }
}
