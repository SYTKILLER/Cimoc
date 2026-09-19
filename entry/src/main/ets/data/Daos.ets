/** DAO 层：Comic/Chapter/ImageUrl/Source（异步 Promise，UI 直接 await）。 */

import { relationalStore } from '@kit.ArkData';
import { Db, UrlsCodec } from './Db';
import { Comic, Chapter, ImageInfo, SourceInfo } from '../model/Model';
import { common } from '@kit.AbilityKit';

export class ComicDao {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  private async store(): Promise<relationalStore.RdbStore> {
    return Db.get(this.ctx);
  }

  private static fromRow(rs: relationalStore.ResultSet): Comic {
    const c = new Comic(
      rs.getLong(rs.getColumnIndex('SOURCE')),
      rs.getString(rs.getColumnIndex('CID')) ?? '',
      rs.getString(rs.getColumnIndex('TITLE')) ?? '',
      rs.getString(rs.getColumnIndex('COVER')) ?? '',
      rs.getString(rs.getColumnIndex('LAST_UPDATE')) ?? '',
      rs.getString(rs.getColumnIndex('AUTHOR')) ?? '');
    c.id = rs.getLong(rs.getColumnIndex('_id'));
    c.intro = rs.getString(rs.getColumnIndex('INTRO')) ?? '';
    const finish = rs.getLong(rs.getColumnIndex('FINISH'));
    c.finish = finish !== 0;
    const fav = rs.getColumnIndex('FAVORITE');
    c.favorite = rs.isColumnNull(fav) ? 0 : rs.getLong(fav);
    const his = rs.getColumnIndex('HISTORY');
    c.history = rs.isColumnNull(his) ? 0 : rs.getLong(his);
    const dl = rs.getColumnIndex('DOWNLOAD');
    c.download = rs.isColumnNull(dl) ? 0 : rs.getLong(dl);
    c.last = rs.getString(rs.getColumnIndex('LAST')) ?? '';
    c.page = rs.getLong(rs.getColumnIndex('PAGE'));
    c.chapter = rs.getString(rs.getColumnIndex('CHAPTER')) ?? '';
    c.highlight = rs.getLong(rs.getColumnIndex('HIGHLIGHT')) !== 0;
    c.local = rs.getLong(rs.getColumnIndex('LOCAL')) !== 0;
    return c;
  }

  private static readonly COLS =
    '_id,SOURCE,CID,TITLE,COVER,HIGHLIGHT,LOCAL,LAST_UPDATE,FINISH,FAVORITE,HISTORY,DOWNLOAD,LAST,PAGE,CHAPTER,URL,INTRO,AUTHOR';

  async load(source: number, cid: string): Promise<Comic | null> {
    const store = await this.store();
    const pred = new relationalStore.RdbPredicates('COMIC');
    pred.equalTo('SOURCE', source).and().equalTo('CID', cid);
    const rs = await store.query(pred, ComicDao.COLS.split(','));
    let found: Comic | null = null;
    if (rs.goToFirstRow()) {
      found = ComicDao.fromRow(rs);
    }
    rs.close();
    return found;
  }

  async loadById(id: number): Promise<Comic | null> {
    const store = await this.store();
    const pred = new relationalStore.RdbPredicates('COMIC');
    pred.equalTo('_id', id);
    const rs = await store.query(pred, ComicDao.COLS.split(','));
    let found: Comic | null = null;
    if (rs.goToFirstRow()) {
      found = ComicDao.fromRow(rs);
    }
    rs.close();
    return found;
  }

