/**
 * 下载管理器（对齐 DownloadService.Worker 状态机，串行简化版）：
 * 解析图片列表 → 逐页下载（重试×3）→ 写文件 + index.cdif → 断点续传（Task.progress）。
 */

import { ComicService } from '../service/ComicService';
import { TaskDao } from '../data/TaskDao';
import { ChapterDao } from '../data/Daos';
import { Storage } from '../data/Storage';
import { Db, UrlsCodec } from '../data/Db';
import { HttpClient, HttpHeader } from '../network/HttpClient';
import { SourceManager } from '../source/SourceManager';
import { Comic, Chapter, Task } from '../model/Model';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { relationalStore } from '@kit.ArkData';

/** 轻量读取图片 URL 列表。 */
class ImageDaoLite {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  async listUrls(chapterId: number): Promise<string[]> {
    const store = await Db.get(this.ctx);
    const pred = new relationalStore.RdbPredicates('IMAGE_URL');
    pred.equalTo('COMIC_CHAPTER', chapterId).orderByAsc('NUM');
    const rs = await store.query(pred, ['URLS']);
    const out: string[] = [];
    while (rs.goToNextRow()) {
      const urls = UrlsCodec.decode(rs.getString(rs.getColumnIndex('URLS')) ?? '');
      if (urls.length > 0) {
        out.push(urls[0]);
      }
    }
    rs.close();
    return out;
  }
}

export class DownloadManager {
  private static instance: DownloadManager | null = null;

  private readonly ctx: common.UIAbilityContext;
  private readonly taskDao: TaskDao;
  private readonly chapterDao: ChapterDao;
  private readonly storage: Storage;
  private readonly client: HttpClient;
  private running = false;
  private imageCache: Map<string, string[]> = new Map();
  private currentTaskId = 0;

  static get(context: common.UIAbilityContext): DownloadManager {
    if (DownloadManager.instance === null) {
      DownloadManager.instance = new DownloadManager(context);
    }
    return DownloadManager.instance;
  }

  private constructor(context: common.UIAbilityContext) {
    this.ctx = context;
    this.taskDao = new TaskDao(context);
    this.chapterDao = new ChapterDao(context);
    this.storage = new Storage(context);
    this.client = HttpClient.get();
  }

  taskDaoRef(): TaskDao {
    return this.taskDao;
  }

  isRunning(): boolean {
    return this.running;
  }

  /** 当前正在下载的任务 _id（0 = 空闲），供 UI 区分"下载中/等待中"。 */
  currentId(): number {
    return this.currentTaskId;
  }

  /** 任务/进度变化通知：下载中页面与书库"本地"页监听该键实时刷新。 */
  private notify(): void {
    AppStorage.setOrCreate('download_dirty', Date.now());
  }

  /** 加入下载队列。下载前查重（对齐用户要求：查重放在下载阶段）：
   *  已完整下载 → 跳过返回 false；上次失败 → 重置重试；已在队列 → 恢复调度；
   *  新任务 → 入队。返回是否产生了新的下载动作。 */
  async addDownload(comic: Comic, chapter: Chapter): Promise<boolean> {
    const existing = await this.taskDao.load(comic.id, chapter.path);
    if (existing !== null && existing.isFinish()) {
      chapter.download = true;
      return false; // 已完整下载，查重跳过
    }
    if (existing !== null) {
      // 已有记录：失败的重置续传，中断的恢复调度
      if (existing.max < 0) {
        existing.progress = 0;
        existing.max = 0;
      } else if (existing.max > 0 && existing.id !== this.currentTaskId) {
        // 恢复队列时强制重新解析全量列表（自愈旧的不完整任务），进度保留断点
        existing.max = 0;
      }
      await this.taskDao.update(existing);
      chapter.download = true;
      await this.chapterDao.updateDownloadFlag(chapter);
      this.notify();
      this.pump();
      return true;
    }
    const task = new Task(comic.id, chapter.path, chapter.title, 0, 0);
    await this.taskDao.insertIfNotExist(task);
    chapter.download = true;
    await this.chapterDao.updateDownloadFlag(chapter);
    if (comic.download === 0) {
      comic.download = Date.now();
      await ComicService.get(this.ctx).comicDaoRef().insertOrReplace(comic);
      // 首次缓存：把详情页（资料+章节列表）快照一份到本地，"本地"页据此离线展示
      await this.writeComicCdif(comic);
    }
    this.notify();
    this.pump();
    return true;
  }

