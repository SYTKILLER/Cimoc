/** 应用内文件存储（移植 Storage/Download 的目录约定，根目录 = 应用沙箱 filesDir）。 */

import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

export class Storage {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  root(): string {
    return this.ctx.filesDir;
  }

  downloadDir(): string {
    return `${this.root()}/download`;
  }

  pictureDir(): string {
    return `${this.root()}/picture`;
  }

  imageCacheDir(): string {
    return `${this.ctx.cacheDir}/images`;
  }

  /** 确保目录存在并返回路径。 */
  ensureDir(path: string): string {
    if (!fs.accessSync(path)) {
      fs.mkdirSync(path, true);
    }
    return path;
  }

  ensureDownloadTree(source: number, cid: string, chapterDir: string): string {
    const root = this.ensureDir(this.downloadDir());
    const sDir = this.ensureDir(`${root}/${source}`);
    const cDir = this.ensureDir(`${sDir}/${Storage.cleanCid(cid)}`);
    return this.ensureDir(`${cDir}/${Storage.cleanCid(chapterDir)}`);
  }

  /** 漫画下载根目录：download/<source>/<cid清洗后>/（封面等漫画级文件放这里，不进章节目录）。 */
  comicDir(source: number, cid: string): string {
    return this.ensureDir(`${this.downloadDir()}/${source}/${Storage.cleanCid(cid)}`);
  }

  /** 漫画详情快照文件（详情字段 + 章节列表），缓存首次入队时写入。 */
  comicCdifPath(source: number, cid: string): string {
    return `${this.comicDir(source, cid)}/comic.cdif`;
  }

  /** 章节下载目录路径（不创建）。 */
  chapterDir(source: number, cid: string, chapterPath: string): string {
    return `${this.downloadDir()}/${source}/${Storage.cleanCid(cid)}/${Storage.cleanCid(chapterPath)}`;
  }

  /** 删除单个文件（不存在则忽略）。 */
  removeFile(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      // ignore
    }
  }

  /** 本地封面文件路径；不存在返回空串（调用方据此严格离线展示，不回退网络）。 */
  localCoverPath(source: number, cid: string): string {
    const path = `${this.downloadDir()}/${source}/${Storage.cleanCid(cid)}/cover`;
    try {
      return fs.accessSync(path) ? path : '';
    } catch (e) {
      return '';
    }
  }

  static cleanCid(s: string): string {
    return s.replace(/[:\/\\?<>\"|\.]/g, '-');
  }

  /** 图片文件名：%03d.后缀（对齐 buildFileName）。 */
  imageFileName(page: number, url: string): string {
    let ext = 'jpg';
    const dot = url.lastIndexOf('.');
    if (dot > 0) {
      const e = url.substring(dot + 1).toLowerCase();
      if (e.length <= 5 && /^[a-z0-9]+$/.test(e)) {
        ext = e;
      }
    }
    const num = page <= 0 ? 1 : page;
    const pad = num < 10 ? `00${num}` : (num < 100 ? `0${num}` : `${num}`);
    return `${pad}.${ext}`;
  }

  saveImageBytes(dir: string, fileName: string, bytes: ArrayBuffer): string {
    this.ensureDir(dir);
    const path = `${dir}/${fileName}`;
    const f = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(f.fd, bytes);
    fs.closeSync(f);
    return path;
  }

  listImages(dir: string): string[] {
    try {
      const names = fs.listFileSync(dir);
      const out: string[] = [];
      for (const n of names) {
        if (!n.endsWith('.cdif') && !n.startsWith('.')) {
          out.push(n);
        }
      }
      out.sort();
      return out;
    } catch (e) {
      return [];
    }
  }

  readFileBytes(path: string): ArrayBuffer | null {
    try {
      const stat = fs.statSync(path);
      const f = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(f.fd, buf);
      fs.closeSync(f);
      return buf;
    } catch (e) {
      return null;
    }
  }

  removeDir(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.rmdirSync(path);
      }
    } catch (e) {
      // ignore
    }
  }
}
