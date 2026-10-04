/**
 * 「继续阅读」卡片数据构建（供 EntryFormAbility 在卡片进程调用，与主应用共享沙箱数据）：
 * COMIC 表最近一条阅读历史（ComicDao.listHistory()[0]）→ 封面两级来源
 * （离线封面文件 → 网络下载带图源防盗链头）→ 保比缩放打包 JPEG → tempDir fd
 * → formImages 绑定数据。封面获取整体限时，规避卡片进程约 5 秒的后台存活限制。
 */

import { formBindingData, formProvider } from '@kit.FormKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ComicDao } from '../data/Daos';
import { Prefs } from '../data/Prefs';
import { Storage } from '../data/Storage';
import { SourceManager } from '../source/SourceManager';
import { HttpClient, HttpHeader } from '../network/HttpClient';
import { Comic } from '../model/Model';

const DOMAIN = 0x0000;
const TAG = 'CimocCard';
/** 封面获取总限时：FormExtensionAbility 回调后台仅存活约 5 秒，留出打包与 updateForm 余量 */
const COVER_TIMEOUT_MS = 4500;
/** 卡片封面缩略图长边：2×2 卡实际显示约 60~80vp，480px 足够清晰且打包体积小 */
const COVER_MAX_EDGE = 480;
/** 自存 formId 的偏好 key：应用进程 reloadAllForms 失败时兜底直刷用 */
const PREF_FORM_IDS = 'pref_widget_form_ids';
const TEMP_IMG_NAME = 'card_cover.jpg';

/** 绑定数据载体；封面 fd 需在 updateForm 完成后由调用方关闭。 */
export class CardPayload {
  data: formBindingData.FormBindingData;
  fd: number = -1;

  constructor(data: formBindingData.FormBindingData) {
    this.data = data;
  }

  close(): void {
    if (this.fd >= 0) {
      try {
        fs.closeSync(this.fd);
      } catch (e) {
        // ignore
      }
      this.fd = -1;
    }
  }
}

/** 卡片绑定数据（键名与 WidgetCard.ets 的 @LocalStorageProp 一一对应）。 */
class CardBinding {
  hasHistory: boolean = false;
  comicId: number = 0;
  chapter: string = '打开应用，开始阅读';
  loaded: boolean = false;
  imgName: string = '';
  formImages: Record<string, number> = {};
}

