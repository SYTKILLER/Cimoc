/** 本地漫画页："本地"列表进入的轻量详情——只展示已缓存章节（按正确章节顺序），
 *  全程零网络、零加载态；章节列表可正序/倒序切换，当前进度章节高亮；
 *  智感握姿"继续阅读"胶囊为唯一阅读入口（联网详情页三联胶囊的单一动作版）。
 *  阅读进度独立于联网进度：不写 COMIC 表，由 ReaderPage 落 Preferences（LocalProgress）。
 *  Navigation 架构：系统路由表注册，onReady 标准入口取 NavPathStack 与路由参数，不使用 router。 */

import { Chapter, Comic, DetailArgs, ReaderArgs } from '../model/Model';
import { DownloadManager } from '../download/DownloadManager';
import { LocalProgress } from '../data/LocalProgress';
import Theme from '../common/Theme';
import { PageTitleBar } from '../common/PageTitleBar';
import { hdsEffect } from '@kit.UIDesignKit';
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
  // 智感握姿按钮位置（Index 唯一写入：0=右下默认位，2=左下）与窗口高度（vp），本页只读
  @StorageLink('gripBtnPos') btnPos: number = 0;
  @StorageLink('winHVp') winHVp: number = 0;
  private pathStack: NavPathStack | null = null;
  @State comic: Comic = new Comic(0, '', '');
  // 已缓存章节，按章节正确顺序（入库顺序 = 原始顺序）排列
  @State chapters: Chapter[] = [];
  // 本地阅读进度（Preferences，独立于联网进度）：高亮当前章 + 继续阅读定位
  @State localProgress: LocalProgress = new LocalProgress();
  @State asc: boolean = true;

  chapterIndex(ch: Chapter): number {
    for (let i = 0; i < this.chapters.length; i++) {
      if (this.chapters[i].path === ch.path) {
        return i;
      }
    }
    return 0;
  }

  readChapter(ch: Chapter): void {
    // 本地阅读不写 COMIC 表（favorite/history/last 保持联网语义不被本地阅读覆盖）；
    // local=true 让阅读器离线锁定，只读本地文件，进度由 ReaderPage 落 Preferences。
    // 打开章节即乐观更新进度态（对齐联网页"打开即记录"），返回时 onShown 再回读真实落库值
    const lp = new LocalProgress();
    lp.path = ch.path;
    lp.title = ch.title;
    lp.time = Date.now();
    this.localProgress = lp;
    if (this.pathStack !== null) {
      this.pathStack.pushPathByName('reader', new ReaderArgs(this.comic, this.chapters, this.chapterIndex(ch), true));
    }
  }

  /** 进度指向的章节（已被左滑删除后返回 null）。 */
  private progressChapter(): Chapter | null {
    if (this.localProgress.path.length === 0) {
      return null;
    }
    for (const ch of this.chapters) {
      if (ch.path === this.localProgress.path) {
        return ch;
      }
    }
    return null;
  }

  continueReading(): void {
    const ch = this.progressChapter();
    if (ch !== null) {
      this.readChapter(ch);
      return;
    }
    // 无本地进度或进度章节已被左滑删除：从第一章开始阅读，胶囊作为唯一阅读入口保持可用；
    // 进度仍由 ReaderPage 按真实阅读落 Preferences，此处不预写记录
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

  /**
   * 智感握姿继续阅读胶囊：本地详情页唯一阅读入口。
   * 位置由根 Stack 的 alignContent 按握姿切换，换边动画由 Index 统一驱动，此处零动画代码；
   * 底色与联网详情页胶囊同款系统毛玻璃材质，图标用 sys.color 自适应 + ACCENT 点亮。
   * 只要有缓存章节就常显：无本地进度或进度章节已被删除时，点击从第一章开始阅读，
   * 避免唯一阅读入口在从未读过时凭空消失。
   */
  @Builder
  gripContinueButton() {
    Row() {
      SymbolGlyph($r('sys.symbol.book_badge_play'))
        .fontSize(24)
        .fontColor([Theme.ACCENT])
    }
    .width(60)
    .height(60)
    .justifyContent(FlexAlign.Center)
    .borderRadius(30)
    .backgroundBlurStyle(BlurStyle.Thin)
    .backgroundColor('#33000000')
    // 贴边一侧内收 PAD_PAGE：BottomEnd 对齐时负 x 向屏内推，换到 BottomStart 后对称
    .offset({
      x: this.btnPos === 0 ? -Theme.PAD_PAGE : Theme.PAD_PAGE,
      y: -this.winHVp * 0.3
    })
    // 智感光效：标识「会随握姿换边的活按钮」，与联网详情页胶囊一致
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: hdsEffect.PointLightSourceType.BRIGHT,
        illuminatedType: hdsEffect.PointLightIlluminatedType.DEFAULT_FEATHERING_BORDER
      })
      .buildEffect())
    .onClick(() => {
      this.continueReading();
    })
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          // 自定义标题栏：内置标题栏在真机全屏下不避让状态栏（模拟器由 HDS 桥接兜底）
          PageTitleBar({
            title: this.comic.title.length > 0 ? this.comic.title : '本地漫画',
            onBack: (): void => {
              if (this.pathStack !== null) {
                this.pathStack.pop(true);
              }
            }
          })
          // 副标题行：缓存计数 + 正序/倒序切换
          Row() {
            Text(`已缓存 ${this.chapters.length} 章 · 离线可读`)
              .fontSize(12)
              .fontColor($r('sys.color.font_tertiary'))
            Blank()
            if (this.chapters.length > 0) {
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
          }
          .width('100%')
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
              ForEach(this.orderedChapters(), (ch: Chapter) => {
                ListItem() {
                  // 进度章节整卡高亮（ACCENT_SOFT 底 + ACCENT 标题），对齐联网详情页的当前章样式
                  Column({ space: 3 }) {
                    Text(ch.title)
                      .fontSize(14)
                      .fontWeight(ch.path === this.localProgress.path ? FontWeight.Medium : FontWeight.Normal)
                      .fontColor(ch.path === this.localProgress.path ? Theme.ACCENT : $r('sys.color.font_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (ch.count > 0) {
                      Text(`${ch.count} 图`)
                        .fontSize(11)
                        .fontColor($r('sys.color.font_tertiary'))
                    }
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .padding(Theme.PAD_CARD)
                  .borderRadius(Theme.RADIUS_ITEM)
                  .backgroundColor(ch.path === this.localProgress.path
                    ? Theme.ACCENT_SOFT : $r('sys.color.comp_background_primary'))
                  .border(Theme.BORDER_HAIRLINE)
                  .onClick(() => {
                    this.readChapter(ch);
                  })
                }
                .swipeAction({ end: this.deleteCell(ch) })
              }, (ch: Chapter) => `local_${ch.id}_${ch.path}_${this.asc ? 1 : 0}`)
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

        // 智感握姿继续阅读胶囊：根 Stack 全屏 + alignContent 随握姿在右下/左下间切换
        if (this.chapters.length > 0) {
          this.gripContinueButton()
        }
      }
      .width('100%')
      .height('100%')
      .alignContent(this.btnPos === 0 ? Alignment.BottomEnd : Alignment.BottomStart)
    }
    .hideTitleBar(true)
    .backgroundColor($r('sys.color.background_primary'))
    .onReady((ctx: NavDestinationContext) => {
      // Navigation 标准入口：ctx.pathStack 拿导航控制器，ctx.pathInfo.param 拿路由参数
      this.pathStack = ctx.pathStack;
      const p = ctx.pathInfo.param as Object;
      if (p instanceof DetailArgs) {
        this.comic = p.comic;
        // 正确章节顺序：按 id（入库序）升序 = 第1话 → 第N话
        this.chapters = p.chapters.slice().sort((a: Chapter, b: Chapter): number => a.id - b.id);
        this.reloadLocalProgress();
      }
    })
    .onShown(() => {
      // 本页常驻导航栈：从阅读器返回不会重建，进度要在每次可见时回读
      // （阅读器内可能已切章，落库值以 Preferences 为准）
      this.reloadLocalProgress();
    })
  }

  /** 回读本地阅读进度（Preferences）：刷新当前章高亮与继续阅读胶囊。 */
  private reloadLocalProgress(): void {
    LocalProgress.load(getContext(this) as common.UIAbilityContext, this.comic.id)
      .then((lp: LocalProgress): void => {
        this.localProgress = lp;
      });
  }
}