  /** 漫画详情快照（cimoc JSON）：详情字段 + 全章节状态。入队与章节完成时刷新。 */
  private async writeComicCdif(comic: Comic): Promise<void> {
    try {
      const chapters = await this.chapterDao.list(comic.id);
      const arr: string[] = [];
      for (const c of chapters) {
        arr.push(`{"title":${JSON.stringify(c.title)},"path":${JSON.stringify(c.path)},` +
          `"group":${JSON.stringify(c.group)},"download":${c.download ? 1 : 0},"complete":${c.complete ? 1 : 0}}`);
      }
      const meta = `cimoc{"version":"1","type":"comic","title":${JSON.stringify(comic.title)},` +
        `"cover":${JSON.stringify(comic.cover)},"author":${JSON.stringify(comic.author)},` +
        `"update":${JSON.stringify(comic.update)},"intro":${JSON.stringify(comic.intro)},` +
        `"finish":${comic.finish ? 1 : 0},"chapters":[${arr.join(',')}]}`;
      const path = this.storage.comicCdifPath(comic.source, comic.cid);
      const f = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, meta);
      fs.closeSync(f);
    } catch (e) {
      // 快照写失败不影响下载
    }
  }

  /** 失败任务重试：清零进度后重新入队。 */
  async retry(task: Task): Promise<void> {
    task.progress = 0;
    task.max = 0;
    await this.taskDao.update(task);
    this.notify();
    this.pump();
  }

  /** 从队列移除任务。未完成的章节一并清掉"缓存中"标记（已完成章节保持"已下载"）。 */
  async deleteTask(task: Task): Promise<void> {
    await this.taskDao.delete(task);
    const comic = await ComicService.get(this.ctx).comicDaoRef().loadById(task.key);
    if (comic !== null) {
      const chapters = await this.chapterDao.list(comic.id);
      for (const c of chapters) {
        if (c.path === task.path && !c.complete) {
          c.download = false;
          await this.chapterDao.updateDownloadFlag(c);
          break;
        }
      }
      await this.refreshComicDownloadState(comic);
    }
    this.notify();
    AppStorage.setOrCreate('library_dirty', Date.now());
  }

  /** 删除某章节的本地缓存：任务行 + 章节目录 + 下载标记；漫画已无缓存时清空下载态与封面/快照。 */
  async deleteChapterCache(comicId: number, chapterPath: string): Promise<void> {
    const comic = await ComicService.get(this.ctx).comicDaoRef().loadById(comicId);
    if (comic === null) {
      return;
    }
    const task = await this.taskDao.load(comicId, chapterPath);
    if (task !== null) {
      await this.taskDao.delete(task);
    }
    this.storage.removeDir(this.storage.chapterDir(comic.source, comic.cid, chapterPath));
    const chapters = await this.chapterDao.list(comicId);
    for (const c of chapters) {
      if (c.path === chapterPath) {
        c.download = false;
        c.complete = false;
        await this.chapterDao.updateDownloadFlag(c);
        await this.chapterDao.updateCount(c);
        break;
      }
    }
    await this.refreshComicDownloadState(comic);
    this.notify();
    AppStorage.setOrCreate('library_dirty', Date.now());
  }

  /** 漫画已无缓存章节且无排队任务时：清下载态 + 删封面/详情快照，"本地"页不再展示。 */
  private async refreshComicDownloadState(comic: Comic): Promise<void> {
    const chapters = await this.chapterDao.list(comic.id);
    let cached = 0;
    for (const c of chapters) {
      if (c.download) {
        cached++;
      }
    }
    if (cached > 0) {
      // 还有缓存章节：仅刷新详情快照里的章节状态
      await this.writeComicCdif(comic);
      return;
    }
    const tasks = await this.taskDao.list();
    for (const t of tasks) {
      if (t.key === comic.id && t.max >= 0 && !t.isFinish()) {
        return; // 还有排队任务，保留下载态
      }
    }
    comic.download = 0;
    await ComicService.get(this.ctx).comicDaoRef().insertOrReplace(comic);
    this.storage.removeFile(this.storage.comicCdifPath(comic.source, comic.cid));
    this.storage.removeFile(`${this.storage.comicDir(comic.source, comic.cid)}/cover`);
  }

  /** 调度循环：按加入顺序执行未完成任务（max<0 为失败任务，跳过避免死循环）。 */
  private async pump(): Promise<void> {
    if (this.running) {
      return;
    }
    this.running = true;
    this.notify();
    try {
      for (;;) {
        const tasks = await this.taskDao.listPendingAsc();
        let next: Task | null = null;
        for (const t of tasks) {
          if (t.max >= 0 && !t.isFinish()) {
            next = t;
            break;
          }
        }
        if (next === null) {
          break;
        }
        this.currentTaskId = next.id;
        this.notify();
        await this.runTask(next);
      }
    } finally {
      this.currentTaskId = 0;
      this.running = false;
      this.notify();
    }
  }

  private async runTask(task: Task): Promise<void> {
    const comic = await ComicService.get(this.ctx).comicDaoRef().loadById(task.key);
    if (comic === null) {
      task.max = -1;
      await this.taskDao.update(task);
      this.notify();
      return;
    }
    try {
      // 0. 封面离线化（失败不阻塞下载）
      await this.ensureCover(comic);
      // 1. 解析图片列表（max>0 表示已解析，支持断点）
      if (task.max === 0) {
        const chapters = await this.chapterDao.list(comic.id);
        let chapter: Chapter | null = null;
        for (const c of chapters) {
          if (c.path === task.path) {
            chapter = c;
            break;
          }
        }
        if (chapter === null) {
          task.max = -1;
          await this.taskDao.update(task);
          this.notify();
          return;
        }
        // 下载解析专用：强制在线全量分页解析，不走离线/缓存回退（否则会停在旧的第一分页 50 张）
        const images = await ComicService.get(this.ctx).parseImagesOnline(comic, chapter);
        // 空列表置失败标记（max=-1），否则 max 留 0 会被调度反复重解析
        task.max = images.length > 0 ? images.length : -1;
        await this.taskDao.update(task);
        this.notify();
        if (images.length === 0) {
          return;
        }
        this.imageCache.delete(task.path);
      }
      // 2. 逐页下载
      const parser = SourceManager.get().getParser(comic.source);
      const headers: HttpHeader | null = parser !== null ? parser.imageHeaders() : null;
      const dir = this.storage.ensureDownloadTree(comic.source, comic.cid, task.path);
      const cdifPath = `${dir}/index.cdif`;
      try {
        if (!fs.accessSync(cdifPath)) {
          const meta = `cimoc{"version":"1","type":"chapter","title":${JSON.stringify(task.title)},"path":${JSON.stringify(task.path)}}`;
          const f = fs.openSync(cdifPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
          fs.writeSync(f.fd, meta);
          fs.closeSync(f);
        }
      } catch (e) {
        // 索引写失败不阻塞下载
      }
      for (let page = task.progress + 1; page <= task.max; page++) {
        // 任务可能已在队列中被删除：每页检查，已删即中止
        const alive = await this.taskDao.load(task.key, task.path);
        if (alive === null) {
          return;
        }
        const fileName = this.storage.imageFileName(page, '');
        const filePath = `${dir}/${fileName}`;
        if (fs.accessSync(filePath)) {
          task.progress = page;
          await this.taskDao.update(task);
          this.notify();
          continue;
        }
        const bytes = await this.fetchPage(page, task, headers, 0);
        if (bytes === null) {
          throw new Error(`page ${page} failed`);
        }
        this.storage.saveImageBytes(dir, fileName, bytes);
        task.progress = page;
        await this.taskDao.update(task);
        this.notify();
      }
      // 3. 完成标记
      if (task.max > 0 && task.progress >= task.max) {
        const chapters = await this.chapterDao.list(comic.id);
        for (const c of chapters) {
          if (c.path === task.path) {
            c.download = true;
            c.count = task.max;
            c.complete = true;
            await this.chapterDao.updateCount(c);
            await this.chapterDao.updateDownloadFlag(c);
            break;
          }
        }
        if (comic.download === 0) {
          comic.download = Date.now();
          await ComicService.get(this.ctx).comicDaoRef().insertOrReplace(comic);
        }
        // 章节完成：刷新详情快照里的章节状态
        await this.writeComicCdif(comic);
      }
    } catch (e) {
      // 失败：进度已持久化，下次 pump 续传
    }
  }

  /** 封面离线化：下载目录内无 cover 文件时拉取一次，供"本地"页离线展示。带源站图片请求头（部分 CDN 校验 Referer）。 */
  private async ensureCover(comic: Comic): Promise<void> {
    try {
      if (comic.cover.length === 0) {
        return;
      }
      if (this.storage.localCoverPath(comic.source, comic.cid).length > 0) {
        return;
      }
      const parser = SourceManager.get().getParser(comic.source);
      const headers: HttpHeader | null = parser !== null ? parser.imageHeaders() : null;
      const resp = await this.client.fetchBytes(comic.cover, headers);
      if (resp.code === 200 && resp.bytes.byteLength > 0) {
        this.storage.saveImageBytes(this.storage.comicDir(comic.source, comic.cid), 'cover', resp.bytes);
      }
    } catch (e) {
      // 封面拉取失败不影响章节下载
    }
  }

  private async fetchPage(page: number, task: Task, headers: HttpHeader | null, tried: number): Promise<ArrayBuffer | null> {
    const images = await this.imagesForTask(task);
    if (images === null || page > images.length) {
      return null;
    }
    const url = images[page - 1];
    if (url.length === 0) {
      return null;
    }
    if (url.startsWith('/') || url.startsWith('file://')) {
      return this.storage.readFileBytes(url.replace('file://', ''));
    }
    try {
      const resp = await this.client.fetchBytes(url, headers);
      if (resp.code === 200 && resp.bytes.byteLength > 0) {
        return resp.bytes;
      }
    } catch (e) {
      // retry below
    }
    if (tried < 3) {
      await this.sleep(800);
      return this.fetchPage(page, task, headers, tried + 1);
    }
    return null;
  }

  private async imagesForTask(task: Task): Promise<string[] | null> {
    const cached = this.imageCache.get(task.path);
    if (cached !== undefined) {
      return cached;
    }
    const comic = await ComicService.get(this.ctx).comicDaoRef().loadById(task.key);
    if (comic === null) {
      return null;
    }
    const chapters = await this.chapterDao.list(comic.id);
    let chapterId = 0;
    for (const c of chapters) {
      if (c.path === task.path) {
        chapterId = c.id;
        break;
      }
    }
    if (chapterId === 0) {
      return null;
    }
    const rows = await new ImageDaoLite(this.ctx).listUrls(chapterId);
    this.imageCache.set(task.path, rows);
    return rows;
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: (v: void) => void) => {
      setTimeout((): void => {
        resolve();
      }, ms);
    });
  }
}
