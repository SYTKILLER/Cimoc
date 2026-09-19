/**
 * Vendored bundle 的类型声明（打包自 htmlparser2 + css-select + domutils，MIT）。
 * 普通模块声明形式（与 '../jslib/htmljs' 相对导入匹配）。
 */

export interface DomNode {
  children: DomNode[];
  parent: DomNode | null;
  attribs: Record<string, string> | undefined;
  type: string;
  name?: string;
  data?: string;
}

export interface DomDocument extends DomNode {
}

export interface SelectorEngine {
  selectAll(selector: string, node: DomNode | DomNode[] | null): DomNode[];
  selectOne(selector: string, node: DomNode | DomNode[] | null): DomNode | null;
  compile(selector: string): (node: DomNode) => boolean;
}

export interface DomUtilsModule {
  textContent(node: DomNode | DomNode[] | null): string;
  getAttributeValue(node: DomNode | null, name: string): string | undefined;
  hasAttrib(node: DomNode | null, name: string): boolean;
  findOne(selector: string, node: DomNode | DomNode[]): DomNode | null;
  findAll(selector: string, node: DomNode | DomNode[]): DomNode[];
  removeElement(node: DomNode): void;
  getInnerHTML(node: DomNode | null, options?: object): string;
  getOuterHTML(node: DomNode | DomNode[] | null, options?: object): string;
}

export declare function parseDocument(html: string): DomDocument;
export declare const cssSelect: SelectorEngine;
export declare const domutils: DomUtilsModule;
export declare function serialize(node: DomNode | DomNode[] | null): string;