  async insertOrReplace(comic: Comic): Promise<number> {
    const store = await this.store();
    const row: relationalStore.ValuesBucket = {
      'SOURCE': comic.source,
      'CID': comic.cid,
      'TITLE': comic.title,
      'COVER': comic.cover,
      'HIGHLIGHT': comic.highlight ? 1 : 0,
      'LOCAL': comic.local ? 1 : 0,
      'LAST_UPDATE': comic.update,
      'FINISH': comic.finish ? 1 : 0,
      'FAVORITE': comic.favorite > 0 ? comic.favorite : null,
      'HISTORY': comic.history > 0 ? comic.history : null,
      'DOWNLOAD': comic.download > 0 ? comic.download : null,
      'LAST': comic.last,
      'PAGE': comic.page,
      'CHAPTER': comic.chapter,
      'URL': '',
      'INTRO': comic.intro,
      'AUTHOR': comic.author,
    };
    if (comic.id > 0) {
      const pred = new relationalStore.RdbPredicates('COMIC');
      pred.equalTo('_id', comic.id);
      await store.update(row, pred);
      return comic.id;
    }
    const existing = await this.load(comic.source, comic.cid);
    if (existing !== null) {
      comic.id = existing.id;
      const pred2 = new relationalStore.RdbPredicates('COMIC');
      pred2.equalTo('_id', existing.id);
      await store.update(row, pred2);
      return existing.id;
    }
    const id = await store.insert('COMIC', row);
    comic.id = id;
    return id;
  }

  async updateProgress(comic: Comic): Promise<void> {
    const store = await this.store();
    const row: relationalStore.ValuesBucket = {
      'LAST': comic.last,
      'PAGE': comic.page,
      'CHAPTER': comic.chapter,
      'HISTORY': comic.history > 0 ? comic.history : null,
      'HIGHLIGHT': comic.highlight ? 1 : 0,
    };
    const pred = new relationalStore.RdbPredicates('COMIC');
    pred.equalTo('_id', comic.id);
    await store.update(row, pred);
  }

  async listFavorite(): Promise<Comic[]> {
    return this.listByTimeColumn('FAVORITE');
  }

  async listHistory(): Promise<Comic[]> {
    return this.listByTimeColumn('HISTORY');
  }

  async listDownload(): Promise<Comic[]> {
    return this.listByTimeColumn('DOWNLOAD');
  }

  private async listByTimeColumn(col: string): Promise<Comic[]> {
    const store = await this.store();
    const sql = `SELECT ${ComicDao.COLS} FROM COMIC WHERE ${col} IS NOT NULL ORDER BY ${col} DESC`;
    const rs = await store.querySql(sql);
    const out: Comic[] = [];
    while (rs.goToNextRow()) {
      out.push(ComicDao.fromRow(rs));
    }
    rs.close();
    return out;
  }

  async delete(comic: Comic): Promise<void> {
    const store = await this.store();
    const pred = new relationalStore.RdbPredicates('COMIC');
    pred.equalTo('_id', comic.id);
    await store.delete(pred);
  }

  /** 三态全空时物理删除（对齐 ComicManager.updateOrDelete）。 */
  async updateOrDelete(comic: Comic): Promise<void> {
    if (comic.favorite === 0 && comic.history === 0 && comic.download === 0) {
      await this.delete(comic);
    } else {
      await this.insertOrReplace(comic);
    }
  }

  async cancelHighlight(comic: Comic): Promise<void> {
    comic.highlight = false;
    const store = await this.store();
    const row: relationalStore.ValuesBucket = { 'HIGHLIGHT': 0 };
    const pred = new relationalStore.RdbPredicates('COMIC');
    pred.equalTo('_id', comic.id);
    await store.update(row, pred);
  }
}

export class ChapterDao {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  private async store(): Promise<relationalStore.RdbStore> {
    return Db.get(this.ctx);
  }

  private static fromRow(rs: relationalStore.ResultSet): Chapter {
    const c = new Chapter(
      rs.getLong(rs.getColumnIndex('_id')),
      rs.getLong(rs.getColumnIndex('SOURCE_COMIC')),
      rs.getString(rs.getColumnIndex('TITLE')) ?? '',
      rs.getString(rs.getColumnIndex('PATH')) ?? '',
      rs.getString(rs.getColumnIndex('SOURCE_GROUP')) ?? '');
    c.count = rs.getLong(rs.getColumnIndex('COUNT'));
    c.complete = rs.getLong(rs.getColumnIndex('COMPLETE')) !== 0;
    c.download = rs.getLong(rs.getColumnIndex('DOWNLOAD')) !== 0;
    return c;
  }

