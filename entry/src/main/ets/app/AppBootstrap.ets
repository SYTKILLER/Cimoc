/** 应用启动引导：种子数据初始化 + 图源目录加载。 */

import { SourceManager } from '../source/SourceManager';
import { SourceDao } from '../data/Daos';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

export class AppBootstrap {
  private static seeded = false;

  static async init(context: common.UIAbilityContext): Promise<void> {
    if (AppBootstrap.seeded) {
      return;
    }
    AppBootstrap.seeded = true;
    const dao = new SourceDao(context);
    const existing = await dao.list();
    const have: Set<number> = new Set();
    for (const s of existing) {
      have.add(s.type);
    }
    for (const def of SourceManager.get().defaultSources()) {
      if (!have.has(def.type)) {
        await dao.insertOrReplace(def);
      }
    }
    // 图源目录：prefs（远程导入过）→ 内置 rawfile，解析后全部入库
    try {
      await SourceManager.get().init(context);
      await SourceManager.get().applyToDatabase(context);
      // 目录版本变化后的一次性清扫：不在目录的旧源自动停用（用户可左滑删除）
      await SourceManager.get().sweepStaleSources(context, SourceManager.get().catalogVersion());
    } catch (e) {
      // 目录加载失败不影响内置源使用
    }
    // 删除历史测试工具遗留的图片目录（数据行由 Db 首次打开时清理）
    try {
      const dir = `${context.filesDir}/download/999`;
      if (fs.accessSync(dir)) {
        fs.rmdirSync(dir);
      }
    } catch (e) {
      // 不影响启动
    }
  }
}
