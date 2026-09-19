/**
 * 阅读器：翻页(Swiper) / 条漫(List) 双模式，默认条漫。
 * 条漫模式下图片按原始宽高比铺满宽度、上下无缝拼接为流式阅读。
 * 预加载、进度持久化、章节切换、方向设置、阅读器内模式切换。
 */

import { Comic, Chapter, ImageInfo, ReaderArgs } from '../model/Model';
import { ComicService } from '../service/ComicService';
import { ImageLoader } from '../image/ImageLoader';
import { Prefs, PrefKeys } from '../data/Prefs';
import { HttpHeader } from '../network/HttpClient';
import { SourceManager } from '../source/SourceManager';
import Theme from '../common/Theme';
import { image } from '@kit.ImageKit';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { batteryInfo } from '@kit.BasicServicesKit';

/** List 懒加载数据源。 */
class ImageDataSource implements IDataSource {
  private list: ImageInfo[] = [];
  private listeners: DataChangeListener[] = [];

  refresh(list: ImageInfo[]): void {
    this.list = list;
    this.listeners.forEach((l: DataChangeListener) => l.onDataReloaded());
  }

  totalCount(): number {
    return this.list.length;
  }

  getData(index: number): ImageInfo | null {
    return index >= 0 && index < this.list.length ? this.list[index] : null;
  }

  registerDataChangeListener(l: DataChangeListener): void {
    this.listeners.push(l);
  }

  unregisterDataChangeListener(l: DataChangeListener): void {
    const i = this.listeners.indexOf(l);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }
}

@Component
struct ReaderImage {
  @Prop url: string = '';
  @Prop referer: string = '';
  /** 条漫流式布局：按原图宽高比撑高，保证上下无缝拼接。 */
  @Prop stream: boolean = false;
  @Prop @Watch('onActiveChange') active: boolean = true;
  @State pm: image.PixelMap | null = null;
  @State ratio: number = 0;
  @State failed: boolean = false;
  @State loading: boolean = false;
  onTap: () => void = () => {};

  aboutToAppear(): void {
    if (this.active) {
      this.load();
    }
  }

  onActiveChange(): void {
    if (this.active && this.pm === null && !this.failed && !this.loading) {
      this.load();
    }
  }

  async load(): Promise<void> {
    if (this.url.length === 0) {
      this.failed = true;
      return;
    }
    this.loading = true;
    try {
      const headers: HttpHeader | null = this.referer.length > 0
        ? HttpHeader.of([['Referer', this.referer]]) : null;
      const pm = await ImageLoader.get(getContext(this) as common.UIAbilityContext).load(this.url, headers);
      try {
        const info = await pm.getImageInfo();
        if (info.size.width > 0 && info.size.height > 0) {
          this.ratio = info.size.width / info.size.height;
        }
      } catch (e) {
        // 取不到尺寸时退化为组件自适应高度
      }
      this.pm = pm;
      this.failed = false;
    } catch (e) {
      this.failed = true;
    }
    this.loading = false;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.pm !== null) {
        if (this.stream && this.ratio > 0) {
          Image(this.pm)
            .width('100%')
            .aspectRatio(this.ratio)
            .objectFit(ImageFit.Contain)
            .interpolation(ImageInterpolation.Low)
        } else {
          Image(this.pm)
            .width('100%')
            .objectFit(ImageFit.Contain)
            .interpolation(ImageInterpolation.Low)
        }
      } else if (this.failed) {
        Column({ space: 6 }) {
          Text('加载失败').fontSize(13).fontColor('#999999')
          Button('重试').fontSize(12).height(28).onClick(() => {
            this.failed = false;
            this.load();
          })
        }.width('100%').height(160)
      } else {
        Column({ space: 6 }) {
          LoadingProgress().width(30).height(30).color('#BBBBBB')
          Text('加载中…').fontSize(10).fontColor('#AAAAAA')
        }.width('100%').height(240)
      }
    }
    .width('100%')
    .backgroundColor(this.pm !== null ? '#000000' : '#111111')
    .onClick(() => {
      this.onTap();
    })
  }
}

