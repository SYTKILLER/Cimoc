/** 搜索入口页（Tab 首页）：胶囊搜索框 + 历史标签。
 *  发起搜索即跳转二级搜索页（系统路由表 searchresult），聚合搜索与搜索源勾选都在二级页完成。 */

import { Prefs } from '../data/Prefs';
import Theme from '../common/Theme';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { extractUrl, resolveLink } from '../common/LinkResolver';

@Component
export struct SearchPage {
  @Consume('nav') navStack: NavPathStack;
  @StorageLink('bp') bp: string = 'sm';
  @State keyword: string = '';
  @State history: string[] = [];
  private context: common.UIAbilityContext | null = null;

  aboutToAppear(): void {
    this.context = getContext(this) as common.UIAbilityContext;
    Prefs.getStringArray(this.context, 'pref_search_history').then((h: string[]) => {
      this.history = h;
    });
  }

  /** 发起搜索：含链接时先尝试识别成漫画直达详情页（链接导入，不落搜索历史）；
   *  识别不了再按关键字走二级搜索页。 */
  async startSearch(): Promise<void> {
    const kw = this.keyword.trim();
    if (kw.length === 0) {
      return;
    }
    const url = extractUrl(kw);
    if (url.length > 0 && this.context !== null) {
      const comic = await resolveLink(this.context, url);
      if (comic !== null) {
        this.navStack.pushPathByName('detail', comic);
        return;
      }
      promptAction.showToast({ message: '未识别到支持的漫画链接，已按关键字搜索' });
    }
    this.saveHistory(kw);
    this.navStack.pushPathByName('searchresult', kw);
  }

  private saveHistory(kw: string): void {
    const h: string[] = [kw];
    for (const old of this.history) {
      if (old !== kw && h.length < 10) {
        h.push(old);
      }
    }
    this.history = h;
    if (this.context !== null) {
      Prefs.putStringArray(this.context, 'pref_search_history', h);
    }
  }

  build() {
    Column() {
      // 规范标题栏：高 56vp，标题 20fp/Medium 靠左（全应用统一）
      Row() {
        Text('搜索')
          .fontSize(28)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
      }
      .height(56)
      .width('100%')
      .padding({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp) })

      // 胶囊搜索框
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([$r('sys.color.font_tertiary')])
        TextInput({ text: this.keyword, placeholder: '漫画名 / 作者' })
          .layoutWeight(1)
          .height(40)
          .backgroundColor(Color.Transparent)
          .placeholderColor($r('sys.color.font_fourth'))
          .fontSize(15)
          .onChange((v: string) => {
            this.keyword = v;
          })
          .onSubmit(() => {
            this.startSearch();
          })
        Button('搜索')
          .type(ButtonType.Capsule)
          .height(34)
          .fontSize(14)
          .padding({ left: 18, right: 18 })
          .onClick(() => {
            this.startSearch();
          })
      }
      .padding({ left: 14, right: 6, top: 6, bottom: 6 })
      .borderRadius(Theme.RADIUS_PILL)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .margin({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp), top: 8 })

      // 历史标签
      if (this.history.length > 0) {
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          ForEach(this.history, (h: string) => {
            Row({ space: 5 }) {
              SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
                .fontSize(12)
                .fontColor([$r('sys.color.font_tertiary')])
              Text(h)
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
            }
            .padding({ left: 13, right: 13, top: 7, bottom: 7 })
            .borderRadius(Theme.RADIUS_PILL)
            .backgroundColor($r('sys.color.comp_background_primary'))
            .margin(4)
            .onClick(() => {
              this.keyword = h;
              this.startSearch();
            })
          }, (h: string) => h)
        }
        .padding({ left: Theme.pagePad(this.bp) - 4, right: Theme.pagePad(this.bp) - 4, top: 8 })
        .width('100%')
      } else {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(44)
            .fontColor([$r('sys.color.font_fourth')])
          Text('输入漫画名开始搜索\n搜索结果页右上角可选择参与搜索的源')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      }
    }
    .height('100%')
    .width('100%')
  }
}
