/** 数据模型：字段与 Android 版 Comic/Chapter/ImageUrl/Source 一一对应。 */

import { StringUtils } from '../common/StringUtils';

export class Comic {
  id: number;
  source: number;
  cid: string;
  title: string;
  cover: string;
  update: string;
  intro: string;
  author: string;
  finish: boolean;
  favorite: number;   // 收藏时间戳，0 = 未收藏
  history: number;    // 阅读时间戳，0 = 无历史
  download: number;   // 下载时间戳，0 = 无下载
  last: string;       // 最后阅读章节 path
  page: number;       // 最后阅读页码
  chapter: string;    // 最后阅读章节标题
  highlight: boolean;
  local: boolean;
  localCover: string;   // 运行时字段：本地封面文件路径（不入库）
  localCount: number;   // 运行时字段：已完整缓存章节数（不入库），"本地"页展示用

  constructor(source: number, cid: string, title: string, cover: string = '',
              update: string = '', author: string = '') {
    this.id = 0;
    this.source = source;
    this.cid = cid;
    this.title = title;
    this.cover = cover;
    this.update = update;
    this.intro = '';
    this.author = author;
    this.finish = false;
    this.favorite = 0;
    this.history = 0;
    this.download = 0;
    this.last = '';
    this.page = 0;
    this.chapter = '';
    this.highlight = false;
    this.local = false;
    this.localCover = '';
    this.localCount = 0;
  }

  setInfo(title: string, cover: string, update: string, intro: string,
          author: string, finish: boolean): void {
    if (StringUtils.isNotBlank(title)) {
      this.title = title;
    }
    if (StringUtils.isNotBlank(cover)) {
      this.cover = cover;
    }
    this.update = update;
    this.intro = intro;
    this.author = author;
    this.finish = finish;
    this.highlight = false;
  }
}

export class Chapter {
  id: number;
  sourceComic: number;
  title: string;
  path: string;
  count: number;
  complete: boolean;
  download: boolean;
  group: string;

  constructor(id: number, sourceComic: number, title: string, path: string, group: string = '') {
    this.id = id;
    this.sourceComic = sourceComic;
    this.title = title;
    this.path = path;
    this.count = 0;
    this.complete = false;
    this.download = false;
    this.group = group;
  }
}

export class ImageInfo {
  id: number;
  chapterId: number;
  num: number;
  urls: string[];      // 多线路
  lazy: boolean;       // 需二次解析
  state: number;       // 0=NULL 1=PAGE_1 2=PAGE_2（分屏状态）
  width: number;
  height: number;

  constructor(id: number, chapterId: number, num: number, url: string, lazy: boolean) {
    this.id = id;
    this.chapterId = chapterId;
    this.num = num;
    this.urls = url === '' ? [] : [url];
    this.lazy = lazy;
    this.state = 0;
    this.width = 0;
    this.height = 0;
  }

  url(): string {
    return this.urls.length > 0 ? this.urls[0] : '';
  }
}

export class SourceInfo {
  id: number;
  title: string;
  type: number;
  enable: boolean;

  constructor(id: number, title: string, type: number, enable: boolean) {
    this.id = id;
    this.title = title;
    this.type = type;
    this.enable = enable;
  }
}

/** 章节与合成 ID 规则：sourceComic = Number(source + '000' + index) */
export class IdUtils {
  static sourceComic(source: number, comicRowId: number): number {
    return Number(`${source}000${comicRowId}`);
  }

  static chapterId(chapterRowId: number, index: number): number {
    return Number(`${chapterRowId}000${index}`);
  }
}

/** 阅读器页面参数。local=true 时离线锁定：图片只允许本地文件，禁止网络回退。 */
export class ReaderArgs {
  comic: Comic;
  chapters: Chapter[];
  index: number;
  local: boolean;

  constructor(comic: Comic, chapters: Chapter[], index: number, local: boolean = false) {
    this.comic = comic;
    this.chapters = chapters;
    this.index = index;
    this.local = local;
  }
}

/** 详情页参数：local=true 时进入本地模式（只展示/阅读已缓存章节，全程不联网）。
 *  chapters 由入口页查本地 CHAPTER 表预先备好（仅 download&&complete），详情页同步渲染、零加载态。 */
export class DetailArgs {
  comic: Comic;
  local: boolean;
  chapters: Chapter[];

  constructor(comic: Comic, local: boolean, chapters: Chapter[] = []) {
    this.comic = comic;
    this.local = local;
    this.chapters = chapters;
  }
}

/** 下载任务（state 运行时不入库，对齐 Android Task）。
 *  @Observed：下载中页面用 @ObjectLink 持有，进度逐页原位刷新，避免整行重建闪烁。 */
@Observed
export class Task {
  id: number;
  key: number;        // COMIC._id
  path: string;
  title: string;
  progress: number;
  max: number;
  // 运行时
  state: number;
  source: number;
  cid: string;
  comicTitle: string;

  static readonly STATE_FINISH = 0;
  static readonly STATE_PAUSE = 1;
  static readonly STATE_DOING = 3;
  static readonly STATE_WAIT = 4;
  static readonly STATE_ERROR = 5;

  constructor(key: number, path: string, title: string, progress: number, max: number) {
    this.id = 0;
    this.key = key;
    this.path = path;
    this.title = title;
    this.progress = progress;
    this.max = max;
    this.state = Task.STATE_WAIT;
    this.source = 0;
    this.cid = '';
    this.comicTitle = '';
  }

  isFinish(): boolean {
    return this.max !== 0 && this.progress === this.max;
  }
}