@Component
export struct ReaderPage {
  @Consume('nav') navStack: NavPathStack;
  @State comic: Comic = new Comic(0, '', '');
  @State chapters: Chapter[] = [];
  @State index: number = 0;
  @State images: ImageInfo[] = [];
  @State loading: boolean = true;
  @State errorText: string = '';
  @State showBars: boolean = true;
  @State clockText: string = '';
  @State batteryText: string = '';
  @State pageMode: number = 0;
  @State turnDirection: number = 0;
  @State pageIndex: number = 0;
  @State topInset: number = 0;
  @State bottomInset: number = 0;
  @State streamSource: ImageDataSource = new ImageDataSource();
  private referer: string = '';
  // 离线锁定（"本地"页进入）：图片只允许本地文件，禁止网络回退
  private localOnly: boolean = false;
  private service: ComicService | null = null;
  private scroller: Scroller = new Scroller();
  private win: window.Window | null = null;
  private avoidHandler: ((data: window.AvoidAreaOptions) => void) | null = null;
  private barTimer: number = -1;

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    this.service = ComicService.get(ctx);
    const params = this.navStack.getParamByName('reader') as Array<Object>;
    if (params.length > 0) {
      const args = params[params.length - 1] as ReaderArgs;
      this.comic = args.comic;
      this.chapters = args.chapters;
      this.index = args.index;
      this.localOnly = args.local;
    }
    Prefs.getInt(ctx, PrefKeys.READER_MODE, 1).then((v: number) => {
      this.pageMode = v;
      if (this.pageMode === 1) {
        this.streamSource.refresh(this.images);
      }
    });
    Prefs.getBool(ctx, PrefKeys.READER_KEEP_ON, true).then((on: boolean) => {
      this.keepScreenOn(on);
    });
    // 窗口全屏布局：漫画内容真正画进状态栏/导航条区域，退出时恢复
    window.getLastWindow(ctx).then((w: window.Window) => {
      this.win = w;
      this.readInsets(w);
      this.avoidHandler = (): void => {
        this.readInsets(w);
      };
      w.on('avoidAreaChange', this.avoidHandler);
      w.setWindowLayoutFullScreen(true).catch(() => {
        // 保持安全区布局时仍有 expandSafeArea 兜底，忽略失败
      });
    });
    this.startClock();
    const parser = SourceManager.get().getParser(this.comic.source);
    if (parser !== null) {
      const h = parser.imageHeaders();
      if (h !== null) {
        const ref = h.get('Referer');
        this.referer = ref !== undefined ? ref : '';
      }
    }
    this.loadChapter();
  }

  private keepScreenOn(on: boolean): void {
    try {
      window.getLastWindow(getContext(this)).then((w: window.Window) => {
        w.setWindowKeepScreenOn(on);
      });
    } catch (e) {
      // ignore
    }
  }

  /** 记录状态栏/导航条高度(vp)，工具栏避让用。 */
  private readInsets(w: window.Window): void {
    const sys = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const nav = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    this.topInset = this.getUIContext().px2vp(sys.topRect.height);
    this.bottomInset = this.getUIContext().px2vp(nav.bottomRect.height);
  }

  /** 工具栏显隐：隐藏后停刷时间/电量，展示时立即刷新一次。 */
  toggleBars(): void {
    this.showBars = !this.showBars;
    if (this.showBars) {
      this.startClock();
    } else {
      this.stopClock();
    }
  }

  private refreshStatus(): void {
    const d = new Date();
    const m = d.getMinutes();
    this.clockText = `${d.getHours()}:${m < 10 ? '0' + m : m}`;
    this.batteryText = `${batteryInfo.batterySOC}%`;
  }

  private startClock(): void {
    this.refreshStatus();
    if (this.barTimer === -1) {
      this.barTimer = setInterval((): void => {
        this.refreshStatus();
      }, 15000);
    }
  }

  private stopClock(): void {
    if (this.barTimer !== -1) {
      clearInterval(this.barTimer);
      this.barTimer = -1;
    }
  }

  async loadChapter(): Promise<void> {
    if (this.service === null || this.chapters.length === 0) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    this.images = [];
    try {
      const imgs = await this.service.loadChapterImages(this.comic, this.chapters[this.index], false, this.localOnly);
      this.images = imgs;
      const restorePage = this.chapters[this.index].path === this.comic.last && this.comic.page > 0
        ? Math.min(this.comic.page - 1, Math.max(imgs.length - 1, 0)) : 0;
      if (this.pageMode === 1) {
        this.streamSource.refresh(imgs);
        // 等列表完成一次布局后再定位，首帧高度未定时直接滚会跳不准
        setTimeout(() => {
          this.scroller.scrollToIndex(restorePage, false);
        }, 100);
      }
      this.pageIndex = restorePage;
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : String(e);
    }
    this.loading = false;
  }

  /**
   * 手动刷新：忽略缓存强制网络重拉当前章节。
   * 部分源对最新话有独占/分批解锁机制，首次抓到的列表可能不全，
   * 缓存后无法自行恢复，需要用户手动强制刷新。
   */
  async refreshChapter(): Promise<void> {
    if (this.service === null || this.chapters.length === 0 || this.loading) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    try {
      // 离线锁定下刷新只重读本地文件，不联网
      const imgs = await this.service.loadChapterImages(this.comic, this.chapters[this.index], this.localOnly ? false : true, this.localOnly);
      this.images = imgs;
      if (this.pageIndex > imgs.length - 1) {
        this.pageIndex = Math.max(imgs.length - 1, 0);
      }
      if (this.pageMode === 1) {
        this.streamSource.refresh(imgs);
        // 等列表完成一次布局后再定位，首帧高度未定时直接滚会跳不准
        setTimeout(() => {
          this.scroller.scrollToIndex(this.pageIndex, false);
        }, 100);
      }
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : String(e);
    }
    this.loading = false;
  }

  async saveProgress(): Promise<void> {
    if (this.service === null || this.chapters.length === 0) {
      return;
    }
    const ch = this.chapters[this.index];
    this.comic.last = ch.path;
    this.comic.chapter = ch.title;
    this.comic.page = this.pageIndex + 1;
    this.comic.history = Date.now();
    this.comic.highlight = false;
    await this.service.comicDaoRef().updateProgress(this.comic);
  }

  async switchChapter(delta: number): Promise<void> {
    const next = this.index + delta;
    if (next < 0 || next >= this.chapters.length) {
      return;
    }
    await this.saveProgress();
    this.index = next;
    this.pageIndex = 0;
    this.loadChapter();
  }

  /** 阅读器内切换 翻页/条漫 并持久化，条漫下保持当前页位置。 */
  setMode(mode: number): void {
    if (this.pageMode === mode) {
      return;
    }
    this.pageMode = mode;
    const ctx = getContext(this) as common.UIAbilityContext;
    Prefs.putInt(ctx, PrefKeys.READER_MODE, mode);
    if (mode === 1) {
      this.streamSource.refresh(this.images);
      const target = this.pageIndex;
      setTimeout(() => {
        this.scroller.scrollToIndex(target, false);
      }, 100);
    }
  }

  aboutToDisappear(): void {
    this.stopClock();
    // 退出阅读器恢复窗口安全区布局，并注销本页的避让区监听
    if (this.win !== null) {
      if (this.avoidHandler !== null) {
        this.win.off('avoidAreaChange', this.avoidHandler);
        this.avoidHandler = null;
      }
      this.win.setWindowLayoutFullScreen(false).catch(() => {
        // ignore
      });
      this.win = null;
    }
    // 退出阅读器时进度/历史已落库，通知书库刷新
    this.saveProgress().then(() => {
      AppStorage.setOrCreate('library_dirty', Date.now());
    });
  }

  @Builder
  readerCircleButton(icon: Resource, enabled: boolean, action: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([enabled ? '#FFFFFF' : '#666666'])
    }
    .width(38)
    .height(38)
    .borderRadius(Theme.RADIUS_PILL)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(enabled ? '#33FFFFFF' : '#1AFFFFFF')
    .onClick(() => {
      if (enabled) {
        action();
      }
    })
  }

  @Builder
  topBar() {
    Row({ space: 12 }) {
      this.readerCircleButton($r('sys.symbol.chevron_left'), true, (): void => {
        this.navStack.pop();
      })
      // 章节标题比漫画名更能确认当前进度；章节未就绪时回退漫画名
      Text(this.chapters.length > 0 ? this.chapters[this.index].title : this.comic.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .maxLines(1)
        .layoutWeight(1)
      // 全屏下系统时间不可见，工具栏内直接给出时间与电量
      Text(this.clockText)
        .fontSize(13)
        .fontColor('#FFFFFF')
      Text(this.batteryText)
        .fontSize(13)
        .fontColor('#CCCCCC')
      Text(`${this.index + 1}/${this.chapters.length}章`)
        .fontSize(12)
        .fontColor('#CCCCCC')
    }
    .padding({ left: 12, right: 12, top: 8 + this.topInset, bottom: 8 })
    .backgroundColor('#99000000')
    .borderRadius({ bottomLeft: 20, bottomRight: 20 })
    .backgroundBlurStyle(BlurStyle.Thin)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -32 }))
      .animation({ duration: 250, curve: Curve.EaseInOut }))
  }

  @Builder
  bottomBar() {
    Column({ space: 12 }) {
      // 进度滑杆，两端直读页码，替代独立页码文本
      Row({ space: 10 }) {
        Text(`${this.pageIndex + 1}`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .width(34)
          .textAlign(TextAlign.End)
        Slider({ value: this.pageIndex + 1, min: 1, max: Math.max(this.images.length, 1), step: 1 })
          .selectedColor(Theme.ACCENT)
          .blockColor(Theme.ACCENT)
          .trackColor('#33FFFFFF')
          .trackThickness(3)
          .layoutWeight(1)
          .onChange((v: number) => {
            const p = Math.max(0, Math.round(v) - 1);
            this.pageIndex = p;
            if (this.pageMode === 1) {
              this.scroller.scrollToIndex(p, false);
            }
          })
        Text(`${this.images.length}`)
          .fontSize(13)
          .fontColor('#99FFFFFF')
          .width(34)
          .textAlign(TextAlign.Start)
        // 强制刷新当前章节：与页码滑杆同属章节定位操作
        this.readerCircleButton($r('sys.symbol.arrow_clockwise'), true, (): void => {
          this.refreshChapter();
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 三个等宽操作位：上一章 / 切换模式 / 下一章
      Row({ space: 10 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(14)
            .fontColor([this.index > 0 ? '#FFFFFF' : '#66FFFFFF'])
          Text('上一章')
            .fontSize(13)
            .fontColor(this.index > 0 ? '#FFFFFF' : '#66FFFFFF')
        }
        .height(40)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .borderRadius(Theme.RADIUS_PILL)
        .backgroundColor(this.index > 0 ? '#14FFFFFF' : '#0DFFFFFF')
        .onClick(() => {
          this.switchChapter(-1);
        })

        Text(this.pageMode === 1 ? '切换翻页' : '切换条漫')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .height(40)
          .layoutWeight(1)
          .borderRadius(Theme.RADIUS_PILL)
          .backgroundColor('#14FFFFFF')
          .onClick(() => {
            this.setMode(this.pageMode === 1 ? 0 : 1);
          })

        Row({ space: 6 }) {
          Text('下一章')
            .fontSize(13)
            .fontColor(this.index < this.chapters.length - 1 ? '#FFFFFF' : '#66FFFFFF')
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([this.index < this.chapters.length - 1 ? '#FFFFFF' : '#66FFFFFF'])
        }
        .height(40)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .borderRadius(Theme.RADIUS_PILL)
        .backgroundColor(this.index < this.chapters.length - 1 ? '#14FFFFFF' : '#0DFFFFFF')
        .onClick(() => {
          this.switchChapter(1);
        })
      }
      .width('100%')
    }
    .padding({ left: 16, right: 16, top: 12, bottom: 14 + this.bottomInset })
    .backgroundColor('#99000000')
    .borderRadius({ topLeft: Theme.RADIUS_CARD, topRight: Theme.RADIUS_CARD })
    .backgroundBlurStyle(BlurStyle.Thin)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 48 }))
      .animation({ duration: 250, curve: Curve.EaseInOut }))
  }

  build() {
    NavDestination() {
      Stack() {
        // 沉浸式黑底：延伸绘制到状态栏/导航条区域，避免两处露出窗口白底
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#000000')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层
        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress().width(40).height(40).color('#888888')
            Text('解析章节图片…').fontSize(13).fontColor('#999999')
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        } else if (this.errorText.length > 0) {
          Column({ space: 10 }) {
            Text(`章节加载失败：${this.errorText}`).fontSize(13).fontColor('#CC0000')
            Button('重试').onClick(() => {
              this.loadChapter();
            })
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        } else if (this.images.length === 0) {
          Column() {
            Text('本章无图片').fontSize(14).fontColor('#999999')
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        } else if (this.pageMode === 0) {
          // 翻页模式
          Swiper() {
            ForEach(this.images, (img: ImageInfo, i: number) => {
              ReaderImage({
                url: img.url(),
                referer: this.referer,
                active: Math.abs(i - this.pageIndex) <= 2,
                onTap: (): void => {
                  this.toggleBars();
                }
              })
            }, (img: ImageInfo) => `${img.chapterId}_${img.num}`)
          }
          .index(this.pageIndex)
          .cachedCount(2)
          .loop(false)
          .indicator(false)
          .vertical(this.turnDirection === 2)
          .width('100%').height('100%')
          .backgroundColor('#000000')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .onChange((i: number) => {
            this.pageIndex = i;
            this.saveProgress();
          })
        } else {
          // 条漫模式：整章图片无缝拼接为一条纵向长流
          List({ space: 0, scroller: this.scroller }) {
            LazyForEach(this.streamSource, (img: ImageInfo) => {
              ListItem() {
                ReaderImage({
                  url: img.url(),
                  referer: this.referer,
                  stream: true,
                  active: true,
                  onTap: (): void => {
                    this.toggleBars();
                  }
                })
              }
            }, (img: ImageInfo) => `${img.chapterId}_${img.num}`)
          }
          .cachedCount(3)
          .width('100%').height('100%')
          .backgroundColor('#000000')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .onScrollIndex((start: number) => {
            if (start !== this.pageIndex) {
              this.pageIndex = start;
            }
          })
          .onScrollStop(() => {
            this.saveProgress();
          })
          .onReachEnd(() => {
            // 到底不自动切章：唤起工具栏，由用户决定是否进入下一章
            if (!this.showBars) {
              this.toggleBars();
            }
          })
        }

        // 工具栏（中间空白区点击隐藏）
        if (this.showBars) {
          Column() {
            this.topBar()
            Blank()
              .layoutWeight(1)
              .onClick(() => {
                this.showBars = false;
              })
            this.bottomBar()
          }
          .width('100%').height('100%')
        }
      }
      .width('100%').height('100%')
      .backgroundColor('#000000')
    }
    .hideTitleBar(true)
    .backgroundColor('#000000')
  }
}
