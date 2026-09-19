/**
 * org.json 风格的 JSON 访问辅助（移植自 Cimoc 的 org.json 用法）。
 * ArkTS 严格模式下对 JSON.parse 结果的统一安全访问层。
 */

export class JsonObj {
  private readonly m: Record<string, Object | null>;

  constructor(m: Record<string, Object | null>) {
    this.m = m;
  }

  static parse(text: string): JsonObj | null {
    try {
      const o: Object = JSON.parse(text);
      if (o !== null && typeof o === 'object' && !Array.isArray(o)) {
        return new JsonObj(o as Record<string, Object | null>);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static of(o: Object | null): JsonObj | null {
    if (o === null || o === undefined) {
      return null;
    }
    if (typeof o === 'object' && !Array.isArray(o)) {
      return new JsonObj(o as Record<string, Object | null>);
    }
    return null;
  }

  has(key: string): boolean {
    return this.m[key] !== undefined && this.m[key] !== null;
  }

  optString(key: string, def: string = ''): string {
    const v = this.m[key];
    if (v === undefined || v === null) {
      return def;
    }
    if (typeof v === 'string') {
      return v as string;
    }
    return JSON.stringify(v);
  }

  optInt(key: string, def: number = 0): number {
    const v = this.m[key];
    if (typeof v === 'number') {
      return v as number;
    }
    if (typeof v === 'string') {
      const n = parseInt(v as string, 10);
      return isNaN(n) ? def : n;
    }
    return def;
  }

  optLong(key: string, def: number = 0): number {
    return this.optInt(key, def);
  }

  optBool(key: string, def: boolean = false): boolean {
    const v = this.m[key];
    if (typeof v === 'boolean') {
      return v as boolean;
    }
    if (typeof v === 'string') {
      return (v as string) === 'true' || (v as string) === '1';
    }
    if (typeof v === 'number') {
      return (v as number) !== 0;
    }
    return def;
  }

  optObj(key: string): JsonObj | null {
    return JsonObj.of(this.m[key]);
  }

  optArray(key: string): JsonArr | null {
    const v = this.m[key];
    if (Array.isArray(v)) {
      return new JsonArr(v as Array<Object | null>);
    }
    return null;
  }

  keys(): string[] {
    return Object.keys(this.m);
  }
}

export class JsonArr {
  private readonly a: Array<Object | null>;

  constructor(a: Array<Object | null>) {
    this.a = a;
  }

  static parse(text: string): JsonArr | null {
    try {
      const o: Object = JSON.parse(text);
      if (Array.isArray(o)) {
        return new JsonArr(o as Array<Object | null>);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static of(o: Object | null): JsonArr | null {
    if (Array.isArray(o)) {
      return new JsonArr(o as Array<Object | null>);
    }
    return null;
  }

  length(): number {
    return this.a.length;
  }

  optObj(index: number): JsonObj | null {
    const v = this.a[index];
    if (v !== undefined && v !== null && typeof v === 'object' && !Array.isArray(v)) {
      return JsonObj.of(v);
    }
    return null;
  }

  optString(index: number, def: string = ''): string {
    const v = this.a[index];
    if (typeof v === 'string') {
      return v as string;
    }
    return def;
  }

  raw(index: number): Object | null {
    const v = this.a[index];
    return v === undefined ? null : v;
  }
}