  async list(sourceComic: number): Promise<Chapter[]> {
    const store = await this.store();
    const pred = new relationalStore.RdbPredicates('CHAPTER');
    pred.equalTo('SOURCE_COMIC', sourceComic).orderByAsc('_id');
    const rs = await store.query(pred, ['_id', 'SOURCE_COMIC', 'TITLE', 'PATH', 'COUNT', 'COMPLETE', 'DOWNLOAD', 'SOURCE_GROUP']);
    const out: Chapter[] = [];
    while (rs.goToNextRow()) {
      out.push(ChapterDao.fromRow(rs));
    }
    rs.close();
    return out;
  }

  /**
   * 全量同步：以解析顺序为唯一基准合并章节。
   * - 新列表先按 path 去重；
   * - 同 path 的历史重复行只保留一行（优先已下载的），其余连同图片缓存删除；
   * - 全量可信（去重后规模 ≥ 旧列表一半）时，删除不在新列表且未下载的残留行
   *   （如历史镜像时代遗留的失效 path，它们永远不会再被解析命中）；
   * - 无新增行且现存顺序与解析顺序不一致（历史 bug 遗留的乱序）时，按解析顺序重建
   *   全部行（一次性自愈，继承 COUNT/COMPLETE/DOWNLOAD，代价是图片缓存需按章重取）；
   * 返回按解析顺序排列、已带回 _id 与缓存标志的章节。
   */
  async updateOrInsert(sourceComic: number, chapters: Chapter[]): Promise<Chapter[]> {
    const existing = await this.list(sourceComic);
    const byPath: Map<string, Chapter[]> = new Map();
    for (const c of existing) {
      const arr = byPath.get(c.path);
      if (arr === undefined) {
        byPath.set(c.path, [c]);
      } else {
        arr.push(c);
      }
    }
    const store = await this.store();
    const seen: Set<string> = new Set();
    const result: Chapter[] = [];
    let inserted = 0;
    for (const ch of chapters) {
      if (ch.path.length === 0 || seen.has(ch.path)) {
        continue;
      }
      seen.add(ch.path);
      const olds = byPath.get(ch.path);
      if (olds !== undefined && olds.length > 0) {
        let keep = olds[0];
        for (const o of olds) {
          if (o.download && !keep.download) {
            keep = o;
          }
        }
        ch.id = keep.id;
        ch.count = keep.count;
        ch.complete = keep.complete;
        ch.download = keep.download;
        const row: relationalStore.ValuesBucket = {
          'TITLE': ch.title,
          'SOURCE_GROUP': ch.group,
        };
        const pred = new relationalStore.RdbPredicates('CHAPTER');
        pred.equalTo('_id', ch.id);
        await store.update(row, pred);
        for (const o of olds) {
          if (o.id !== keep.id) {
            await this.removeChapterRow(store, o.id);
          }
        }
      } else {
        const row: relationalStore.ValuesBucket = {
          'SOURCE_COMIC': sourceComic,
          'TITLE': ch.title,
          'PATH': ch.path,
          'COUNT': 0,
          'COMPLETE': 0,
          'DOWNLOAD': 0,
          'SOURCE_GROUP': ch.group,
        };
        ch.id = await store.insert('CHAPTER', row);
        inserted++;
      }
      result.push(ch);
    }
    const fullSync = result.length * 2 >= existing.length;
    if (!fullSync) {
      return result;
    }
    for (const o of existing) {
      if (!seen.has(o.path) && !o.download) {
        await this.removeChapterRow(store, o.id);
      }
    }
    // 顺序修复仅在无新增行时执行：避免"最新在前"类站点每次刷新都触发重建
    if (inserted === 0) {
      const keepIds: Set<number> = new Set<number>();
      for (const c of result) {
        keepIds.add(c.id);
      }
      const oldOrder: number[] = [];
      for (const o of existing) {
        if (keepIds.has(o.id)) {
          oldOrder.push(o.id);
        }
      }
      let ordered = oldOrder.length === result.length;
      if (ordered) {
        for (let i = 0; i < result.length; i++) {
          if (result[i].id !== oldOrder[i]) {
            ordered = false;
            break;
          }
        }
      }
      if (!ordered) {
        for (const id of oldOrder) {
          await this.removeChapterRow(store, id);
        }
        for (const ch of result) {
          const row: relationalStore.ValuesBucket = {
            'SOURCE_COMIC': sourceComic,
            'TITLE': ch.title,
            'PATH': ch.path,
            'COUNT': ch.count,
            'COMPLETE': ch.complete ? 1 : 0,
            'DOWNLOAD': ch.download ? 1 : 0,
            'SOURCE_GROUP': ch.group,
          };
          ch.id = await store.insert('CHAPTER', row);
        }
      }
    }
    return result;
  }

