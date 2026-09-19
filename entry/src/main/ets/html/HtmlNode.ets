/**
 * HTML 门面：复刻 Cimoc soup/Node 的流式 API（移植源代码零改动映射）。
 * 底层为 vendored htmlparser2 + css-select（纯 JS bundle）。
 * Jsoup 扩展选择器 :eq(n) 以 :nth-of-type(n+1) 近似改写（实测源中仅该扩展被使用）。
 */

import { parseDocument, cssSelect, domutils, serialize } from '../jslib/htmljs';
import type { DomNode } from '../jslib/htmljs';
import { StringUtils } from '../common/StringUtils';

export class HtmlNode {
  private readonly node: DomNode | null;

  private constructor(node: DomNode | null) {
    this.node = node;
  }

  static parse(html: string): HtmlNode {
    return new HtmlNode(parseDocument(html));
  }

  static wrap(node: DomNode | null): HtmlNode {
    return new HtmlNode(node);
  }

  raw(): DomNode | null {
    return this.node;
  }

  /** 复刻 :eq(n) → :nth-of-type(n+1)。 */
  private static fixSelector(selector: string): string {
    return selector.replace(/:eq\((\d+)\)/g, (_m: string, n: string) => `:nth-of-type(${Number(n) + 1})`);
  }

  list(selector: string): HtmlNode[] {
    if (this.node === null) {
      return [];
    }
    try {
      const nodes: DomNode[] = cssSelect.selectAll(HtmlNode.fixSelector(selector), this.node);
      const out: HtmlNode[] = [];
      for (const n of nodes) {
        out.push(HtmlNode.wrap(n));
      }
      return out;
    } catch (e) {
      return [];
    }
  }

  /** selectFirst 等价：返回文档序第一个匹配。 */
  getChild(selector: string): HtmlNode | null {
    if (this.node === null) {
      return null;
    }
    try {
      const n: DomNode | null = cssSelect.selectOne(HtmlNode.fixSelector(selector), this.node);
      return n === null ? null : HtmlNode.wrap(n);
    } catch (e) {
      return null;
    }
  }

  getLastChild(selector: string): HtmlNode | null {
    const list = this.list(selector);
    return list.length === 0 ? null : list[list.length - 1];
  }

  text(): string {
    if (this.node === null) {
      return '';
    }
    try {
      return domutils.textContent(this.node).trim();
    } catch (e) {
      return '';
    }
  }

  textOf(selector: string): string | null {
    const child = this.getChild(selector);
    if (child === null) {
      return null;
    }
    const t = child.text();
    return t.length === 0 ? null : t;
  }

  ownText(): string {
    if (this.node === null) {
      return '';
    }
    let s = '';
    const children = this.node.children ?? [];
    for (const c of children) {
      if (c.type === 'text' && typeof c.data === 'string') {
        s += c.data;
      }
    }
    return s.trim();
  }

  attr(name: string): string | null {
    if (this.node === null || this.node.attribs === undefined) {
      return null;
    }
    const v = this.node.attribs[name];
    return v === undefined ? null : v.trim();
  }

  attrOf(selector: string, name: string): string | null {
    const child = this.getChild(selector);
    return child === null ? null : child.attr(name);
  }

  src(): string | null {
    return this.attr('src');
  }

  srcOf(selector: string): string | null {
    return this.attrOf(selector, 'src');
  }

  href(): string | null {
    return this.attr('href');
  }

  hrefOf(selector: string): string | null {
    return this.attrOf(selector, 'href');
  }

  html(): string {
    if (this.node === null) {
      return '';
    }
    try {
      return serialize((this.node as DomNode).children ?? []);
    } catch (e) {
      return '';
    }
  }

  outerHtml(): string {
    if (this.node === null) {
      return '';
    }
    try {
      return serialize(this.node);
    } catch (e) {
      return '';
    }
  }

  // ---- Cimoc Node 的组合便捷方法（同名映射） ----

  textWithSubstring(selector: string, start: number, end: number = -1): string | null {
    return StringUtils.substring(this.textOf(selector), start, end);
  }

  attrWithSubString(name: string, start: number, end: number): string | null;
  attrWithSubString(selector: string, name: string, start: number, end: number): string | null;
  attrWithSubString(a: string, b: number | string, c?: number | string, d?: number): string | null {
    if (typeof b === 'number') {
      return StringUtils.substring(this.attr(a), b as number, typeof c === 'number' ? c : -1);
    }
    return StringUtils.substring(this.attrOf(a, b as string), c as number, d === undefined ? -1 : d);
  }

  attrWithSplit(name: string, regex: string, index: number): string | null {
    return StringUtils.split(this.attr(name), regex, index);
  }

  hrefWithSubString(start: number, end: number = -1): string | null {
    return StringUtils.substring(this.href(), start, end);
  }

  /** 复刻 Node.splitHref：取 path 按非字母段拆分的第 index 段。 */
  static splitHref(str: string | null, index: number): string | null {
    if (str === null) {
      return null;
    }
    let s = str.replace(/^.*\..*?\//, '');
    s = s.replace(/[\/\.=\?]/g, ' ').trim();
    return StringUtils.split(s, '\\s+', index);
  }

  hrefWithSplit(index: number): string | null {
    return HtmlNode.splitHref(this.href(), index);
  }

  hrefWithSplitOf(selector: string, index: number): string | null {
    return HtmlNode.splitHref(this.hrefOf(selector), index);
  }
}