export class CardDataProvider {
  /** 占位数据：onAddForm 必须同步返回，真实数据随后 updateForm 补全。 */
  static placeholder(): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData(new CardBinding());
  }

  /** 读取最近阅读 + 构建封面，组装完整卡片数据。 */
  static async build(ctx: common.UIAbilityContext): Promise<CardPayload> {
    const payload = new CardPayload(CardDataProvider.placeholder());
    let comic: Comic | null = null;
    try {
      const list = await new ComicDao(ctx).listHistory();
      comic = list.length > 0 ? list[0] : null;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'listHistory failed: %{public}s', String(e));
    }
    if (comic === null) {
      return payload;
    }
    const b = new CardBinding();
    b.hasHistory = true;
    b.comicId = comic.id;
    if (comic.chapter.length > 0) {
      b.chapter = comic.chapter;
    }
    const fd = await CardDataProvider.coverFd(ctx, comic);
    if (fd >= 0) {
      b.loaded = true;
      // imgName 每次刷新必须唯一，重复的 imgName 卡片图片不会更新
      b.imgName = `cover${Date.now()}`;
      b.formImages[b.imgName] = fd;
      payload.fd = fd;
    }
    payload.data = formBindingData.createFormBindingData(b);
    return payload;
  }

  /** 封面 → tempDir 文件 fd；任何一步失败返回 -1（卡片显示占位图）。 */
  private static async coverFd(ctx: common.UIAbilityContext, comic: Comic): Promise<number> {
    try {
      const pm = await CardDataProvider.loadThumb(ctx, comic);
      if (pm === null) {
        return -1;
      }
      const packer = image.createImagePacker();
      const buf = await packer.packToData(pm, { format: 'image/jpeg', quality: 80 });
      packer.release();
      // 写 tempDir（固定文件名 TRUNC 覆盖，不堆积临时文件），以打开的 fd 交给卡片框架
      const path = `${ctx.tempDir}/${TEMP_IMG_NAME}`;
      const f = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, buf);
      return f.fd; // 不在此 close：updateForm 完成后由 payload.close() 关闭
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'coverFd failed: %{public}s', String(e));
      return -1;
    }
  }

  /** 封面缩略图：离线封面优先（已下载漫画必有），否则网络获取（带图源防盗链头，整体限时）。 */
  private static async loadThumb(ctx: common.UIAbilityContext, comic: Comic): Promise<image.PixelMap | null> {
    const local = new Storage(ctx).localCoverPath(comic.source, comic.cid);
    if (local.length > 0) {
      const pm = await CardDataProvider.decode(local, null);
      if (pm !== null) {
        return pm;
      }
    }
    if (comic.cover.length === 0) {
      return null;
    }
    let headers: HttpHeader | null = null;
    try {
      // 仅读 rawfile + prefs 合并源目录，纯读内存操作，卡片进程安全
      await SourceManager.get().init(ctx);
      const parser = SourceManager.get().getParser(comic.source);
      headers = parser !== null ? parser.imageHeaders() : null;
    } catch (e) {
      // 目录加载失败则裸取（部分 CDN 会 403，接受降级为占位图）
    }
    const task = HttpClient.get().fetchBytes(comic.cover, headers).then((resp) => {
      if (resp.code !== 200 || resp.bytes.byteLength === 0) {
        throw new Error(`cover http ${resp.code}`);
      }
      return CardDataProvider.decode('', resp.bytes);
    });
    const timer = new Promise<null>((resolve: (v: null) => void) => {
      setTimeout(() => resolve(null), COVER_TIMEOUT_MS);
    });
    return Promise.race([task.catch((): null => null), timer]);
  }

  /** 解码 + 保比缩放到长边 COVER_MAX_EDGE；path 与 bytes 二选一。 */
  private static async decode(path: string, bytes: ArrayBuffer | null): Promise<image.PixelMap | null> {
    let source: image.ImageSource | undefined = undefined;
    let file: fs.File | null = null;
    try {
      if (bytes !== null) {
        source = image.createImageSource(bytes);
      } else if (path.length > 0) {
        file = fs.openSync(path, fs.OpenMode.READ_ONLY);
        source = image.createImageSource(file.fd);
      }
      if (source === undefined) {
        return null;
      }
      const info = await source.getImageInfo();
      let w = info.size.width;
      let h = info.size.height;
      let opts: image.DecodingOptions | undefined = undefined;
      if (w > 0 && h > 0 && Math.max(w, h) > COVER_MAX_EDGE) {
        if (w >= h) {
          h = Math.round(h * COVER_MAX_EDGE / w);
          w = COVER_MAX_EDGE;
        } else {
          w = Math.round(w * COVER_MAX_EDGE / h);
          h = COVER_MAX_EDGE;
        }
        opts = { desiredSize: { width: w, height: h } };
      }
      return opts === undefined ? await source.createPixelMap() : await source.createPixelMap(opts);
    } catch (e) {
      return null;
    } finally {
      try {
        if (source !== undefined) {
          source.release();
        }
      } catch (e) {
        // ignore
      }
      try {
        if (file !== null) {
          fs.closeSync(file);
        }
      } catch (e) {
        // ignore
      }
    }
  }

  // ---- formId 登记（reloadAllForms 兜底直刷用；卡片进程写、应用进程读） ----

  static async addFormId(ctx: common.UIAbilityContext, formId: string): Promise<void> {
    const ids = await Prefs.getStringArray(ctx, PREF_FORM_IDS);
    if (ids.indexOf(formId) === -1) {
      ids.push(formId);
      await Prefs.putStringArray(ctx, PREF_FORM_IDS, ids);
    }
  }

  static async removeFormId(ctx: common.UIAbilityContext, formId: string): Promise<void> {
    const ids = await Prefs.getStringArray(ctx, PREF_FORM_IDS);
    const i = ids.indexOf(formId);
    if (i >= 0) {
      ids.splice(i, 1);
      await Prefs.putStringArray(ctx, PREF_FORM_IDS, ids);
    }
  }

  /** 兜底：reloadAllForms 不可用时，应用进程按自存 formId 直接 updateForm（不依赖任何刷新配置）。 */
  static async flushAll(ctx: common.UIAbilityContext): Promise<void> {
    const ids = await Prefs.getStringArray(ctx, PREF_FORM_IDS);
    for (const id of ids) {
      try {
        const payload = await CardDataProvider.build(ctx);
        await formProvider.updateForm(id, payload.data);
        payload.close();
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'flushAll %{public}s failed: %{public}s', id, String(e));
      }
    }
  }
}