  /** 删除单行章节及其图片缓存行（IMAGE_URL.COMIC_CHAPTER 引用章节 _id）。 */
  private async removeChapterRow(store: relationalStore.RdbStore, chapterId: number): Promise<void> {
    const pred = new relationalStore.RdbPredicates('CHAPTER');
    pred.equalTo('_id', chapterId);
    await store.delete(pred);
    const imgPred = new relationalStore.RdbPredicates('IMAGE_URL');
    imgPred.equalTo('COMIC_CHAPTER', chapterId);
    await store.delete(imgPred);
  }

  async updateCount(chapter: Chapter): Promise<void> {
    const store = await this.store();
    const row: relationalStore.ValuesBucket = {
      'COUNT': chapter.count,
      'COMPLETE': chapter.complete ? 1 : 0,
    };
    const pred = new relationalStore.RdbPredicates('CHAPTER');
    pred.equalTo('_id', chapter.id);
    await store.update(row, pred);
  }

  async updateDownloadFlag(chapter: Chapter): Promise<void> {
    const store = await this.store();
    const row: relationalStore.ValuesBucket = { 'DOWNLOAD': chapter.download ? 1 : 0 };
    const pred = new relationalStore.RdbPredicates('CHAPTER');
    pred.equalTo('_id', chapter.id);
    await store.update(row, pred);
  }
}

export class ImageDao {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  private async store(): Promise<relationalStore.RdbStore> {
    return Db.get(this.ctx);
  }

  private static fromRow(rs: relationalStore.ResultSet): ImageInfo {
    const urls = UrlsCodec.decode(rs.getString(rs.getColumnIndex('URLS')) ?? '');
    const img = new ImageInfo(
      rs.getLong(rs.getColumnIndex('_id')),
      rs.getLong(rs.getColumnIndex('COMIC_CHAPTER')),
      rs.getLong(rs.getColumnIndex('NUM')),
      urls.length > 0 ? urls[0] : '',
      rs.getLong(rs.getColumnIndex('LAZY')) !== 0);
    img.urls = urls;
    img.state = rs.getLong(rs.getColumnIndex('STATE'));
    img.width = rs.getLong(rs.getColumnIndex('WIDTH'));
    img.height = rs.getLong(rs.getColumnIndex('HEIGHT'));
    return img;
  }

  async list(chapterId: number): Promise<ImageInfo[]> {
    const store = await this.store();
    const pred = new relationalStore.RdbPredicates('IMAGE_URL');
    pred.equalTo('COMIC_CHAPTER', chapterId).orderByAsc('NUM');
    const rs = await store.query(pred,
      ['_id', 'COMIC_CHAPTER', 'NUM', 'URLS', 'CHAPTER', 'STATE', 'HEIGHT', 'WIDTH', 'LAZY']);
    const out: ImageInfo[] = [];
    while (rs.goToNextRow()) {
      out.push(ImageDao.fromRow(rs));
    }
    rs.close();
    return out;
  }

