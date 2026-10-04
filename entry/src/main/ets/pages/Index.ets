/** 应用主页：Navigation 根 + HDS 悬浮胶囊页签栏（参考 Pixark 的 UIDesignKit 用法）。 */

import { LibraryPage } from './LibraryPage';
import { LocalLibraryPage } from './LocalLibraryPage';
import { ExplorePage } from './ExplorePage';
import { SearchPage } from './SearchPage';
import { ProfilePage } from './ProfilePage';
import { DetailPage } from './DetailPage';
import { ReaderPage } from './ReaderPage';
import { SymbolGlyphModifier, window, curves } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { HoldingHandleUtil } from '../common/HoldingHandleUtil';
import { ComicDao, ChapterDao } from '../data/Daos';
import { ReaderArgs } from '../model/Model';

interface TabItem {
  title: string;
  normal: Resource;
  selected: Resource;
}

// 握持状态须稳定保持该时长才换边，过滤系统左右手判定抖动（holdingHandChanged 高频抖动会导致按钮左右横跳）
const HOLDING_STABLE_MS = 500;

@Entry
@Component
struct Index {
  @Provide('nav') navStack: NavPathStack = new NavPathStack();
  @StorageLink('topInset') topInset: number = 0;
  @StorageLink('bottomInset') bottomInset: number = 0;
  // EntryAbility 全屏切换完成后广播（insetEpoch 变化）：此刻的避让值才是新鲜值。
  // 启动时 Index 在 loadContent 期间就读过一次 insets（早于全屏生效），
  // 桥接系统上全屏后状态栏避让会归 0，不重读会导致主页顶部双重避让
  @StorageProp('insetEpoch') @Watch('onInsetEpoch') insetEpoch: number = 0;
  // 活动页签写入 AppStorage（'active_tab'）：TabContent 组件常驻不重建，
  // 各页签页靠 @StorageLink @Watch 感知"自己重新可见"以便每次进入都重载最新数据
  @StorageLink('active_tab') activeTab: number = 0;
  // 桌面「继续阅读」卡片深跳意图（EntryAbility 写入 comicId，0=无）：消费即清零防重复导航
  @StorageProp('pending_reader_intent') @Watch('onPendingIntent') pendingIntent: number = 0;
  private tabsController: HdsTabsController = new HdsTabsController();
  // 待生效的换边定时器（-1 表示无）
  private holdDebounceTimer: number = -1;

  private tabs: TabItem[] = [
    { title: '书库', normal: $r('sys.symbol.book'), selected: $r('sys.symbol.book_open_fill') },
    { title: '本地', normal: $r('sys.symbol.download'), selected: $r('sys.symbol.download_fill') },
    { title: '发现', normal: $r('sys.symbol.compass'), selected: $r('sys.symbol.square_fill_grid_2x2') },
    { title: '搜索', normal: $r('sys.symbol.magnifyingglass'), selected: $r('sys.symbol.curve_magnifyingglass') },
    { title: '我的', normal: $r('sys.symbol.person'), selected: $r('sys.symbol.person_fill') },
  ];

  aboutToAppear(): void {
    this.tabsController.changeIndex(this.activeTab);
    // 冷启动携带卡片深跳意图时 AppStorage 已先于本页写入（@Watch 不会触发），延后一拍等 Navigation 挂载再消费
    setTimeout(() => this.consumePendingIntent(), 0);
    // 智感握姿：订阅系统左右手握持事件（不支持的设备内部静默降级，按钮停在默认右下）
    HoldingHandleUtil.start((status: motion.HoldingHandStatus) => {
      this.handleHoldingStatusChange(status);
    });
    // 安全区内边距（vp）与窗口断点写入 AppStorage：悬浮页签 barBottomMargin、
    // 各页面避让与栅格列数都从这里取
    window.getLastWindow(getContext(this) as common.UIAbilityContext).then((w: window.Window) => {
      this.readInsets(w);
      this.readBreakpoint(w);
      w.on('avoidAreaChange', (): void => this.readInsets(w));
      w.on('windowSizeChange', (): void => this.readBreakpoint(w));
    });
  }

  private onPendingIntent(): void {
    this.consumePendingIntent();
  }

