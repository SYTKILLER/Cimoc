/**
 * 源站浏览器的详情页 URL 识别规则（代码侧，不放 source_catalog.json）：
 * 目录合并是"整源对象覆盖"（非 pinned 键会被设备上已导入目录整体替换），
 * 放目录里的新字段会被旧导入冲掉，放代码侧立即生效。
 *
 * 规则均为 2026-09-26 curl 实测各源首页/搜索页 href 形态后定稿：
 * - BAOZIMH  详情 /comic/{slug}，章节 /comic/chapter/{id}/{slot}_{n}.html → 排除 chapter 段
 * - GUAZIMH  详情 /comic.php?id={n}，章节 /chapter.php?id={n}（php 名不同天然不冲突）
 * - HAOMAN6  详情与分类页同为 /mh-{slug}/（/mh-aiqing/ 是恋爱分类页）→ 命中后须先拉 HTML
 *            验证 parseInfoTitle 再跳，验证不过放行网页继续加载
 * - MH92     详情 /manhua/{id}/，章节 /manhua/{id}/{n}.html（多段不匹配）
 * - JISUMH   详情 /manhua{id}/（无分隔符），章节 /ch{n}-{id}/ 不匹配
 */

interface WebDetailRule {
  readonly pattern: string;
  /** 命中后需先拉 HTML 验证是详情页再跳原生（URL 形态有歧义的源，如漫本分类页）。 */
  readonly validate: boolean;
}

const RULES: Map<string, WebDetailRule> = new Map();
RULES.set('BAOZIMH', { pattern: '^/comic/(?!chapter/).+', validate: false });
RULES.set('GUAZIMH', { pattern: '^/comic\\.php\\?id=\\d+$', validate: false });
RULES.set('HAOMAN6', { pattern: '^/mh-.+/$', validate: true });
RULES.set('MH92', { pattern: '^/manhua/\\d+/?$', validate: false });
RULES.set('JISUMH', { pattern: '^/manhua\\d+/?$', validate: false });

/** 去掉 scheme/host/#fragment，保留 query（与搜索结果 extractPath 的 cid 语义一致）。
 *  搜索页链接导入（LinkResolver）也用。 */
export function pathOf(url: string): string {
  const schemeEnd = url.indexOf('://');
  if (schemeEnd < 0) {
    return '';
  }
  const rest = url.substring(schemeEnd + 3);
  const slash = rest.indexOf('/');
  if (slash < 0) {
    return '';
  }
  const hash = rest.indexOf('#');
  return hash >= 0 ? rest.substring(slash, hash) : rest.substring(slash);
}

/** 取 host（小写、去端口）。搜索页链接导入（LinkResolver）也用。 */
export function hostOf(url: string): string {
  const schemeEnd = url.indexOf('://');
  if (schemeEnd < 0) {
    return '';
  }
  const rest = url.substring(schemeEnd + 3);
  const slash = rest.indexOf('/');
  const end = slash >= 0 ? slash : rest.length;
  const colon = rest.indexOf(':');
  const host = colon >= 0 && colon < end ? rest.substring(0, colon) : rest.substring(0, end);
  return host.toLowerCase();
}

/**
 * 主框架 URL 命中该源详情页规则时返回 cid（相对路径，可直接进 getComicInfo 链路），
 * 未配置规则 / 域名不符 / 未命中返回空串。
 */
export function matchWebDetail(key: string, baseUrl: string, url: string): string {
  const rule = RULES.get(key);
  if (rule === undefined || baseUrl.length === 0 || url.length === 0) {
    return '';
  }
  const host = hostOf(url);
  if (host.length === 0 || host !== hostOf(baseUrl)) {
    return '';
  }
  const path = pathOf(url);
  if (path.length === 0) {
    return '';
  }
  const re = new RegExp(rule.pattern);
  return re.test(path) ? path : '';
}

/** 该源命中规则后是否需要先验证 HTML 再跳原生详情页。 */
export function detailNeedsValidate(key: string): boolean {
  const rule = RULES.get(key);
  return rule !== undefined && rule.validate;
}

/** 该源是否配置了详情页 URL 规则（搜索页链接导入的域名兜底只对无规则源生效）。 */
export function hasWebDetailRule(key: string): boolean {
  return RULES.has(key);
}
