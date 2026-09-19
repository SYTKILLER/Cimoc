/** 搜索页：胶囊搜索框 + 历史标签 + 多源聚合结果卡片。 */

import { ComicService, SourceResult } from '../service/ComicService';
import { Comic } from '../model/Model';
import { Prefs } from '../data/Prefs';
import Theme from '../common/Theme';
import { common } from '@kit.AbilityKit';

@Component
export struct SearchPage {
  @Consume('nav') navStack: NavPathStack;
  @StorageLink('bottomInset') bottomInset: number = 0;
  @StorageLink('bp') bp: string = 'sm';
  @State keyword: string = '';
  @State results: Comic[] = [];
  @State resultTags: string[] = [];
  @State searching: boolean = false;
  @State statusText: string = '输入关键字搜索全部已启用源';
  @State history: string[] = [];
  private context: common.UIAbilityContext | null = null;

  aboutToAppear(): void {
    this.context = getContext(this) as common.UIAbilityContext;
    Prefs.getStringArray(this.context, 'pref_search_history').then((h: string[]) => {
      this.history = h;
    });
  }

  async doSearch(): Promise<void> {
    const kw = this.keyword.trim();
    if (kw.length === 0 || this.searching) {
      return;
    }
    this.searching = true;
    this.results = [];
    this.resultTags = [];
    this.statusText = '搜索中…';
    // 历史记录
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
    const service = ComicService.get(this.context as common.UIAbilityContext);
    const types = await service.enabledSourceTypes();
    if (types.length === 0) {
      this.statusText = '没有启用的源，请到「发现」页开启';
      this.searching = false;
      return;
    }
    const rs: SourceResult[] = await service.searchAll(kw, 1, types);
    const comics: Comic[] = [];
    const tags: string[] = [];
    const parts: string[] = [];
    for (const r of rs) {
      for (const c of r.comics) {
        comics.push(c);
        tags.push(r.title);
      }
      if (r.error.length > 0) {
        parts.push(`${r.title} 失败`);
      } else if (r.comics.length === 0) {
        parts.push(`${r.title} 0 条`);
      } else {
        parts.push(`${r.title} ${r.comics.length} 条`);
      }
    }
    this.results = comics;
    this.resultTags = tags;
    this.statusText = comics.length === 0
      ? `无结果（${parts.join(' · ')}）`
      : `共 ${comics.length} 条 · ${parts.join(' · ')}`;
    this.searching = false;
  }

  openDetail(comic: Comic): void {
    this.navStack.pushPathByName('detail', comic);
  }

  @Builder
  emptyState() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(44)
        .fontColor([$r('sys.color.font_fourth')])
      Text(this.statusText)
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .width('100%')
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
            this.doSearch();
          })
        Button('搜索')
          .type(ButtonType.Capsule)
          .height(34)
          .fontSize(14)
          .padding({ left: 18, right: 18 })
          .onClick(() => {
            this.doSearch();
          })
      }
      .padding({ left: 14, right: 6, top: 6, bottom: 6 })
      .borderRadius(Theme.RADIUS_PILL)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .margin({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp), top: 8 })

      // 历史标签
      if (this.history.length > 0 && this.results.length === 0 && !this.searching) {
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
              this.doSearch();
            })
          }, (h: string) => h)
        }
        .padding({ left: Theme.pagePad(this.bp) - 4, right: Theme.pagePad(this.bp) - 4, top: 8 })
        .width('100%')
      }

      if (this.results.length === 0 && !this.searching) {
        Text(this.statusText)
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
          .padding({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp) })
          .margin({ top: 10 })
          .width('100%')
      }

      if (this.searching) {
        Column({ space: 10 }) {
          LoadingProgress().width(36).height(36).color(Theme.ACCENT)
          Text('正在搜索全部已启用源…')
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else if (this.results.length === 0 && this.history.length === 0) {
        // 有历史标签时顶部状态行已显示同一文案，避免重复渲染空态
        this.emptyState()
      } else {
        List({ space: Theme.GAP_LIST }) {
          ForEach(this.results, (c: Comic, idx: number) => {
            ListItem() {
              Row({ space: 12 }) {
                Image(c.cover.length > 0 ? c.cover : undefined)
                  .width(58)
                  .height(78)
                  .borderRadius(Theme.RADIUS_SMALL)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .objectFit(ImageFit.Cover)
                Column({ space: 5 }) {
                  Text(c.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('sys.color.font_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(c.author.length > 0 ? c.author : '佚名')
                    .fontSize(12)
                    .fontColor($r('sys.color.font_tertiary'))
                    .maxLines(1)
                  Text(this.resultTags[idx] ?? '')
                    .fontSize(10)
                    .fontColor(Theme.ACCENT)
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .borderRadius(Theme.RADIUS_PILL)
                    .backgroundColor(Theme.ACCENT_SOFT)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([$r('sys.color.font_fourth')])
              }
              .padding(Theme.PAD_CARD)
              .borderRadius(Theme.RADIUS_ITEM)
              .backgroundColor($r('sys.color.comp_background_primary'))
              .onClick(() => {
                this.openDetail(c);
              })
            }
            .stateStyles({
              pressed: { .opacity(Theme.PRESS_OPACITY) },
              normal: { .opacity(1) }
            })
          }, (c: Comic, idx: number) => `${c.source}_${c.cid}_${idx}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp), top: 6 })
        .contentEndOffset(Theme.floatTabBarAvoid(this.bottomInset))
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .height('100%')
    .width('100%')
  }
}