  /** 消费卡片深跳意图：查库重建 ReaderArgs 直达阅读器（ReaderPage 按 comic.last/page 自动恢复页码）。 */
  private consumePendingIntent(): void {
    const id = AppStorage.get<number>('pending_reader_intent');
    if (id === undefined || id <= 0) {
      return;
    }
    AppStorage.setOrCreate('pending_reader_intent', 0);
    const names = this.navStack.getAllPathName();
    if (names.length > 0 && names[names.length - 1] === 'reader') {
      return; // 已在阅读器，不重复压栈
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    new ComicDao(ctx).loadById(id).then((comic) => {
      if (comic === null) {
        return; // 漫画已删除：静默停在首页
      }
      if (comic.last.length === 0) {
        this.navStack.pushPathByName('detail', comic);
        return;
      }
      return new ChapterDao(ctx).list(comic.id).then((chapters) => {
        if (chapters.length === 0) {
          // 无章节记录（如仅收藏未打开过详情）：退回详情页拉取
          this.navStack.pushPathByName('detail', comic);
          return;
        }
        // 对齐 DetailPage.continueReading：记录章节已不存在时回退第一章
        let index = 0;
        for (let i = 0; i < chapters.length; i++) {
          if (chapters[i].path === comic.last) {
            index = i;
            break;
          }
        }
        this.navStack.pushPathByName('reader', new ReaderArgs(comic, chapters, index));
      });
    }).catch((e: Object) => {
      hilog.error(0x0000, 'Cimoc', 'card intent navigate failed: %{public}s', String(e));
    });
  }

  aboutToDisappear(): void {
    // 丢弃尚未生效的换边 + 停止握持订阅，防泄漏与销毁后误落位
    if (this.holdDebounceTimer !== -1) {
      clearTimeout(this.holdDebounceTimer);
      this.holdDebounceTimer = -1;
    }
    HoldingHandleUtil.stop();
  }

  private readInsets(w: window.Window): void {
    const sys = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const nav = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    const ui = this.getUIContext();
    AppStorage.setOrCreate('topInset', ui.px2vp(sys.topRect.height));
    AppStorage.setOrCreate('bottomInset', ui.px2vp(nav.bottomRect.height));
  }

  /** 全屏切换生效后重读安全区（EntryAbility 广播），替换启动早期的陈旧避让值。 */
  onInsetEpoch(): void {
    window.getLastWindow(getContext(this) as common.UIAbilityContext).then((w: window.Window) => {
      this.readInsets(w);
    });
  }

  private readBreakpoint(w: window.Window): void {
    const rect = w.getWindowProperties().windowRect;
    const widthVp = this.getUIContext().px2vp(rect.width);
    // 窗口高度（vp）写入 AppStorage：详情页侧边按钮的垂直定位按屏高百分比取值
    AppStorage.setOrCreate('winHVp', this.getUIContext().px2vp(rect.height));
    // 规范断点：<600 sm / 600–840 md / ≥840 lg
    const bp = widthVp >= 840 ? 'lg' : (widthVp >= 600 ? 'md' : 'sm');
    AppStorage.setOrCreate('bp', bp);
  }

  /**
   * 智感握姿策略层（全局唯一写入点）：握持状态 → 按钮落位。
   * 左手 → 2（左下），右手/未握持 → 0（右下默认位）；双手捧机最易误触发，保持原位不换边。
   * 写 AppStorage 'gripBtnPos'，消费页面（详情页侧边按钮）经 @StorageLink 自动响应刷新。
   */
  private handleHoldingStatusChange(status: motion.HoldingHandStatus): void {
    // 每个事件先取消未生效的换边：只有连续 HOLDING_STABLE_MS 保持不变的状态才落位
    if (this.holdDebounceTimer !== -1) {
      clearTimeout(this.holdDebounceTimer);
      this.holdDebounceTimer = -1;
    }
    let target = 0;
    switch (status) {
      case motion.HoldingHandStatus.LEFT_HAND_HELD:
        target = 2;
        break;
      case motion.HoldingHandStatus.BOTH_HANDS_HELD:
        return;
      case motion.HoldingHandStatus.RIGHT_HAND_HELD:
      case motion.HoldingHandStatus.NOT_HELD:
      default:
        target = 0;
        break;
    }
    if (target === (AppStorage.get<number>('gripBtnPos') ?? 0)) {
      return;
    }
    this.holdDebounceTimer = setTimeout(() => {
      this.holdDebounceTimer = -1;
      if (target === (AppStorage.get<number>('gripBtnPos') ?? 0)) {
        return;
      }
      // 动画包在状态赋值外面，消费页面靠 @StorageLink 自动获得弹簧换边过渡，页面侧零动画代码
      this.getUIContext().animateTo({ duration: 350, curve: curves.springMotion() }, () => {
        AppStorage.setOrCreate('gripBtnPos', target);
      });
    }, HOLDING_STABLE_MS);
  }

  @Builder
  PageMap(name: string) {
    // 'downloading' 走系统路由表（router_map.json → DownloadingPageBuilder），不在此注册
    if (name === 'detail') {
      DetailPage()
    } else if (name === 'reader') {
      ReaderPage()
    }
  }

  @Builder
  TabIcon(index: number) {
    SymbolGlyph(this.activeTab === index ? this.tabs[index].selected : this.tabs[index].normal)
      .fontSize(24)
      .fontColor([this.activeTab === index ? '#007DFF' : $r('sys.color.font_secondary')])
  }

  build() {
    Navigation(this.navStack) {
      HdsTabs({
        barPosition: BarPosition.End,
        controller: this.tabsController
      }) {
        TabContent() {
          LibraryPage()
        }
        .tabBar(new BottomTabBarStyle({
          normal: new SymbolGlyphModifier(this.tabs[0].normal).fontColor([$r('sys.color.font_secondary')]),
          selected: new SymbolGlyphModifier(this.tabs[0].selected).fontColor(['#007DFF'])
        }, this.tabs[0].title))

        TabContent() {
          LocalLibraryPage()
        }
        .tabBar(new BottomTabBarStyle({
          normal: new SymbolGlyphModifier(this.tabs[1].normal).fontColor([$r('sys.color.font_secondary')]),
          selected: new SymbolGlyphModifier(this.tabs[1].selected).fontColor(['#007DFF'])
        }, this.tabs[1].title))

        TabContent() {
          ExplorePage()
        }
        .tabBar(new BottomTabBarStyle({
          normal: new SymbolGlyphModifier(this.tabs[2].normal).fontColor([$r('sys.color.font_secondary')]),
          selected: new SymbolGlyphModifier(this.tabs[2].selected).fontColor(['#007DFF'])
        }, this.tabs[2].title))

        TabContent() {
          SearchPage()
        }
        .tabBar(new BottomTabBarStyle({
          normal: new SymbolGlyphModifier(this.tabs[3].normal).fontColor([$r('sys.color.font_secondary')]),
          selected: new SymbolGlyphModifier(this.tabs[3].selected).fontColor(['#007DFF'])
        }, this.tabs[3].title))

        TabContent() {
          ProfilePage()
        }
        .tabBar(new BottomTabBarStyle({
          normal: new SymbolGlyphModifier(this.tabs[4].normal).fontColor([$r('sys.color.font_secondary')]),
          selected: new SymbolGlyphModifier(this.tabs[4].selected).fontColor(['#007DFF'])
        }, this.tabs[4].title))
      }
      .zIndex(1)
      .barOverlap(true)
      .vertical(false)
      .barFloatingStyle({
        // 沉浸式下胶囊须避开底部导航条：直接用导航条高度（TYPE_NAVIGATION_INDICATOR，
        // avoidAreaChange 实时维护），取不到时 16vp 兜底；列表 contentEndOffset 用 floatTabBarAvoid 与此几何配套
        barBottomMargin: this.bottomInset > 0 ? this.bottomInset : 16,
        // HdsTabs 默认在页签区域叠加一层通栏白色渐变遮罩（默认高度 = 页签栏高 + 32vp），
        // 把划过栏下的内容洗成白色，看起来就是「白色遮罩挡住页面底部内容」。
        // 显式给透明色即可关闭；该字段不能省略——省略即恢复默认白色遮罩
        // （实测同一纯色内容在 y=2800、栏外 x=10 处由 #008001 变为 #B5D6B7）。
        gradientMask: { maskColor: Color.Transparent },
        adaptToHandedness: true,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .onTabBarClick((index: number) => {
        this.activeTab = index;
      })
      .onChange((index: number) => {
        this.activeTab = index;
      })
      .width('100%')
      .height('100%')
      // 顶部避让状态栏；底部不做整体 padding，避让交给各列表 contentEndOffset（内容穿过栏下）
      .padding({ top: this.topInset })
      // 兜底：setWindowLayoutFullScreen 未生效时仍把页签铺进上下安全区
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .navDestination(this.PageMap)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor($r('sys.color.background_primary'))
    // 主题底色铺到物理底缘：底部导航条区域不再露窗口底色（悬浮胶囊经 barBottomMargin 自行避开导航条）
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
