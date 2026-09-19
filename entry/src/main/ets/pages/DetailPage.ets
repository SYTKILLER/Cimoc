/** 详情页：沉浸式头部 + 毛玻璃操作按钮 + 章节卡片网格。 */

import { Comic, Chapter, ReaderArgs } from '../model/Model';
import { ComicService } from '../service/ComicService';
import { ComicDao } from '../data/Daos';
import { DownloadManager } from '../download/DownloadManager';
import Theme from '../common/Theme';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

@Component
export struct DetailPage {
  @Consume('nav') navStack: NavPathStack;
  @StorageLink('topInset') topInset: number = 0;
  @StorageLink('bottomInset') bottomInset: number = 0;
  @StorageLink('bp') bp: string = 'sm';
  @State comic: Comic = new Comic(0, '', '');
  @State chapters: Chapter[] = [];
  @State loading: boolean = true;
  @State errorText: string = '';
  @State asc: boolean = false;
  // 缓存半模态面板（缓存状态不在详情页展示，查重统一在下载阶段做）
  @State sheetShow: boolean = false;
  @State selectedPaths: Set<string> = new Set<string>();
  private comicDao: ComicDao | null = null;
  private service: ComicService | null = null;

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    this.comicDao = new ComicDao(ctx);
    this.service = ComicService.get(ctx);
    const params = this.navStack.getParamByName('detail') as Array<Object>;
    if (params.length > 0) {
      const c = params[params.length - 1] as Comic;
      this.comic = c;
      this.fetch(c.source, c.cid);
    }
  }

  async fetch(source: number, cid: string): Promise<void> {
    if (this.service === null) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    try {
      const r = await this.service.getComicInfo(source, cid);
      if (r !== null) {
        this.comic = r[0];
        this.chapters = r[1];
      }
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : String(e);
    }
    this.loading = false;
  }

  async toggleFavorite(): Promise<void> {
    if (this.comicDao === null) {
      return;
    }
    if (this.comic.favorite > 0) {
      this.comic.favorite = 0;
    } else {
      this.comic.favorite = Date.now();
    }
    await this.comicDao.updateOrDelete(this.comic);
    AppStorage.setOrCreate('library_dirty', Date.now());
    this.chapters = this.chapters.slice();
  }

  async readChapter(chapter: Chapter): Promise<void> {
    // 对齐原版 DetailPresenter.updateLast：打开章节即记历史；已收藏则刷新收藏时间
    if (this.comicDao !== null && this.comic.id > 0) {
      if (this.comic.favorite > 0) {
        this.comic.favorite = Date.now();
      }
      this.comic.history = Date.now();
      if (chapter.path !== this.comic.last) {
        this.comic.last = chapter.path;
        this.comic.page = 1;
      }
      await this.comicDao.updateOrDelete(this.comic);
      AppStorage.setOrCreate('library_dirty', Date.now());
    }
    this.navStack.pushPathByName('reader', new ReaderArgs(this.comic, this.chapters, this.chapterIndex(chapter)));
  }

  chapterIndex(chapter: Chapter): number {
    for (let i = 0; i < this.chapters.length; i++) {
      if (this.chapters[i].path === chapter.path) {
        return i;
      }
    }
    return 0;
  }

  continueReading(): void {
    if (this.comic.last.length === 0) {
      return;
    }
    for (let i = 0; i < this.chapters.length; i++) {
      if (this.chapters[i].path === this.comic.last) {
        this.readChapter(this.chapters[i]);
        return;
      }
    }
    // 记录章节已不存在（如历史残留行被同步清理）时回退第一章，避免按钮失效
    if (this.chapters.length > 0) {
      this.readChapter(this.chapters[0]);
    }
  }

  orderedChapters(): Chapter[] {
    if (this.asc) {
      return this.chapters;
    }
    return this.chapters.slice().reverse();
  }

  headerCoverSrc(): string | undefined {
    return this.comic.cover.length > 0 ? this.comic.cover : undefined;
  }

  openCacheSheet(): void {
    this.selectedPaths = new Set<string>();
    this.sheetShow = true;
  }

  toggleSelect(path: string): void {
    const next = new Set<string>(this.selectedPaths);
    if (next.has(path)) {
      next.delete(path);
    } else {
      next.add(path);
    }
    this.selectedPaths = next;
  }

  toggleSelectAll(): void {
    if (this.selectedPaths.size >= this.chapters.length) {
      this.selectedPaths = new Set<string>();
      return;
    }
    const next = new Set<string>();
    for (const ch of this.chapters) {
      next.add(ch.path);
    }
    this.selectedPaths = next;
  }

  async startCache(): Promise<void> {
    if (this.selectedPaths.size === 0) {
      return;
    }
    const targets: Chapter[] = [];
    for (const ch of this.chapters) {
      if (this.selectedPaths.has(ch.path)) {
        targets.push(ch);
      }
    }
    const mgr = DownloadManager.get(getContext(this) as common.UIAbilityContext);
    // 查重在下载阶段做：已下载的跳过，失败的重试，只在队列的恢复
    let queued = 0;
    for (const ch of targets) {
      const ok = await mgr.addDownload(this.comic, ch);
      if (ok) {
        queued++;
      }
    }
    this.selectedPaths = new Set<string>();
    this.sheetShow = false;
    if (queued === 0) {
      promptAction.showToast({ message: '所选章节均已在缓存中' });
    } else if (queued === targets.length) {
      AppStorage.setOrCreate('library_dirty', Date.now());
      promptAction.showToast({ message: `已加入缓存 ${queued} 章` });
    } else {
      AppStorage.setOrCreate('library_dirty', Date.now());
      promptAction.showToast({ message: `已加入缓存 ${queued} 章，${targets.length - queued} 章已有缓存` });
    }
  }

  @Builder
  circleButton(icon: Resource, action: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([$r('sys.color.font_primary')])
    }
    .width(38)
    .height(38)
    .borderRadius(Theme.RADIUS_PILL)
    .backgroundBlurStyle(BlurStyle.Thin)
    .backgroundColor('#33000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      action();
    })
  }

  // 图标在 Builder 内部直接读取 @State，避免按值传参导致图标不随收藏状态刷新
  @Builder
  favButton() {
    Row() {
      SymbolGlyph(this.comic.favorite > 0 ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
        .fontSize(20)
        .fontColor([$r('sys.color.font_primary')])
    }
    .width(38)
    .height(38)
    .borderRadius(Theme.RADIUS_PILL)
    .backgroundBlurStyle(BlurStyle.Thin)
    .backgroundColor('#33000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.toggleFavorite();
    })
  }

  // 缓存选择半模态面板：内容直接读 this.* 状态（@Builder 按值参数不会随状态刷新）。
  // 保留系统 showClose 关闭按钮，标题行右侧留出空区避让面板右上角的系统 X
  @Builder
  cacheSheetBuilder() {
    Column() {
      Row() {
        Text('缓存章节')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Text('全选')
          .fontSize(13)
          .fontColor(Theme.ACCENT)
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .borderRadius(Theme.RADIUS_PILL)
          .backgroundColor(Theme.ACCENT_SOFT)
          .onClick(() => {
            this.toggleSelectAll();
          })
      }
      .width('100%')
      .padding({ right: 44 })

      if (this.orderedChapters().length === 0) {
        Text('暂无可缓存的章节')
          .fontSize(13)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ top: 40 })
      } else {
        List() {
          ForEach(this.orderedChapters(), (ch: Chapter) => {
            ListItem() {
              Row({ space: 10 }) {
                Text(`${ch.group === '默认' ? '' : ch.group + ' · '}${ch.title}`)
                  .fontSize(14)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)

                Column() {}
                  .width(20)
                  .height(20)
                  .borderRadius(Theme.RADIUS_PILL)
                  .borderWidth(1.5)
                  .borderColor(this.selectedPaths.has(ch.path) ? Theme.ACCENT : $r('sys.color.font_tertiary'))
                  .backgroundColor(this.selectedPaths.has(ch.path) ? Theme.ACCENT : Color.Transparent)
              }
              .width('100%')
              .padding({ left: 4, right: 8, top: 11, bottom: 11 })
              .onClick(() => {
                this.toggleSelect(ch.path);
              })
            }
          }, (ch: Chapter) => `sheet_${ch.id}_${ch.path}_${this.selectedPaths.has(ch.path) ? 1 : 0}`)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .margin({ top: 6 })
      }

      Button(this.selectedPaths.size > 0 ? `开始缓存（${this.selectedPaths.size}）` : '选择要缓存的章节')
        .type(ButtonType.Capsule)
        .width('100%')
        .height(44)
        .fontSize(15)
        .enabled(this.selectedPaths.size > 0)
        .backgroundColor(this.selectedPaths.size > 0 ? Theme.ACCENT : $r('sys.color.comp_background_tertiary'))
        .fontColor(this.selectedPaths.size > 0 ? Color.White : $r('sys.color.font_tertiary'))
        .margin({ top: 10 })
        .onClick(() => {
          this.startCache();
        })
    }
    .padding({ left: 20, right: 20, top: 16, bottom: 24 })
    .width('100%')
    .height('100%')
  }

  build() {
    NavDestination() {
      Stack() {
        // 内容层
        Column() {
          Scroll() {
            Column() {
              Row({ space: 14 }) {
                Image(this.headerCoverSrc())
                  .width(112)
                  .height(152)
                  .borderRadius(Theme.RADIUS_ITEM)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .objectFit(ImageFit.Cover)
                  .shadow(Theme.CARD_SHADOW)

                Column({ space: 6 }) {
                  Text(this.comic.title.length > 0 ? this.comic.title : '加载中…')
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('sys.color.font_primary'))
                    .maxLines(3)
                  Text(`作者：${this.comic.author.length > 0 ? this.comic.author : '未知'}`)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .maxLines(1)
                  Row({ space: 8 }) {
                    Text(this.comic.finish ? '已完结' : '连载中')
                      .fontSize(10)
                      .fontColor(this.comic.finish ? Theme.SUCCESS : Theme.WARNING)
                      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                      .borderRadius(Theme.RADIUS_PILL)
                      .backgroundColor(this.comic.finish ? '#1A4CAF50' : '#1AFF9500')
                    Text(`更新 ${this.comic.update.length > 0 ? this.comic.update : '—'}`)
                      .fontSize(10)
                      .fontColor($r('sys.color.font_tertiary'))
                  }

                  Row({ space: 8 }) {
                    if (this.comic.last.length > 0) {
                      Button('继续阅读')
                        .type(ButtonType.Capsule)
                        .fontSize(13)
                        .height(34)
                        .backgroundColor(Theme.ACCENT)
                        .onClick(() => {
                          this.continueReading();
                        })
                    }
                    Button(this.comic.favorite > 0 ? '已收藏' : '收藏')
                      .type(ButtonType.Capsule)
                      .fontSize(13)
                      .height(34)
                      .fontColor(this.comic.favorite > 0 ? $r('sys.color.font_primary') : Color.White)
                      .backgroundColor(this.comic.favorite > 0 ? $r('sys.color.comp_background_tertiary') : Theme.WARNING)
                      .onClick(() => {
                        this.toggleFavorite();
                      })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .padding({
                left: Theme.pagePad(this.bp),
                right: Theme.pagePad(this.bp),
                top: 52 + this.topInset,
                bottom: 12
              })
              .width('100%')

              if (this.comic.intro.length > 0) {
                Text(this.comic.intro)
                  .fontSize(12)
                  .fontColor($r('sys.color.font_secondary'))
                  .lineHeight(18)
                  .maxLines(3)
                  .padding({
                    left: Theme.pagePad(this.bp),
                    right: Theme.pagePad(this.bp),
                    bottom: 10
                  })
                  .width('100%')
              }

              if (this.loading) {
                Column({ space: 10 }) {
                  LoadingProgress().width(36).height(36).color(Theme.ACCENT)
                  Text('正在加载章节…')
                    .fontSize(12)
                    .fontColor($r('sys.color.font_tertiary'))
                }
                .margin({ top: 50 })
                .width('100%')
              } else if (this.errorText.length > 0) {
                Column({ space: 10 }) {
                  SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
                    .fontSize(40)
                    .fontColor([$r('sys.color.font_fourth')])
                  Text(`加载失败：${this.errorText}`)
                    .fontSize(12)
                    .fontColor(Theme.DANGER)
                    .textAlign(TextAlign.Center)
                    .maxLines(3)
                  Button('重试')
                    .type(ButtonType.Capsule)
                    .backgroundColor(Theme.ACCENT)
                    .onClick(() => {
                      this.fetch(this.comic.source, this.comic.cid);
                    })
                }
                .margin({ top: 40, left: 24, right: 24 })
                .width('100%')
              } else {
                // 章节标题行
                Row() {
                  Text(`章节 · ${this.chapters.length}`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('sys.color.font_primary'))
                  Blank()
                  Text(this.asc ? '正序 ↑' : '倒序 ↓')
                    .fontSize(12)
                    .fontColor(Theme.ACCENT)
                    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    .borderRadius(Theme.RADIUS_PILL)
                    .backgroundColor($r('sys.color.comp_background_tertiary'))
                    .onClick(() => {
                      this.asc = !this.asc;
                    })
                }
                .padding({
                  left: Theme.pagePad(this.bp),
                  right: Theme.pagePad(this.bp),
                  top: 4,
                  bottom: 8
                })
                .width('100%')

                Grid() {
                  ForEach(this.orderedChapters(), (ch: Chapter) => {
                    GridItem() {
                      Column({ space: 3 }) {
                        Text(`${ch.group === '默认' ? '' : ch.group + ' · '}${ch.title}`)
                          .width('100%')
                          .fontSize(12)
                          .maxLines(1)
                          .textAlign(TextAlign.Start)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .fontColor(ch.path === this.comic.last ? Theme.ACCENT : $r('sys.color.font_primary'))
                      }
                      .width('100%')
                      .padding({ left: 6, right: 6 })
                      .justifyContent(FlexAlign.Center)
                      .height(44)
                      .borderRadius(Theme.RADIUS_SMALL)
                      .backgroundColor(ch.path === this.comic.last ? Theme.ACCENT_SOFT : $r('sys.color.comp_background_primary'))
                      .onClick(() => {
                        this.readChapter(ch);
                      })
                    }
                    .stateStyles({
                      pressed: { .opacity(Theme.PRESS_OPACITY) },
                      normal: { .opacity(1) }
                    })
                  }, (ch: Chapter) => `${ch.id}_${ch.path}_${this.asc ? 1 : 0}`)
                }
                .columnsTemplate(Theme.chapterCols(this.bp))
                .columnsGap(8)
                .rowsGap(8)
                .padding({
                  left: Theme.pagePad(this.bp),
                  right: Theme.pagePad(this.bp),
                  bottom: 30 + this.bottomInset
                })
                .height('100%')
              }
            }
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')

        // 顶部浮动按钮（毛玻璃）
        Row() {
          this.circleButton($r('sys.symbol.chevron_left'), (): void => {
            this.navStack.pop();
          })
          Blank()
          Row({ space: 10 }) {
            this.circleButton($r('sys.symbol.download'), (): void => {
              this.openCacheSheet();
            })
            this.favButton()
          }
        }
        .padding({ left: Theme.PAD_PAGE, right: Theme.PAD_PAGE, top: 10 + this.topInset })
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
      .width('100%')
      .height('100%')
      .alignContent(Alignment.Top)
      .bindSheet(this.sheetShow, this.cacheSheetBuilder(), {
        height: SheetSize.MEDIUM,
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: true,
        showClose: true,
        onDisappear: (): void => {
          this.sheetShow = false;
        }
      })    }
    .hideTitleBar(true)
    .backgroundColor($r('sys.color.background_primary'))
  }
}
