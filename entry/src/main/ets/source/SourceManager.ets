/**
 * SourceManager：源注册表 + Parser 实例缓存（对齐 data/SourceManager.java + SourceConfigManager.java）。
 * - 内置分析器：CopyMH(26)（MH517 已随源失效移除）
 * - 配置化源：从 source_catalog.json（rawfile 内置，可远程覆盖）加载，固定编号 200-219，
 *   其余键按 Java String.hashCode 哈希到 300-9299，保证与 CimocPlus 数据互通。
 */

import { Parser } from './Parser';
import { CopyMangaParser } from './CopyManga';
import { GenericHtmlParser, SourceConfig } from './SourceConfig';
import { SourceInfo } from '../model/Model';
import { JsonObj } from '../common/Json';
import { Prefs } from '../data/Prefs';
import { SourceDao } from '../data/Daos';
import { HttpClient, HttpHeader } from '../network/HttpClient';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

const PREF_CATALOG_JSON = 'pref_source_catalog_json';
const PREF_SWEPT_CATALOG_VERSION = 'pref_swept_catalog_version';

/** 远程图源目录（自有已验证仓库，镜像兜底大陆直连）。 */
const REMOTE_CATALOG_URLS: string[] = [
  'https://raw.githubusercontent.com/SYTKILLER/Cimoc-Source/refs/heads/main/source_catalog.json',
  'https://cdn.jsdelivr.net/gh/SYTKILLER/Cimoc-Source@main/source_catalog.json',
];

class ItemMeta {
  readonly type: number;
  readonly title: string;

  constructor(type: number, title: string) {
    this.type = type;
    this.title = title;
  }
}

/** 固定编号配置源（对齐 CimocPlus GENERIC_ITEMS，200-219）。 */
const GENERIC_ITEMS: Map<string, ItemMeta> = new Map();
GENERIC_ITEMS.set('BAOZIMH', new ItemMeta(200, '包子漫画'));
GENERIC_ITEMS.set('YIMMH', new ItemMeta(201, '忆漫画'));
GENERIC_ITEMS.set('DUMH', new ItemMeta(202, '独漫画'));
GENERIC_ITEMS.set('FEIXUEMH', new ItemMeta(203, '飞雪漫画'));
GENERIC_ITEMS.set('MANHUAWU', new ItemMeta(204, '漫画屋'));
GENERIC_ITEMS.set('YEMANMH', new ItemMeta(205, '野蛮漫画'));
GENERIC_ITEMS.set('HAOMAN8', new ItemMeta(206, '好漫8'));
GENERIC_ITEMS.set('HAOMAN6', new ItemMeta(207, '好漫6'));
GENERIC_ITEMS.set('MITUI', new ItemMeta(208, '米推漫画'));
GENERIC_ITEMS.set('MH360', new ItemMeta(209, '360漫画'));
GENERIC_ITEMS.set('BMG', new ItemMeta(210, '百漫谷'));
GENERIC_ITEMS.set('BAINIANMH', new ItemMeta(211, '百年漫画'));
GENERIC_ITEMS.set('QIMIAO', new ItemMeta(212, '奇妙漫画'));
GENERIC_ITEMS.set('PUFEIMH', new ItemMeta(213, '扑飞漫画'));
GENERIC_ITEMS.set('XINXINMH', new ItemMeta(214, '新新漫画'));
GENERIC_ITEMS.set('BODONGMH', new ItemMeta(215, '波动漫画'));
GENERIC_ITEMS.set('IQIYI', new ItemMeta(216, '爱奇艺漫画'));
GENERIC_ITEMS.set('BOLEFU', new ItemMeta(217, '博乐福'));
GENERIC_ITEMS.set('QIXIMH', new ItemMeta(218, '七夕漫画'));
GENERIC_ITEMS.set('ZERO', new ItemMeta(219, 'Zero'));

