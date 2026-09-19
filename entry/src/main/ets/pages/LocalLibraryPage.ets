/** 本地页（顶级页签）：本地漫画管理，完全离线——只读数据库与下载目录文件，不发任何网络请求。
 *  与书库页零耦合：不回传数据，缓存状态以任务表/章节文件为准。 */

import { ChapterDao, ComicDao } from '../data/Daos';
import { Chapter, Comic, DetailArgs, Task } from '../model/Model';
import { DownloadManager } from '../download/DownloadManager';
import { Storage } from '../data/Storage';
import Theme from '../common/Theme';
import { common } from '@kit.AbilityKit';

@Component
export struct LocalLibraryPage {
  @Consume('nav') navStack: NavPathStack;
  @StorageLink('bottomInset') bottomInset: number = 0;
  @StorageLink('bp') bp: string = 'sm';
  @State localComics: Comic[] = [];
  @State tasks: Task[] = [];   // 仅用于"下载中"入口徽章计数
  // 阅读进度（library_dirty）与下载进度（download_dirty）变化时重载本地列表
  @StorageLink('library_dirty') @Watch('onDirty') dirty: number = 0;
  @StorageLink('download_dirty') @Watch('onDirty') downloadDirty: number = 0;
  private comicDao: ComicDao | null = null;
  private storage: Storage | null = null;

  onDirty(): void {
    this.reload();
  }

  aboutToAppear(): void {
    this.comicDao = new ComicDao(getContext(this) as common.UIAbilityContext);
    this.storage = new Storage(getContext(this) as common.UIAbilityContext);
    this.reload();
  }

  reload(): void {
    const dao = this.comicDao;
    if (dao === null) {
      return;
    }
    dao.listDownload().then(async (list: Comic[]) => {
      // 全程离线：逐本统计已完整缓存章节数（本地 DB 查询），只展示确实有缓存的
      const chapterDao = new ChapterDao(getContext(this) as common.UIAbilityContext);
      const shown: Comic[] = [];
      for (const c of list) {
        try {
          const chs = await chapterDao.list(c.id);
          let n = 0;
          for (const ch of chs) {
            if (ch.download && ch.complete) {
              n++;
            }
          }
          c.localCount = n;
        } catch (e) {
          c.localCount = 0;
        }
        if (c.localCount > 0) {
          shown.push(c);
        }
      }
      this.localComics = shown;
    }).catch(() => {
      this.localComics = [];
    });
    DownloadManager.get(getContext(this) as common.UIAbilityContext).taskDaoRef().list().then((list: Task[]) => {
      this.tasks = list;
    }).catch(() => {
      this.tasks = [];
    });
  }

  pendingCount(): number {
    let n = 0;
    for (const t of this.tasks) {
      if (t.max >= 0 && !t.isFinish()) {
        n++;
      }
    }
    return n;
  }

  /** 本地详情：章节预先查好随参数带入，详情页同步渲染。
   *  注意必须完整拷贝收藏/历史/下载标志——updateOrDelete 遇到三态全零会清掉对应列。 */
  async openLocalDetail(comic: Comic): Promise<void> {
    const c = new Comic(comic.source, comic.cid, comic.title, comic.cover, comic.update, comic.author);
    c.id = comic.id;
    c.favorite = comic.favorite;
    c.history = comic.history;
    c.download = comic.download;
    c.last = comic.last;
    c.page = comic.page;
    c.chapter = comic.chapter;
    c.intro = comic.intro;
    c.finish = comic.finish;
    c.highlight = comic.highlight;
    let chapters: Chapter[] = [];
    try {
      const chapterDao = new ChapterDao(getContext(this) as common.UIAbilityContext);
      const all = await chapterDao.list(comic.id);
      for (const ch of all) {
        if (ch.download && ch.complete) {
          chapters.push(ch);
        }
      }
    } catch (e) {
      chapters = [];
    }
    this.navStack.pushPathByName('localcomic', new DetailArgs(c, true, chapters));
  }

  @Builder
  emptyState() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.download'))
        .fontSize(52)
        .fontColor([$r('sys.color.font_fourth')])
      Text(this.pendingCount() > 0 ? '正在下载，完成后将出现在这里' : '暂无本地缓存\n在详情页右上角可缓存章节')
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .width('100%')
  }

  // "本地"列表行：无封面布局——书名 + 已缓存章数 + 上次阅读进度
  @Builder
  localRow(c: Comic) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(c.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(c.history > 0 && c.chapter.length > 0
          ? `已缓存 ${c.localCount} 章 · 读到 ${c.chapter}${c.page > 0 ? ` P${c.page}` : ''}`
          : `已缓存 ${c.localCount} 章`)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_forward'))
        .fontSize(16)
        .fontColor([$r('sys.color.font_tertiary')])
    }
    .width('100%')
    .padding(Theme.PAD_CARD)
    .borderRadius(Theme.RADIUS_ITEM)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .onClick(() => {
      this.openLocalDetail(c);
    })
  }

  // "下载中"快捷入口卡片
  @Builder
  downloadingEntry() {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.download_fill'))
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(36)
      .height(36)
      .borderRadius(10)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Theme.ACCENT)

      Text('下载中')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)

      if (this.pendingCount() > 0) {
        Text(`${this.pendingCount()}`)
          .fontSize(11)
          .fontColor(Color.White)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(Theme.RADIUS_PILL)
          .backgroundColor(Theme.DANGER)
      }

      SymbolGlyph($r('sys.symbol.chevron_forward'))
        .fontSize(16)
        .fontColor([$r('sys.color.font_tertiary')])
    }
    .width('100%')
    .padding(14)
    .borderRadius(Theme.RADIUS_CARD)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .shadow(Theme.CARD_SHADOW)
    .onClick(() => {
      this.navStack.pushPathByName('downloading', null);
    })
  }

  build() {
    Column() {
      // 规范标题栏：高 56vp，标题 28fp/Medium 居左（与书库页同级）
      Row() {
        Text('本地')
          .fontSize(28)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
      }
      .padding({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp) })
      .height(56)
      .width('100%')

      Column() {
        this.downloadingEntry()
      }
      .padding({
        left: Theme.pagePad(this.bp),
        right: Theme.pagePad(this.bp),
        top: 8
      })
      .width('100%')

      if (this.localComics.length === 0) {
        this.emptyState()
      } else {
        List({ space: Theme.GAP_LIST }) {
          ForEach(this.localComics, (c: Comic) => {
            ListItem() {
              this.localRow(c)
            }
            .stateStyles({
              pressed: { .opacity(Theme.PRESS_OPACITY) },
              normal: { .opacity(1) }
            })
          }, (c: Comic) => `local_${c.id}_${c.localCount}_${c.page}_${c.chapter}`)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp), top: 14 })
        .contentEndOffset(Theme.floatTabBarAvoid(this.bottomInset))
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .height('100%')
    .width('100%')
  }
}
