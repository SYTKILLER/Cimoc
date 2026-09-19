/** 应用主页：Navigation 根 + HDS 悬浮胶囊页签栏（参考 Pixark 的 UIDesignKit 用法）。 */

import { LibraryPage } from './LibraryPage';
import { LocalLibraryPage } from './LocalLibraryPage';
import { ExplorePage } from './ExplorePage';
import { SearchPage } from './SearchPage';
import { ProfilePage } from './ProfilePage';
import { DetailPage } from './DetailPage';
import { ReaderPage } from './ReaderPage';
import { SymbolGlyphModifier, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';

interface TabItem {
  title: string;
  normal: Resource;
  selected: Resource;
}

@Entry
@Component
struct Index {
  @Provide('nav') navStack: NavPathStack = new NavPathStack();
  @StorageLink('topInset') topInset: number = 0;
  @StorageLink('bottomInset') bottomInset: number = 0;
  @State activeTab: number = 0;
  private tabsController: HdsTabsController = new HdsTabsController();

  private tabs: TabItem[] = [
    { title: '书库', normal: $r('sys.symbol.book'), selected: $r('sys.symbol.book_open_fill') },
    { title: '本地', normal: $r('sys.symbol.download'), selected: $r('sys.symbol.download_fill') },
    { title: '发现', normal: $r('sys.symbol.compass'), selected: $r('sys.symbol.square_fill_grid_2x2') },
    { title: '搜索', normal: $r('sys.symbol.magnifyingglass'), selected: $r('sys.symbol.curve_magnifyingglass') },
    { title: '我的', normal: $r('sys.symbol.person'), selected: $r('sys.symbol.person_fill') },
  ];

  aboutToAppear(): void {
    this.tabsController.changeIndex(this.activeTab);
    // 安全区内边距（vp）与窗口断点写入 AppStorage：悬浮页签 barBottomMargin、
    // 各页面避让与栅格列数都从这里取
    window.getLastWindow(getContext(this) as common.UIAbilityContext).then((w: window.Window) => {
      this.readInsets(w);
      this.readBreakpoint(w);
      w.on('avoidAreaChange', (): void => this.readInsets(w));
      w.on('windowSizeChange', (): void => this.readBreakpoint(w));
    });
  }

  private readInsets(w: window.Window): void {
    const sys = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const nav = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    const ui = this.getUIContext();
    AppStorage.setOrCreate('topInset', ui.px2vp(sys.topRect.height));
    AppStorage.setOrCreate('bottomInset', ui.px2vp(nav.bottomRect.height));
  }

  private readBreakpoint(w: window.Window): void {
    const widthVp = this.getUIContext().px2vp(w.getWindowProperties().windowRect.width);
    // 规范断点：<600 sm / 600–840 md / ≥840 lg
    const bp = widthVp >= 840 ? 'lg' : (widthVp >= 600 ? 'md' : 'sm');
    AppStorage.setOrCreate('bp', bp);
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
        // 贴近屏幕底部：固定小边距（沉浸式下内容本就画到物理底缘，不需要整体抬到导航条上方）
        barBottomMargin: 8,
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
    }
    .navDestination(this.PageMap)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor($r('sys.color.background_primary'))
  }
}