/** 固定编号键的旧名别名（同站旧域名/旧配置键，对齐 aliasOf）。 */
const ALIAS_KEYS: Map<string, string> = new Map();
ALIAS_KEYS.set('BAOZIMH', 'BaoziManHua');
ALIAS_KEYS.set('YIMMH', 'YiManHua');
ALIAS_KEYS.set('BMG', 'BaiManGu');
ALIAS_KEYS.set('PUFEIMH', 'PuFeiManHua');
ALIAS_KEYS.set('BOLEFU', 'BoLeFu');
ALIAS_KEYS.set('DUMH', 'DuManHua');
ALIAS_KEYS.set('HAOMAN6', 'HaoManSix');
ALIAS_KEYS.set('HAOMAN8', 'HaoManEight');

/** 额外键里跳过的旧别名键（对齐 skipExtraKey）。 */
const SKIP_EXTRA_KEYS: Set<string> = new Set([
  'BaoziManHua', 'CopyManHua', 'YiManHua', 'BaiManGu', 'PuFeiManHua',
  'BoLeFu', 'DuManHua', 'MH50', 'CoCoManHua', 'ManHuaCat',
]);

/** Java String.hashCode 精确复刻（额外源 type = 300 + hash % 9000，与 CimocPlus 编号一致）。 */
function javaHash(s: string): number {
  let h: number = 0;
  for (let i = 0; i < s.length; i++) {
    h = (Math.imul(31, h) + s.charCodeAt(i)) | 0;
  }
  return h;
}

function extraTypeOf(key: string): number {
  return 300 + ((javaHash(key) & 0x7fffffff) % 9000);
}

export class SourceManager {
  private static instance: SourceManager | null = null;
  private parserCache: Map<number, Parser> = new Map();
  private configs: Map<number, SourceConfig> = new Map();
  /** 内置目录钉住的源键：外部导入永不覆盖（内置源修复必须始终生效）。 */
  private pinnedKeys: Set<string> = new Set();
  /** 当前生效目录的 version 字段（日期式），用于门控一次性停用清扫。 */
  private currentVersion: string = '';

  private constructor() {
  }

  static get(): SourceManager {
    if (SourceManager.instance === null) {
      SourceManager.instance = new SourceManager();
    }
    return SourceManager.instance;
  }

  /**
   * 启动加载：内置目录为底座（含钉住的源修复），已导入目录作为覆盖层合并。
   * 绝不允许已导入目录整体替换内置——远程旧配置会冲掉内置修复（包子漫画简中站+多分页）。
   */
  async init(context: common.UIAbilityContext): Promise<void> {
    const bundled = await SourceManager.readRawfile(context);
    const saved = await Prefs.getString(context, PREF_CATALOG_JSON, '');
    this.mergeCatalogs(bundled, saved);
  }

  /** 目录 JSON 顶层 pinned 数组：外部导入永不覆盖的源键（内置修复保护名单）。 */
  private static catalogPinnedKeys(json: string): Set<string> {
    const out: Set<string> = new Set();
    const root = JsonObj.parse(json);
    if (root === null) {
      return out;
    }
    const arr = root.optArray('pinned');
    if (arr === null) {
      return out;
    }
    for (let i = 0; i < arr.length(); i++) {
      const key = arr.optString(i);
      if (key.length > 0) {
        out.add(key);
      }
    }
    return out;
  }

