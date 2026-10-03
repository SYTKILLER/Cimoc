/** 详情页：沉浸式头部 + 智感握姿侧边胶囊（缓存/收藏，随左右手换边）+ 章节卡片网格。 */

import { Comic, Chapter, ReaderArgs } from '../model/Model';
import { ComicService } from '../service/ComicService';
import { ComicDao } from '../data/Daos';
import { DownloadManager } from '../download/DownloadManager';
import { SourceManager } from '../source/SourceManager';
import Theme from '../common/Theme';
import { PageTitleBar } from '../common/PageTitleBar';
import { shareComicText } from '../common/ShareUtil';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hdsEffect } from '@kit.UIDesignKit';

@Component
export struct DetailPage {
  @Consume('nav') navStack: NavPathStack;
  @StorageLink('bottomInset') bottomInset: number = 0;
  @StorageLink('bp') bp: string = 'sm';
  // 智感握姿按钮位置（Index 唯一写入：0=右下默认位，2=左下）与窗口高度（vp），本页只读
  @StorageLink('gripBtnPos') btnPos: number = 0;
  @StorageLink('winHVp') winHVp: number = 0;
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

  /** 分享链接：模型里没有 URL 字段，按源配置拼 baseUrl + cid（cid 已是绝对 URL 则原样）。 */
  private buildShareUrl(): string {
    if (this.comic.cid.length === 0) {
      return '';
    }
    if (this.comic.cid.startsWith('http://') || this.comic.cid.startsWith('https://')) {
      return this.comic.cid;
    }
    const cfg = SourceManager.get().getConfig(this.comic.source);
    return cfg !== null && cfg.baseUrl.length > 0 ? cfg.baseUrl + this.comic.cid : '';
  }

  /** 右上角分享：`[标题][链接]` 文本交给系统分享面板。 */
  private async shareComic(): Promise<void> {
    const url = this.buildShareUrl();
    if (url.length === 0) {
      promptAction.showToast({ message: '无法生成分享链接' });
      return;
    }
    await shareComicText(getContext(this) as common.UIAbilityContext, this.comic.title, url);
  }

  continueReading(): void {
    for (let i = 0; i < this.chapters.length; i++) {
      if (this.chapters[i].path === this.comic.last) {
        this.readChapter(this.chapters[i]);
        return;
      }
    }
    // 无历史（last 为空）或记录章节已不存在（如历史残留行被同步清理）时回退第一章，
    // 保证握姿胶囊阅读入口永远可用；进度仍由 readChapter 按真实打开写入，此处不预写记录
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

  /**
   * 智感握姿侧边胶囊：缓存 + 收藏 + 继续阅读（竖式三动作，阅读入口在最下方）。
   * 位置由根 Stack 的 alignContent 按握姿切换，
   * 换边动画由 Index 统一驱动，此处零动画代码；图标直接读 @State 保证收藏态随状态刷新。
   * 底色用系统毛玻璃材质（浅色下呈浅色磨砂、深色下呈深色磨砂），与返回键圆钮同款；
   * 图标/分隔线用 sys.color 自适应资源，浅色模式下不再是深色块。
   */
  @Builder
  gripSideButton() {
    Column({ space: 4 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.download'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
      }
      .width(56)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.openCacheSheet();
      })

      Divider()
        .strokeWidth(0.5)
        .width(28)
        .color($r('sys.color.comp_divider'))

      Row() {
        SymbolGlyph(this.comic.favorite > 0 ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
          .fontSize(24)
          .fontColor([this.comic.favorite > 0 ? Theme.WARNING : $r('sys.color.font_primary')])
      }
      .width(56)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .borderRadius(26)
      .backgroundColor(this.comic.favorite > 0 ? '#33FF9500' : Color.Transparent)
      .onClick(() => {
        this.toggleFavorite();
      })

      Divider()
        .strokeWidth(0.5)
        .width(28)
        .color($r('sys.color.comp_divider'))

      Row() {
        SymbolGlyph($r('sys.symbol.book_badge_play'))
          .fontSize(24)
          .fontColor([Theme.ACCENT])
      }
      .width(56)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.continueReading();
      })
    }
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 4, bottom: 4 })
    .width(60)
    .borderRadius(30)
    .backgroundBlurStyle(BlurStyle.Thin)
    .backgroundColor('#33000000')
    // 贴边一侧内收 PAD_PAGE：BottomEnd 对齐时负 x 向屏内推，换到 BottomStart 后对称
    .offset({
      x: this.btnPos === 0 ? -Theme.PAD_PAGE : Theme.PAD_PAGE,
      y: -this.winHVp * 0.3
    })
    // 智感光效：标识「会随握姿换边的活按钮」；收藏态靠心形颜色 + 底色高亮区分
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: hdsEffect.PointLightSourceType.BRIGHT,
        illuminatedType: hdsEffect.PointLightIlluminatedType.DEFAULT_FEATHERING_BORDER
      })
      .buildEffect())
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
        // 内容层：固定布局——页面本身不滚动（杜绝内容被划出屏幕外），
        // 头部/简介常驻，章节 Grid 独占剩余高度自行滚动、容器直通屏幕底部
        Column() {
          // 自定义标题栏：内置标题栏在真机全屏下不避让状态栏（模拟器由 HDS 桥接兜底），
          // 统一换成 PageTitleBar（topInset 补差，两端避让一致）
          PageTitleBar({
            title: this.comic.title.length > 0 ? this.comic.title : '详情',
            onBack: (): void => {
              this.navStack.pop(true);
            },
            menuIcon: $r('sys.symbol.share'),
            onMenu: (): void => {
              this.shareComic();
            }
          })
          // 头部：封面 + 信息
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
            top: 12,
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
            .justifyContent(FlexAlign.Center)
            .layoutWeight(1)
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
            .justifyContent(FlexAlign.Center)
            .layoutWeight(1)
            .width('100%')
          } else {
            // 章节标题行（固定，不随列表滚动）
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

            // 章节网格：layoutWeight(1) 通到屏幕底部，滚动只发生在 Grid 内部
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
                  .border(Theme.BORDER_HAIRLINE)
                  .shadow({ radius: 6, color: '#14000000', offsetY: 2 })
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
              bottom: 16 + this.bottomInset
            })
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
        .width('100%')
        .height('100%')

        // 智感握姿侧边胶囊：根 Stack 全屏 + alignContent 随握姿在右下/左下间切换
        this.gripSideButton()
      }
      .width('100%')
      .height('100%')
      .alignContent(this.btnPos === 0 ? Alignment.BottomEnd : Alignment.BottomStart)
      .bindSheet(this.sheetShow, this.cacheSheetBuilder(), {
        height: SheetSize.MEDIUM,
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: true,
        showClose: true,
        onDisappear: (): void => {
          this.sheetShow = false;
        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor($r('sys.color.background_primary'))
  }
}