  async insertOrReplaceAll(chapterId: number, images: ImageInfo[]): Promise<void> {
    const store = await this.store();
    // beginTrans 仅向量库可用（普通关系库抛 801），普通库事务用 createTransaction
    const tx = await store.createTransaction();
    try {
      const pred = new relationalStore.RdbPredicates('IMAGE_URL');
      pred.equalTo('COMIC_CHAPTER', chapterId);
      await tx.delete(pred);
      for (const img of images) {
        const row: relationalStore.ValuesBucket = {
          'COMIC_CHAPTER': chapterId,
          'NUM': img.num,
          'URLS': UrlsCodec.encode(img.urls),
          'CHAPTER': '',
          'STATE': img.state,
          'HEIGHT': img.width,
          'WIDTH': img.width,
          'LAZY': img.lazy ? 1 : 0,
          'LOADING': 0,
          'SUCCESS': 0,
          'DOWNLOAD': 0,
        };
        img.id = await tx.insert('IMAGE_URL', row, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      }
      await tx.commit();
    } catch (e) {
      await tx.rollback();
      throw e as Error;
    }
  }
}

export class SourceDao {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  private async store(): Promise<relationalStore.RdbStore> {
    return Db.get(this.ctx);
  }

  async list(): Promise<SourceInfo[]> {
    const store = await this.store();
    const pred = new relationalStore.RdbPredicates('SOURCE');
    pred.orderByAsc('TYPE');
    const rs = await store.query(pred, ['_id', 'TITLE', 'TYPE', 'ENABLE']);
    const out: SourceInfo[] = [];
    while (rs.goToNextRow()) {
      out.push(new SourceInfo(
        rs.getLong(rs.getColumnIndex('_id')),
        rs.getString(rs.getColumnIndex('TITLE')) ?? '',
        rs.getLong(rs.getColumnIndex('TYPE')),
        rs.getLong(rs.getColumnIndex('ENABLE')) !== 0));
    }
    rs.close();
    return out;
  }

  async insertOrReplace(source: SourceInfo): Promise<void> {
    const store = await this.store();
    const row: relationalStore.ValuesBucket = {
      'TITLE': source.title,
      'TYPE': source.type,
      'ENABLE': source.enable ? 1 : 0,
    };
    if (source.id > 0) {
      const pred = new relationalStore.RdbPredicates('SOURCE');
      pred.equalTo('_id', source.id);
      await store.update(row, pred);
      return;
    }
    const pred2 = new relationalStore.RdbPredicates('SOURCE');
    pred2.equalTo('TYPE', source.type);
    const rs = await store.query(pred2, ['_id']);
    if (rs.goToFirstRow()) {
      const id = rs.getLong(rs.getColumnIndex('_id'));
      rs.close();
      const pred3 = new relationalStore.RdbPredicates('SOURCE');
      pred3.equalTo('_id', id);
      await store.update(row, pred3);
      return;
    }
    rs.close();
    await store.insert('SOURCE', row);
  }

  async setEnable(type: number, enable: boolean): Promise<void> {
    const store = await this.store();
    const row: relationalStore.ValuesBucket = { 'ENABLE': enable ? 1 : 0 };
    const pred = new relationalStore.RdbPredicates('SOURCE');
    pred.equalTo('TYPE', type);
    await store.update(row, pred);
  }

  /** 彻底删除源（发现页左滑删除）。只删 SOURCE 行，收藏/章节/下载记录不级联。 */
  async delete(type: number): Promise<void> {
    const store = await this.store();
    const pred = new relationalStore.RdbPredicates('SOURCE');
    pred.equalTo('TYPE', type);
    await store.delete(pred);
  }
}
