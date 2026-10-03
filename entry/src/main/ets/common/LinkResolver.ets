/** 搜索框链接导入：把粘贴进搜索框的 URL 识别成可直达详情页的 Comic。
 *  两级识别——有 WebDetailRules 规则的源只认精确命中（歧义源再拉 HTML 验证，
 *  与源站浏览器 validateThenOpen 同语义）；无规则源按"域名与 baseUrl 一致"兜底，
 *  保证本应用分享出去的链接（baseUrl + cid）必能回导。
 *  识别结果只带 source+cid，详情数据由 DetailPage 自行拉取，除验证外不提前请求网络。 */

import { common } from '@kit.AbilityKit';
import { Comic } from '../model/Model';
import { SourceManager } from '../source/SourceManager';
import { GenericHtmlParser, SourceConfig } from '../source/SourceConfig';
import { SourceDao } from '../data/Daos';
import { HttpClient } from '../network/HttpClient';
import { HtmlNode } from '../html/HtmlNode';
import { matchWebDetail, detailNeedsValidate, hasWebDetailRule, hostOf, pathOf } from './WebDetailRules';

/** 取文本里第一段 http(s) 链接；兼容本应用分享的 `[标题][链接]`、纯链接与聊天软件粘贴的标点尾巴。 */
export function extractUrl(text: string): string {
  const re = new RegExp('https?://[^\\s\\]]+');
  const m = re.exec(text);
  if (m === null) {
    return '';
  }
  // 粘贴文本常带"链接后跟标点/引号"：截掉 URL 尾部标点（.] 类已在字符类里排除）
  return m[0].replace(/[.,;:!?)'"，。；！？、）】》…]+$/, '');
}

/** 歧义源（URL 规则命中但与分类页同构，如漫本 /mh-{slug}/）拉 HTML 验证确是详情页。 */
async function validateDetail(cfg: SourceConfig, cid: string): Promise<boolean> {
  if (cfg.parseInfoTitle.length === 0) {
    return true;
  }
  try {
    const p = SourceManager.get().getParser(cfg.type);
    const headers = p instanceof GenericHtmlParser ? p.getHeader() : null;
    const html = await HttpClient.get().fetchText(cfg.baseUrl + cid, headers);
    const title = HtmlNode.parse(html).textOf(cfg.parseInfoTitle);
    return title !== null && title.length > 0;
  } catch (e) {
    return false;
  }
}

/** URL → Comic（source+cid）；不属于任何启用源返回 null。 */
export async function resolveLink(ctx: common.UIAbilityContext, url: string): Promise<Comic | null> {
  const mgr = SourceManager.get();
  for (const s of await new SourceDao(ctx).list()) {
    if (!s.enable) {
      continue;
    }
    const cfg = mgr.getConfig(s.type);
    if (cfg === null || cfg.baseUrl.length === 0) {
      continue;
    }
    if (hasWebDetailRule(cfg.key)) {
      // 有规则源：只认精确命中，规则未命中不做域名兜底（章节页等被规则排除的形态不该进详情）
      const cid = matchWebDetail(cfg.key, cfg.baseUrl, url);
      if (cid.length === 0) {
        continue;
      }
      if (detailNeedsValidate(cfg.key) && !(await validateDetail(cfg, cid))) {
        continue;
      }
      return new Comic(s.type, cid, '');
    }
    // 无规则源：域名兜底；首页与空路径（https://host、https://host/）不算详情链接
    if (hostOf(url) === hostOf(cfg.baseUrl)) {
      const path = pathOf(url);
      if (path.length > 1) {
        return new Comic(s.type, path, '');
      }
    }
  }
  return null;
}
