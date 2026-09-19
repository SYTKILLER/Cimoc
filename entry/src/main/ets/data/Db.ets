/**
 * 关系库：cimoc.db，schema 与 Android 版（Room v16）1:1 对应。
 * 列名、索引、`##Cimoc##` 约定、合成 ID 规则全部保留。
 */

import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export const DB_NAME = 'cimoc.db';
export const DB_VERSION = 1;

const DDL: string[] = [
  `CREATE TABLE IF NOT EXISTS COMIC (
    _id INTEGER PRIMARY KEY AUTOINCREMENT,
    SOURCE INTEGER NOT NULL DEFAULT 0,
    CID TEXT NOT NULL,
    TITLE TEXT NOT NULL DEFAULT '',
    COVER TEXT NOT NULL DEFAULT '',
    HIGHLIGHT INTEGER NOT NULL DEFAULT 0,
    LOCAL INTEGER NOT NULL DEFAULT 0,
    LAST_UPDATE TEXT DEFAULT '',
    FINISH INTEGER,
    FAVORITE INTEGER,
    HISTORY INTEGER,
    DOWNLOAD INTEGER,
    LAST TEXT DEFAULT '',
    PAGE INTEGER DEFAULT 0,
    CHAPTER TEXT DEFAULT '',
    URL TEXT DEFAULT '',
    INTRO TEXT DEFAULT '',
    AUTHOR TEXT DEFAULT ''
  )`,
  `CREATE INDEX IF NOT EXISTS index_COMIC_SOURCE_CID ON COMIC(SOURCE, CID)`,
  `CREATE TABLE IF NOT EXISTS CHAPTER (
    _id INTEGER PRIMARY KEY AUTOINCREMENT,
    SOURCE_COMIC INTEGER NOT NULL,
    TITLE TEXT DEFAULT '',
    PATH TEXT DEFAULT '',
    COUNT INTEGER DEFAULT 0,
    COMPLETE INTEGER DEFAULT 0,
    DOWNLOAD INTEGER DEFAULT 0,
    SOURCE_GROUP TEXT DEFAULT ''
  )`,
  `CREATE INDEX IF NOT EXISTS index_CHAPTER_SOURCE_COMIC ON CHAPTER(SOURCE_COMIC)`,
  `CREATE TABLE IF NOT EXISTS IMAGE_URL (
    _id INTEGER PRIMARY KEY AUTOINCREMENT,
    COMIC_CHAPTER INTEGER NOT NULL,
    NUM INTEGER DEFAULT 0,
    URLS TEXT DEFAULT '',
    CHAPTER TEXT DEFAULT '',
    STATE INTEGER DEFAULT 0,
    HEIGHT INTEGER DEFAULT 0,
    WIDTH INTEGER DEFAULT 0,
    LAZY INTEGER DEFAULT 0,
    LOADING INTEGER DEFAULT 0,
    SUCCESS INTEGER DEFAULT 0,
    DOWNLOAD INTEGER DEFAULT 0
  )`,
  `CREATE TABLE IF NOT EXISTS SOURCE (
    _id INTEGER PRIMARY KEY AUTOINCREMENT,
    TITLE TEXT NOT NULL,
    TYPE INTEGER NOT NULL,
    ENABLE INTEGER DEFAULT 1
  )`,
  `CREATE UNIQUE INDEX IF NOT EXISTS index_SOURCE_TYPE ON SOURCE(TYPE)`,
  `CREATE TABLE IF NOT EXISTS TAG (
    _id INTEGER PRIMARY KEY AUTOINCREMENT,
    TITLE TEXT NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS TAG_REF (
    _id INTEGER PRIMARY KEY AUTOINCREMENT,
    TID INTEGER DEFAULT 0,
    CID INTEGER DEFAULT 0
  )`,
  `CREATE TABLE IF NOT EXISTS TASK (
    _id INTEGER PRIMARY KEY AUTOINCREMENT,
    KEY INTEGER DEFAULT 0,
    PATH TEXT NOT NULL DEFAULT '',
    TITLE TEXT NOT NULL DEFAULT '',
    PROGRESS INTEGER DEFAULT 0,
    MAX INTEGER DEFAULT 0
  )`,
];

export class Db {
  private static store: relationalStore.RdbStore | null = null;

  static async get(context: common.UIAbilityContext): Promise<relationalStore.RdbStore> {
    if (Db.store !== null) {
      return Db.store;
    }
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
    };
    const store = await relationalStore.getRdbStore(context, config);
    for (const sql of DDL) {
      await store.executeSql(sql);
    }
    await Db.purgeLegacyDebugData(store);
    Db.store = store;
    return store;
  }

  /** 一次性清理历史版本遗留的离线阅读测试数据（source=999 及孤儿行）。 */
  private static async purgeLegacyDebugData(store: relationalStore.RdbStore): Promise<void> {
    try {
      await store.executeSql('DELETE FROM IMAGE_URL WHERE COMIC_CHAPTER NOT IN (SELECT _id FROM CHAPTER)');
      await store.executeSql('DELETE FROM CHAPTER WHERE SOURCE_COMIC NOT IN (SELECT _id FROM COMIC)');
      await store.executeSql('DELETE FROM COMIC WHERE SOURCE = 999');
    } catch (e) {
      // 清理失败不影响建库
    }
  }
}

/** URLS 数组 ↔ `##Cimoc##` 分隔文本（与 Android TypeConverter 兼容）。 */
export class UrlsCodec {
  static readonly SEP = '##Cimoc##';

  static encode(urls: string[]): string {
    return urls.join(UrlsCodec.SEP);
  }

  static decode(text: string | null): string[] {
    if (text === null || text.length === 0) {
      return [];
    }
    return text.split(UrlsCodec.SEP);
  }
}
