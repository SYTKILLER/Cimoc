/** 本地漫画页："本地"列表进入的轻量详情——只展示已缓存章节（按正确章节顺序），
 *  全程零网络、零加载态；横滑删除章节缓存，点击直接离线阅读。
 *  Navigation 架构：系统路由表注册，onReady 标准入口取 NavPathStack 与路由参数，不使用 router。 */

import { Chapter, Comic, DetailArgs, ReaderArgs } from '../model/Model';
import { ComicDao } from '../data/Daos';
import { DownloadManager } from '../download/DownloadManager';
import Theme from '../common/Theme';
import { common } from '@kit.AbilityKit';

/** 系统路由表入口（router_map.json → LocalComicPageBuilder）。 */
@Builder
export function LocalComicPageBuilder() {
  LocalComicPage()
}

@Component
export struct LocalComicPage {
  @StorageLink('bottomInset') bottomInset: number = 0;
  @StorageLink('bp') bp: string = 'sm';
  private pathStack: NavPathStack | null = null;
  @State comic: Comic = new Comic(0, '', '');
  // 已缓存章节，按章节正确顺序（入库顺序 = 原始顺序）排列
  @State chapters: Chapter[] = [];
  private comicDao: ComicDao | null = null;

  aboutToAppear(): void {
    this.comicDao = new ComicDao(getContext(this) as common.UIAbilityContext);
  }

  chapterIndex(ch: Chapter): number {
    for (let i = 0; i < this.chapters.length; i++) {
      if (this.chapters[i].path === ch.path) {
        return i;
      }
    }
    return 0;
  }

  async readChapter(ch: Chapter): Promise<void> {
    // 记历史（本地 DB 操作）；local=true 让阅读器离线锁定，只读本地文件
    if (this.comicDao !== null && this.comic.id > 0) {
      if (this.comic.favorite > 0) {
        this.comic.favorite = Date.now();
      }
      this.comic.history = Date.now();
      if (ch.path !== this.comic.last) {
        this.comic.last = ch.path;
        this.comic.page = 1;
      }
      await this.comicDao.updateOrDelete(this.comic);
      AppStorage.setOrCreate('library_dirty', Date.now());
    }
    if (this.pathStack !== null) {
      this.pathStack.pushPathByName('reader', new ReaderArgs(this.comic, this.chapters, this.chapterIndex(ch), true));
    }
  }

  confirmDelete(ch: Chapter): void {
    AlertDialog.show({
      title: '删除缓存',
      message: `确定删除「${ch.title}」的本地缓存吗？`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Theme.DANGER,
        action: (): void => {
          this.deleteChapter(ch);
        }
      }
    });
  }

  async deleteChapter(ch: Chapter): Promise<void> {
    await DownloadManager.get(getContext(this) as common.UIAbilityContext)
      .deleteChapterCache(this.comic.id, ch.path);
    this.chapters = this.chapters.filter((c: Chapter): boolean => c.path !== ch.path);
  }

  // 左滑露出的删除按钮
  @Builder
  deleteCell(ch: Chapter) {
    Row() {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(20)
        .fontColor([Color.White])
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .borderRadius(Theme.RADIUS_ITEM)
    .backgroundColor(Theme.DANGER)
    .margin({ left: 8 })
    .onClick(() => {
      this.confirmDelete(ch);
    })
  }

  build() {
    NavDestination() {
      Column() {
        Text(`已缓存 ${this.chapters.length} 章 · 离线可读`)
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding({ left: Theme.PAD_PAGE + 10, right: Theme.PAD_PAGE, bottom: 6 })

        if (this.chapters.length === 0) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(48)
              .fontColor([$r('sys.color.font_fourth')])
            Text('暂无已缓存章节')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .width('100%')
        } else {
          List({ space: Theme.GAP_LIST }) {
            ForEach(this.chapters, (ch: Chapter) => {
              ListItem() {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(ch.title)
                      .fontSize(14)
                      .fontColor($r('sys.color.font_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (ch.count > 0) {
                      Text(`${ch.count} 图`)
                        .fontSize(11)
                        .fontColor($r('sys.color.font_tertiary'))
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                    .fontSize(16)
                    .fontColor([Theme.SUCCESS])
                }
                .width('100%')
                .padding(Theme.PAD_CARD)
                .borderRadius(Theme.RADIUS_ITEM)
                .backgroundColor($r('sys.color.comp_background_primary'))
                .onClick(() => {
                  this.readChapter(ch);
                })
              }
              .swipeAction({ end: this.deleteCell(ch) })
            }, (ch: Chapter) => `local_${ch.id}_${ch.path}`)
          }
          .width('100%')
          .layoutWeight(1)
      .padding({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp), top: 4 })
      .contentEndOffset(Theme.floatTabBarAvoid(this.bottomInset))
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .height('100%')
    }
    .title(this.comic.title.length > 0 ? this.comic.title : '本地漫画')
    .backgroundColor($r('sys.color.background_primary'))
    .onReady((ctx: NavDestinationContext) => {
      // Navigation 标准入口：ctx.pathStack 拿导航控制器，ctx.pathInfo.param 拿路由参数
      this.pathStack = ctx.pathStack;
      const p = ctx.pathInfo.param as Object;
      if (p instanceof DetailArgs) {
        this.comic = p.comic;
        // 正确章节顺序：按 id（入库序）升序 = 第1话 → 第N话
        this.chapters = p.chapters.slice().sort((a: Chapter, b: Chapter): number => a.id - b.id);
      }
    })
  }
}