  /**
   * 合并目录：内置为底座，已导入目录覆盖同名源（钉住键除外），导入独有键新增。
   * 两次解析各自确定性分配 type，同名键在两侧得到相同 type，直接按槽位替换。
   */
  private mergeCatalogs(bundledJson: string, savedJson: string): boolean {
    if (bundledJson.length === 0 || !this.parseCatalog(bundledJson)) {
      return false;
    }
    this.pinnedKeys = SourceManager.catalogPinnedKeys(bundledJson);
    if (savedJson.length === 0) {
      return true;
    }
    const savedRoot = JsonObj.parse(savedJson);
    if (savedRoot === null) {
      return true;
    }
    const merged = new Map<number, SourceConfig>(this.configs);
    const usedKeys: Set<string> = new Set();
    GENERIC_ITEMS.forEach((meta: ItemMeta, key: string) => {
      if (this.pinnedKeys.has(key)) {
        return;
      }
      const item = savedRoot.optObj(key);
      if (item !== null) {
        const cfg = new SourceConfig(key, meta.type, meta.title, item);
        if (cfg.isComplete()) {
          merged.set(meta.type, cfg);
          usedKeys.add(key);
          return;
        }
      }
      const aliasKey = ALIAS_KEYS.get(key);
      const alias = aliasKey !== undefined ? savedRoot.optObj(aliasKey) : null;
      if (alias !== null) {
        const fallback = new SourceConfig(key, meta.type, meta.title, alias);
        if (fallback.isComplete()) {
          merged.set(meta.type, fallback);
          usedKeys.add(key);
        }
      }
    });
    for (const key of savedRoot.keys()) {
      if (usedKeys.has(key) || SKIP_EXTRA_KEYS.has(key) || this.pinnedKeys.has(key)) {
        continue;
      }
      const item = savedRoot.optObj(key);
      if (item === null) {
        continue;
      }
      let type = extraTypeOf(key);
      // 与内置目录哈希冲突时让位（内置是底座）；同名键则原位替换
      while (merged.has(type) && merged.get(type) !== undefined && merged.get(type)!.key !== key) {
        type++;
      }
      const cfg = new SourceConfig(key, type, key, item);
      if (cfg.isComplete()) {
        merged.set(type, cfg);
      }
    }
    this.configs = merged;
    this.parserCache.clear();
    return true;
  }

  private static async readRawfile(context: common.UIAbilityContext): Promise<string> {
    try {
      const bytes = await context.resourceManager.getRawFileContent('source_catalog.json');
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(bytes);
    } catch (e) {
      return '';
    }
  }

  /**
   * 解析目录 JSON（对齐 SourceConfigManager.parse）：
   * 固定编号键（含别名兜底）→ 附加键（hash 编号）。
   */
  parseCatalog(json: string): boolean {
    const root = JsonObj.parse(json);
    if (root === null) {
      return false;
    }
    this.currentVersion = root.optString('version');
    const next: Map<number, SourceConfig> = new Map();
    const usedKeys: Set<string> = new Set();
    GENERIC_ITEMS.forEach((meta: ItemMeta, key: string) => {
      let cfg: SourceConfig | null = null;
      const item = root.optObj(key);
      if (item !== null) {
        cfg = new SourceConfig(key, meta.type, meta.title, item);
      }
      if (cfg === null || !cfg.isComplete()) {
        const aliasKey = ALIAS_KEYS.get(key);
        const alias = aliasKey !== undefined ? root.optObj(aliasKey) : null;
        if (alias !== null) {
          const fallback = new SourceConfig(key, meta.type, meta.title, alias);
          if (fallback.isComplete()) {
            cfg = fallback;
          }
        }
      }
      if (cfg !== null && cfg.isComplete()) {
        next.set(meta.type, cfg);
        usedKeys.add(key);
      }
    });
    for (const key of root.keys()) {
      if (usedKeys.has(key) || SKIP_EXTRA_KEYS.has(key)) {
        continue;
      }
      const item = root.optObj(key);
      if (item === null) {
        continue;
      }
      let type = extraTypeOf(key);
      while (next.has(type)) {
        type++;
      }
      const cfg = new SourceConfig(key, type, key, item);
      if (cfg.isComplete()) {
        next.set(type, cfg);
      }
    }
    if (next.size === 0) {
      return false;
    }
    this.configs = next;
    this.parserCache.clear();
    return true;
  }

  /** 目录 JSON 是否像源配置（至少一个带 baseUrl 的对象，对齐 isSourceBaseUrlJson）。 */
  isSourceBaseUrlJson(json: string): boolean {
    const root = JsonObj.parse(json);
    if (root === null) {
      return false;
    }
    for (const key of root.keys()) {
      const item = root.optObj(key);
      if (item !== null && item.optString('baseUrl').startsWith('http')) {
        return true;
      }
    }
    return false;
  }

  /** 当前生效目录的版本（日期式字符串）。 */
  catalogVersion(): string {
    return this.currentVersion;
  }

