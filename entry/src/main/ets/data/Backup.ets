/** 用户数据备份：收藏列表 + 阅读历史的导出/导入。
 *  文件位置完全由用户经系统文件选择器（DocumentViewPicker）选定，Picker 授权自带临时
 *  读写许可，应用侧无需申请任何存储权限。 */

import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { Comic } from '../model/Model';
import { ComicDao } from './Daos';
import { JsonObj } from '../common/Json';

/** 备份文件里的单条漫画（白名单字段：不含 _id/download/local 及运行时字段）。 */
interface BackupComic {
  source: number;
  cid: string;
  title: string;
  cover: string;
  update: string;
  intro: string;
  author: string;
  finish: boolean;
  favorite: number;
  history: number;
  last: string;
  page: number;
  chapter: string;
  highlight: boolean;
}

/** 备份文件根结构（不兼容原版 Android Cimoc 格式，仅 Cimoc HarmonyOS 互通）。 */
interface BackupFile {
  app: string;
  type: string;
  version: number;
  exportTime: number;
  comics: BackupComic[];
}

/** 导入预览：ok=false 且 message='' 表示用户在文件选择器里取消，页面静默返回。 */
export interface ImportPreview {
  ok: boolean;
  message: string;
  total: number;     // 文件内有效记录数
  added: number;     // 本地不存在（可新增）
  conflicts: number; // 本地已存在（需用户选合并策略）
  comics: Comic[];   // 解析出的待导入记录（含冲突条目，写库由 applyImport 负责）
}

export class Backup {
  /**
   * 导出收藏 + 阅读历史为 JSON：拉起系统"另存为"由用户选位置与文件名。
   * 返回实际保存的文件名；用户取消返回空串；无可导出数据/写失败抛错。
   */
  static async exportData(ctx: common.UIAbilityContext): Promise<string> {
    const dao = new ComicDao(ctx);
    // 收藏/历史同存一张 COMIC 表：两个列表按 (source,cid) 取并集（同行数据字段一致）
    const favs = await dao.listFavorite();
    const hist = await dao.listHistory();
    const merged = new Map<string, Comic>();
    for (const c of hist) {
      merged.set(`${c.source}:${c.cid}`, c);
    }
    for (const c of favs) {
      merged.set(`${c.source}:${c.cid}`, c);
    }
    if (merged.size === 0) {
      throw new Error('还没有可导出的收藏或阅读历史');
    }
    const comics: BackupComic[] = [];
    merged.forEach((c: Comic) => {
      const item: BackupComic = {
        source: c.source,
        cid: c.cid,
        title: c.title,
        cover: c.cover,
        update: c.update,
        intro: c.intro,
        author: c.author,
        finish: c.finish,
        favorite: c.favorite,
        history: c.history,
        last: c.last,
        page: c.page,
        chapter: c.chapter,
        highlight: c.highlight
      };
      comics.push(item);
    });
    const now = new Date();
    const pad2 = (n: number): string => (n < 10 ? '0' : '') + n;
    const ymd = `${now.getFullYear()}${pad2(now.getMonth() + 1)}${pad2(now.getDate())}`;
    const file: BackupFile = {
      app: 'cimoc',
      type: 'backup',
      version: 1,
      exportTime: Date.now(),
      comics: comics
    };
    const docPicker = new picker.DocumentViewPicker(ctx);
    const opts = new picker.DocumentSaveOptions();
    opts.newFileNames = [`cimoc_backup_${ymd}.json`];
    opts.fileSuffixChoices = ['Cimoc备份|.json'];
    const uris = await docPicker.save(opts);
    if (uris === undefined || uris.length === 0) {
      return '';
    }
    // save() 返回的 URI 已预创建空文件（用户自选位置），带 TRUNC 兜底清空后写入
    const f = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    fs.writeSync(f.fd, JSON.stringify(file));
    fs.closeSync(f);
    return uris[0].substring(uris[0].lastIndexOf('/') + 1);
  }

  /** 选择并解析备份文件（不写库）。ok=false 且 message='' 表示用户取消。 */
  static async importPreview(ctx: common.UIAbilityContext): Promise<ImportPreview> {
    const docPicker = new picker.DocumentViewPicker(ctx);
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 1;
    opts.fileSuffixFilters = ['.json'];
    const uris = await docPicker.select(opts);
    if (uris === undefined || uris.length === 0) {
      return Backup.failPreview('');
    }
    try {
      const stat = fs.statSync(uris[0]);
      const f = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(f.fd, buf);
      fs.closeSync(f);
      const text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
      return await Backup.parsePreview(ctx, text);
    } catch (e) {
      return Backup.failPreview('读取备份文件失败');
    }
  }

  /** 按策略写库：'newer'=已存在条目按时间戳取较新；'fill'=只新增本地没有的。返回实际写库条数。 */
  static async applyImport(ctx: common.UIAbilityContext, comics: Comic[], policy: string): Promise<number> {
    const dao = new ComicDao(ctx);
    let applied = 0;
    for (const c of comics) {
      if (await dao.importComic(c, policy)) {
        applied++;
      }
    }
    return applied;
  }

  private static failPreview(message: string): ImportPreview {
    const empty: Comic[] = [];
    const p: ImportPreview = {
      ok: false,
      message: message,
      total: 0,
      added: 0,
      conflicts: 0,
      comics: empty
    };
    return p;
  }

  private static async parsePreview(ctx: common.UIAbilityContext, text: string): Promise<ImportPreview> {
    const root = JsonObj.parse(text);
    if (root === null || root.optString('app') !== 'cimoc' || root.optString('type') !== 'backup') {
      return Backup.failPreview('不是有效的 Cimoc 备份文件');
    }
    const arr = root.optArray('comics');
    if (arr === null) {
      return Backup.failPreview('备份文件缺少 comics 数据');
    }
    const comics: Comic[] = [];
    const seen: Set<string> = new Set();
    for (let i = 0; i < arr.length(); i++) {
      const o = arr.optObj(i);
      if (o === null) {
        continue;
      }
      const source = o.optLong('source', -1);
      const cid = o.optString('cid');
      const favorite = Math.max(0, o.optLong('favorite', 0));
      const history = Math.max(0, o.optLong('history', 0));
      if (source < 0 || cid === '' || (favorite === 0 && history === 0)) {
        continue;
      }
      const key = `${source}:${cid}`;
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      const c = new Comic(source, cid, o.optString('title', cid));
      c.cover = o.optString('cover');
      c.update = o.optString('update');
      c.intro = o.optString('intro');
      c.author = o.optString('author');
      c.finish = o.optBool('finish');
      c.favorite = favorite;
      c.history = history;
      c.last = o.optString('last');
      c.page = Math.max(0, o.optInt('page', 0));
      c.chapter = o.optString('chapter');
      c.highlight = o.optBool('highlight');
      comics.push(c);
    }
    if (comics.length === 0) {
      return Backup.failPreview('备份文件中没有可导入的收藏/历史');
    }
    // 逐条与本地比对（文件内已按 source+cid 去重），命中 id 供后续按行更新
    const dao = new ComicDao(ctx);
    let conflicts = 0;
    for (const c of comics) {
      const existing = await dao.load(c.source, c.cid);
      if (existing !== null) {
        conflicts++;
        c.id = existing.id;
      }
    }
    const p: ImportPreview = {
      ok: true,
      message: '',
      total: comics.length,
      added: comics.length - conflicts,
      conflicts: conflicts,
      comics: comics
    };
    return p;
  }
}
