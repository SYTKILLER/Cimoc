/**
 * ImageLoader（对齐 Fresco 管线的最小完备实现）：
 * fetch bytes（带源 headers）→ ImageSource → PixelMap；内存 LRU + 磁盘缓存。
 * 阅读器后处理（白边/分屏/乱序还原）在此基础上于 M4+ 扩展。
 */

import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { HttpClient, HttpHeader } from '../network/HttpClient';
import { common } from '@kit.AbilityKit';
import { taskpool } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 递归统计目录大小（字节）。@Concurrent 模块级函数，供 taskpool 在工作线程执行；
 *  同样的遍历若跑在主线程会阻塞渲染（曾致"我的"页首次进入卡顿）。
 *  用显式栈而非函数自递归：@Concurrent 函数体内不允许引用自身。 */
@Concurrent
function calcDirSize(root: string): number {
  let total = 0;
  const pending: string[] = [root];
  while (pending.length > 0) {
    const path = pending.pop();
    if (path === undefined) {
      break;
    }
    try {
      if (!fs.accessSync(path)) {
        continue;
      }
      const stat = fs.statSync(path);
      if (stat.isDirectory()) {
        const names = fs.listFileSync(path);
        for (const n of names) {
          pending.push(`${path}/${n}`);
        }
      } else {
        total += stat.size;
      }
    } catch (e) {
      // ignore
    }
  }
  return total;
}

interface CacheEntry {
  pixelMap: image.PixelMap;
  size: number;
}

export class ImageLoader {
  private static instance: ImageLoader | null = null;
  private readonly client: HttpClient;
  private readonly memCache: Map<string, CacheEntry> = new Map();
  private readonly inflight: Map<string, Promise<image.PixelMap>> = new Map();
  private memBytes = 0;
  private readonly memLimit = 96 * 1024 * 1024;
  private diskDir: string = '';

  static get(context: common.UIAbilityContext): ImageLoader {
    if (ImageLoader.instance === null) {
      ImageLoader.instance = new ImageLoader(context);
    }
    return ImageLoader.instance;
  }

  private constructor(context: common.UIAbilityContext) {
    this.client = HttpClient.get();
    this.diskDir = `${context.cacheDir}/images`;
    try {
      if (!fs.accessSync(this.diskDir)) {
        fs.mkdirSync(this.diskDir, true);
      }
    } catch (e) {
      // ignore
    }
  }

  private diskPath(key: string): string {
    let hash = 5381;
    for (let i = 0; i < key.length; i++) {
      hash = ((hash << 5) + hash + key.charCodeAt(i)) | 0;
    }
    return `${this.diskDir}/${(hash >>> 0).toString(16)}.img`;
  }

  /** 图片磁盘缓存占用（字节）。遍历派发到 taskpool 工作线程，不阻塞主线程。 */
  async cacheSize(): Promise<number> {
    const begin = Date.now();
    const bytes = await taskpool.execute(calcDirSize, this.diskDir) as number;
    hilog.info(0x0000, 'ImageLoader', 'cacheDir walk: %{public}d ms, %{public}d bytes', Date.now() - begin, bytes);
    return bytes;
  }

  /** 清理在线浏览产生的图片缓存（内存 + 磁盘），返回释放的字节数。
   *  只动 cacheDir/images，下载目录的离线章节与封面不受影响。 */
  async clearCache(): Promise<number> {
    const freed = await this.cacheSize();
    this.memCache.clear();
    this.memBytes = 0;
    try {
      if (fs.accessSync(this.diskDir)) {
        await fs.rmdir(this.diskDir);
      }
      fs.mkdirSync(this.diskDir, true);
    } catch (e) {
      // ignore
    }
    return freed;
  }

  private async memPut(key: string, pm: image.PixelMap): Promise<void> {
    try {
      const info = await pm.getImageInfo();
      const size = info.size.width * info.size.height * 4;
      if (size > 32 * 1024 * 1024) {
        return; // 超大图不进内存缓存
      }
      this.memCache.set(key, { pixelMap: pm, size: size });
      this.memBytes += size;
      while (this.memBytes > this.memLimit) {
        const first = this.memCache.keys().next();
        if (first.done === true) {
          break;
        }
        const old = this.memCache.get(first.value);
        this.memCache.delete(first.value);
        if (old !== undefined) {
          this.memBytes -= old.size;
        }
      }
    } catch (e) {
      // ignore
    }
  }

  async load(url: string, headers: HttpHeader | null = null): Promise<image.PixelMap> {
    if (url.length === 0) {
      throw new Error('empty url');
    }
    const mem = this.memCache.get(url);
    if (mem !== undefined) {
      return mem.pixelMap;
    }
    const busy = this.inflight.get(url);
    if (busy !== undefined) {
      return busy;
    }
    const task = this.doLoad(url, headers);
    this.inflight.set(url, task);
    try {
      const pm = await task;
      await this.memPut(url, pm);
      return pm;
    } finally {
      this.inflight.delete(url);
    }
  }

  private async doLoad(url: string, headers: HttpHeader | null): Promise<image.PixelMap> {
    // 0. 本地文件（离线下载）
    if (url.startsWith('/') || url.startsWith('file://')) {
      const path = url.replace('file://', '');
      try {
        if (fs.accessSync(path)) {
          const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
          const source = image.createImageSource(file.fd);
          const pm = await source.createPixelMap();
          source.release();
          fs.closeSync(file);
          return pm;
        }
      } catch (e) {
        throw new Error('local image missing');
      }
    }
    // 1. 磁盘缓存
    const dPath = this.diskPath(url);
    try {
      if (fs.accessSync(dPath)) {
        const stat = fs.statSync(dPath);
        if (stat.size > 0) {
          const file = fs.openSync(dPath, fs.OpenMode.READ_ONLY);
          const source = image.createImageSource(file.fd);
          const pm = await source.createPixelMap();
          source.release();
          fs.closeSync(file);
          return pm;
        }
      }
    } catch (e) {
      // 缓存读取失败则走网络
    }
    // 2. 网络获取
    const resp = await this.client.fetchBytes(url, headers);
    if (resp.code !== 200 || resp.bytes.byteLength === 0) {
      throw new Error(`image http ${resp.code}`);
    }
    const bytes = resp.bytes;
    // 3. 解码
    const source = image.createImageSource(bytes);
    if (source === null || source === undefined) {
      throw new Error('createImageSource failed');
    }
    let pm: image.PixelMap;
    try {
      pm = await source.createPixelMap();
    } finally {
      source.release();
    }
    // 4. 写磁盘缓存
    try {
      const file = fs.openSync(dPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, bytes);
      fs.closeSync(file);
    } catch (e) {
      // ignore
    }
    return pm;
  }
}
