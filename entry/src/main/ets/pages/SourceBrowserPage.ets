/** 源站浏览器：发现页点击源进入，ArkWeb 打开源站首页；
 *  主框架加载命中源详情页 URL 规则时拦截跳转，改入原生详情页（history 语义保持：
 *  真正点开章节才由 DetailPage 记历史），返回键回到网页继续浏览。
 *  Navigation 架构：系统路由表注册，onReady 标准入口取 NavPathStack 与路由参数，
 *  标题栏用 PageTitleBar 自定义样式（与其他二级页一致），网页后退优先于页面退出。 */

import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Comic, SourceInfo } from '../model/Model';
import { SourceManager } from '../source/SourceManager';
import { GenericHtmlParser } from '../source/SourceConfig';
import { HttpClient } from '../network/HttpClient';
import { HtmlNode } from '../html/HtmlNode';
import { matchWebDetail, detailNeedsValidate } from '../common/WebDetailRules';
import { PageTitleBar } from '../common/PageTitleBar';
import Theme from '../common/Theme';

const DOMAIN = 0x0000;

/** 系统路由表入口（router_map.json → SourceBrowserPageBuilder）。 */
@Builder
export function SourceBrowserPageBuilder() {
  SourceBrowserPage()
}

@Component
export struct SourceBrowserPage {
  @State pageTitle: string = '源站';
  @State progress: number = 100;
  // onReady 时按源配置赋值；ready 后才创建 Web（保证初始 src 就是源站首页）
  @State baseUrl: string = '';
  @State ready: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private pathStack: NavPathStack | null = null;
  private sourceType: number = 0;
  private sourceKey: string = '';
  // 验证不过放行网页继续加载时记录目标 URL：下一次同 URL 拦截直接放行，避免"拦→放→再拦"死循环
  private bypassUrl: string = '';

  /** 网页能后退先退网页，不能退返回 false 交出页面退出。 */
  private goWebBack(): boolean {
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        return true;
      }
    } catch (e) {
      // Web 未初始化（配置缺失兜底态），交出页面退出
    }
    return false;
  }

  private openDetail(cid: string): void {
    if (this.pathStack === null) {
      return;
    }
    this.pathStack.pushPathByName('detail', new Comic(this.sourceType, cid, ''));
  }

  /**
   * URL 有歧义的源（如漫本分类页与详情页同为 /mh-{slug}/）：先按该源 parseInfoTitle
   * 选择器拉 HTML 验证确是详情页才跳原生；验证不过放行网页继续加载。
   */
  private async validateThenOpen(cid: string, url: string): Promise<void> {
    const cfg = SourceManager.get().getConfig(this.sourceType);
    let ok = false;
    if (cfg !== null && cfg.parseInfoTitle.length > 0) {
      try {
        const p = SourceManager.get().getParser(this.sourceType);
        const headers = p instanceof GenericHtmlParser ? p.getHeader() : null;
        const html = await HttpClient.get().fetchText(this.baseUrl + cid, headers);
        const title = HtmlNode.parse(html).textOf(cfg.parseInfoTitle);
        ok = title !== null && title.length > 0;
      } catch (e) {
        ok = false;
      }
    }
    if (ok) {
      this.openDetail(cid);
      return;
    }
    this.bypassUrl = url;
    try {
      this.controller.loadUrl(url);
    } catch (e) {
      hilog.error(DOMAIN, 'Cimoc', 'browser reload after validate failed. Cause: %{public}s', String(e));
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 自定义标题栏：内置标题栏在真机全屏下不避让状态栏（模拟器由 HDS 桥接兜底）；
        // 返回键语义与系统返回一致：网页能退先退网页，不能退再退出页面
        PageTitleBar({
          title: this.pageTitle,
          onBack: (): void => {
            if (!this.goWebBack() && this.pathStack !== null) {
              this.pathStack.pop(true);
            }
          }
        })
        // 顶部加载进度线：加载中可见，满 100 隐藏
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color(Theme.ACCENT)
          .style({ strokeWidth: 2 })
          .visibility(this.progress < 100 ? Visibility.Visible : Visibility.None)

        if (this.ready) {
          Web({ src: this.baseUrl, controller: this.controller })
            .width('100%')
            .layoutWeight(1)
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .multiWindowAccess(true)
            .darkMode(WebDarkMode.Auto)
            .onLoadIntercept((event: OnLoadInterceptEvent) => {
              if (!event.data.isMainFrame()) {
                return false;
              }
              const url = event.data.getRequestUrl();
              if (url === this.bypassUrl) {
                this.bypassUrl = '';
                return false;
              }
              const cid = matchWebDetail(this.sourceKey, this.baseUrl, url);
              if (cid.length === 0) {
                return false;
              }
              hilog.info(DOMAIN, 'Cimoc', 'browser intercept detail: %{public}s', url);
              if (detailNeedsValidate(this.sourceKey)) {
                this.validateThenOpen(cid, url);
              } else {
                this.openDetail(cid);
              }
              return true;
            })
            .onWindowNew((event: OnWindowNewEvent) => {
              // target=_blank / window.open 都不开新窗：目标地址交给当前 Web 加载
              if (!event.isAlert && event.targetUrl.length > 0) {
                try {
                  this.controller.loadUrl(event.targetUrl);
                } catch (e) {
                  hilog.error(DOMAIN, 'Cimoc', 'browser open new-window url failed. Cause: %{public}s', String(e));
                }
              }
              event.handler.setWebController(null);
            })
            .onProgressChange((event: OnProgressChangeEvent) => {
              this.progress = event.newProgress;
            })
        } else {
          // 源配置缺失兜底（如浏览期间源被删除）
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.compass'))
              .fontSize(48)
              .fontColor([$r('sys.color.font_fourth')])
            Text('未找到该源的站点配置')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor($r('sys.color.background_primary'))
    .onReady((ctx: NavDestinationContext) => {
      // Navigation 标准入口：ctx.pathStack 拿导航控制器，ctx.pathInfo.param 拿路由参数
      this.pathStack = ctx.pathStack;
      const p = ctx.pathInfo.param as Object;
      if (p instanceof SourceInfo) {
        this.sourceType = p.type;
        this.pageTitle = p.title;
        const cfg = SourceManager.get().getConfig(p.type);
        this.sourceKey = cfg !== null ? cfg.key : '';
        this.baseUrl = cfg !== null ? cfg.baseUrl : '';
        this.ready = this.baseUrl.length > 0;
      }
    })
    .onBackPressed(() => {
      return this.goWebBack();
    })
  }
}
