/** 本地阅读进度：与联网进度（COMIC.LAST/PAGE/CHAPTER）完全独立的离线阅读记录。
 *  存 Preferences（key 按 comic id 隔离），不动与 Android 版 1:1 对应的库表结构；
 *  写入只发生在 ReaderPage（localOnly），本地详情/列表页只读。 */

import { Prefs } from './Prefs';
import { JsonObj } from '../common/Json';
import { common } from '@kit.AbilityKit';

export class LocalProgress {
  path: string = '';    // 最后阅读章节 path
  title: string = '';   // 最后阅读章节标题
  page: number = 0;     // 最后阅读页码（1-based，0 = 未记录页码）
  time: number = 0;     // 最后阅读时间戳

  static key(comicId: number): string {
    return `local_read_${comicId}`;
  }

  /** 永不 reject：记录缺失/损坏一律返回空进度。 */
  static async load(ctx: common.UIAbilityContext, comicId: number): Promise<LocalProgress> {
    const out = new LocalProgress();
    if (comicId <= 0) {
      return out;
    }
    try {
      const o = JsonObj.parse(await Prefs.getString(ctx, LocalProgress.key(comicId), ''));
      if (o === null) {
        return out;
      }
      out.path = o.optString('path');
      out.title = o.optString('title');
      out.page = o.optInt('page');
      out.time = o.optLong('time');
    } catch (e) {
      // 记录损坏即视为无进度
    }
    return out;
  }

  static async save(ctx: common.UIAbilityContext, comicId: number,
                    path: string, title: string, page: number): Promise<void> {
    if (comicId <= 0 || path.length === 0) {
      return;
    }
    const p = new LocalProgress();
    p.path = path;
    p.title = title;
    p.page = page;
    p.time = Date.now();
    await Prefs.putString(ctx, LocalProgress.key(comicId), JSON.stringify(p));
  }
}