  /**
   * 目录版本门控的一次性清扫：目录更新后，不在「目录 ∪ 内置解析器(26)」的已启用源自动停用。
   * 只停用不删除——删除永远是用户在发现页左滑主动执行。
   * 版本只前进（新于已清扫版本才执行），避免导入旧目录（如归档）后反向触发。
   */
  async sweepStaleSources(context: common.UIAbilityContext, version: string): Promise<void> {
    if (version.length === 0) {
      return;
    }
    const swept = await Prefs.getString(context, PREF_SWEPT_CATALOG_VERSION, '');
    if (version <= swept) {
      return;
    }
    const protectedTypes: Set<number> = new Set();
    protectedTypes.add(26);
    this.configs.forEach((cfg: SourceConfig, type: number) => {
      protectedTypes.add(type);
    });
    const dao = new SourceDao(context);
    for (const s of await dao.list()) {
      if (s.enable && !protectedTypes.has(s.type)) {
        await dao.setEnable(s.type, false);
      }
    }
    await Prefs.putString(context, PREF_SWEPT_CATALOG_VERSION, version);
  }

  /**
   * 导入目录 JSON：校验 → 与内置合并（钉住键保留内置修复）→ 落 prefs → 入库全部源 → 版本清扫 → 清缓存。
   * 返回是否成功。
   */
  async importJson(context: common.UIAbilityContext, json: string): Promise<boolean> {
    const bundled = await SourceManager.readRawfile(context);
    if (!this.isSourceBaseUrlJson(json) || !this.mergeCatalogs(bundled, json)) {
      return false;
    }
    await Prefs.putString(context, PREF_CATALOG_JSON, json);
    await this.applyToDatabase(context);
    const importedRoot = JsonObj.parse(json);
    const v = importedRoot !== null ? importedRoot.optString('version') : '';
    await this.sweepStaleSources(context, v.length > 0 ? v : this.currentVersion);
    return true;
  }

  /** 目录内全部配置源 upsert 入库（新增插入，已有同步标题并启用）。 */
  async applyToDatabase(context: common.UIAbilityContext): Promise<void> {
    const dao = new SourceDao(context);
    for (const info of this.catalogSourceInfos()) {
      await dao.insertOrReplace(info);
    }
  }

  /** 目录源列表（按 type 升序）。 */
  catalogSourceInfos(): SourceInfo[] {
    const out: SourceInfo[] = [];
    const types = Array.from(this.configs.keys()).sort((a: number, b: number) => a - b);
    for (const t of types) {
      const cfg = this.configs.get(t);
      if (cfg !== undefined) {
        out.push(new SourceInfo(0, cfg.title, cfg.type, true));
      }
    }
    return out;
  }

  /** 远程更新：依次尝试发布仓库地址，成功导入返回 true。 */
  async refreshRemote(context: common.UIAbilityContext): Promise<boolean> {
    const client = HttpClient.get();
    const headers = new HttpHeader();
    headers.set('Accept', 'application/json,text/plain,*/*');
    for (const url of REMOTE_CATALOG_URLS) {
      try {
        const text = await client.fetchText(url, headers);
        if (text.trim().startsWith('{') && await this.importJson(context, text)) {
          return true;
        }
      } catch (e) {
        // 换下一个地址
      }
    }
    return false;
  }

  /** 内置源默认定义（首启种子数据）：仅包子漫画默认启用；拷贝漫画停用种子保证发现页可见可开。 */
  defaultSources(): SourceInfo[] {
    return [
      new SourceInfo(0, '拷贝漫画', 26, false),
      new SourceInfo(0, '包子漫画', 200, true),
    ];
  }

  getParser(type: number): Parser | null {
    const cached = this.parserCache.get(type);
    if (cached !== undefined) {
      return cached;
    }
    let parser: Parser | null = null;
    if (type === 26) {
      parser = new CopyMangaParser();
    } else {
      const config = this.configs.get(type);
      if (config !== undefined) {
        parser = new GenericHtmlParser(config);
      }
    }
    if (parser !== null) {
      this.parserCache.set(type, parser);
    }
    return parser;
  }

  clearParserCache(): void {
    this.parserCache.clear();
  }
}
