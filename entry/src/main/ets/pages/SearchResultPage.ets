/** 二级搜索页：多源聚合搜索结果。系统路由表注册（router_map.json → SearchResultPageBuilder）。
 *  标题栏选项按钮弹出半模态面板（bindSheet）勾选参与搜索的源，勾选默认跟随「发现」页开关，
 *  面板关闭后勾选有变化才重搜；Navigation 标准入口：onReady 取 NavPathStack 与路由参数。 */

import { ComicService, SourceResult } from '../service/ComicService';
import { Comic, SourceInfo } from '../model/Model';
import { SourceDao } from '../data/Daos';
import { Prefs, PrefKeys } from '../data/Prefs';
import { FuzzyMatcher } from '../common/FuzzyMatcher';
import Theme from '../common/Theme';
import { PageTitleBar } from '../common/PageTitleBar';
import { common } from '@kit.AbilityKit';

/** 带匹配度的结果条目：本地排序的中间结构。 */
class ScoredItem {
  readonly comic: Comic;
  readonly tag: string;
  // 排序前可被 ranked 源 clamp 改写
  score: number;
  // 聚合原序（同分稳定排序兜底，不依赖引擎排序稳定性）
  readonly order: number;

  constructor(comic: Comic, tag: string, score: number, order: number) {
    this.comic = comic;
    this.tag = tag;
    this.score = score;
    this.order = order;
  }
}

/** 系统路由表入口（router_map.json → SearchResultPageBuilder）。 */
@Builder
export function SearchResultPageBuilder() {
  SearchResultPage()
}

@Component
export struct SearchResultPage {
  @StorageLink('bottomInset') bottomInset: number = 0;
  @StorageLink('bp') bp: string = 'sm';
  private pathStack: NavPathStack | null = null;
  private context: common.UIAbilityContext | null = null;
  @State keyword: string = '';
  @State results: Comic[] = [];
  @State resultTags: string[] = [];
  @State searching: boolean = false;
  @State statusText: string = '输入关键字搜索';
  // 全部源 + 逐项勾选态（与 sources 下标一一对应），默认跟随「发现」页开关
  @State sources: SourceInfo[] = [];
  @State checked: boolean[] = [];
  @State sheetShow: boolean = false;
  // 上次实际参与搜索的源 type（SourceDao 按 TYPE 升序返回，顺序稳定可直接对比）
  private lastSearchedTypes: number[] = [];

  aboutToAppear(): void {
    this.context = getContext(this) as common.UIAbilityContext;
  }

  openDetail(comic: Comic): void {
    if (this.pathStack !== null) {
      this.pathStack.pushPathByName('detail', comic);
    }
  }

  /** 加载全部源并按「发现」页开关初始化勾选。 */
  async initSources(): Promise<void> {
    const ctx = this.context;
    if (ctx === null) {
      return;
    }
    const list: SourceInfo[] = await new SourceDao(ctx).list();
    const checks: boolean[] = [];
    for (const s of list) {
      checks.push(s.enable);
    }
    this.sources = list;
    this.checked = checks;
  }

  selectedTypes(): number[] {
    const out: number[] = [];
    for (let i = 0; i < this.sources.length; i++) {
      if (i < this.checked.length && this.checked[i]) {
        out.push(this.sources[i].type);
      }
    }
    return out;
  }

  checkedCount(): number {
    let n = 0;
    for (const c of this.checked) {
      if (c) {
        n++;
      }
    }
    return n;
  }

  async doSearch(): Promise<void> {
    const kw = this.keyword.trim();
    if (kw.length === 0 || this.searching || this.context === null) {
      return;
    }
    const types = this.selectedTypes();
    this.lastSearchedTypes = types;
    this.results = [];
    this.resultTags = [];
    if (types.length === 0) {
      this.statusText = '未勾选任何搜索源，点右上角可选源';
      return;
    }
    this.searching = true;
    this.statusText = '搜索中…';
    const service = ComicService.get(this.context);
    const rs: SourceResult[] = await service.searchAll(kw, 1, types);
    const hideLow: boolean = await Prefs.getBool(this.context, PrefKeys.SEARCH_HIDE_LOW_QUALITY, false);
    // 本地相关度排序：按关键词 vs 书名模糊打分；searchRanked 源（包子漫画）
    // 站内已按相关度排序，分数夹成非递增序列以保持其内部顺序，再与其他源混合排序
    const items: ScoredItem[] = [];
    const parts: string[] = [];
    for (const r of rs) {
      // 逐源打分（保持站点原序，order 为全局聚合序号，同分时兜底稳定）
      let scored: ScoredItem[] = [];
      for (const c of r.comics) {
        scored.push(new ScoredItem(c, r.title, FuzzyMatcher.score(kw, c.title), items.length + scored.length));
      }
      if (hideLow) {
        // 低匹配结果直接丢弃，不参与排序；每源最多保留匹配度最高的 3 条
        scored = scored.filter((it: ScoredItem): boolean => it.score >= FuzzyMatcher.LOW_QUALITY_THRESHOLD);
        if (scored.length > FuzzyMatcher.MAX_PER_SOURCE) {
          scored.sort((a: ScoredItem, b: ScoredItem): number => b.score - a.score || a.order - b.order);
          scored = scored.slice(0, FuzzyMatcher.MAX_PER_SOURCE);
          // 回到站点原序再做 ranked clamp
          scored.sort((a: ScoredItem, b: ScoredItem): number => a.order - b.order);
        }
      }
      let prev = Number.MAX_VALUE;
      for (const it of scored) {
        if (r.ranked && it.score > prev) {
          it.score = prev;
        }
        prev = it.score;
        items.push(it);
      }
      if (r.error.length > 0) {
        parts.push(`${r.title} 失败`);
      } else {
        parts.push(`${r.title} ${scored.length} 条`);
      }
    }
    // 分数降序；同分按聚合原序（order 兜底），确保最前面一定是匹配度最高的
    items.sort((a: ScoredItem, b: ScoredItem): number => b.score - a.score || a.order - b.order);
    const comics: Comic[] = [];
    const tags: string[] = [];
    for (const it of items) {
      comics.push(it.comic);
      tags.push(it.tag);
    }
    this.results = comics;
    this.resultTags = tags;
    this.statusText = comics.length === 0
      ? `无结果（${parts.join(' · ')}）`
      : `共 ${comics.length} 条 · ${parts.join(' · ')}`;
    this.searching = false;
  }

  /** 面板关闭后对比勾选：有变化才重搜，避免无意义请求。 */
  applySelectionOnSheetClose(): void {
    const now = this.selectedTypes();
    const old = this.lastSearchedTypes;
    if (now.length !== old.length) {
      this.doSearch();
      return;
    }
    for (let i = 0; i < now.length; i++) {
      if (now[i] !== old[i]) {
        this.doSearch();
        return;
      }
    }
  }

  /** 半模态源勾选面板：勾选即时生效，关闭（或点确定）时统一对比重搜。 */
  @Builder
  sourceSheetBuilder() {
    Column() {
      Text('参与搜索的源')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
      Text(`默认跟随「发现」页开关 · 已选 ${this.checkedCount()} 个`)
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ top: 4 })

      List({ space: 4 }) {
        ForEach(this.sources, (s: SourceInfo, idx: number) => {
          ListItem() {
            Row({ space: 12 }) {
              Checkbox({ name: s.title })
                .select(this.checked[idx])
                .selectedColor(Theme.ACCENT)
                .onChange((on: boolean) => {
                  this.checked[idx] = on;
                })
              Text(s.title.substring(0, 1))
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .width(40)
                .height(40)
                .borderRadius(Theme.RADIUS_SMALL)
                .backgroundColor(this.checked[idx] ? Theme.ACCENT : $r('sys.color.font_fourth'))
                .textAlign(TextAlign.Center)
              Column({ space: 2 }) {
                Text(s.title)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary'))
                Text(s.enable ? '发现页已启用' : '发现页已停用')
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .borderRadius(Theme.RADIUS_ITEM)
            .onClick(() => {
              this.checked[idx] = !this.checked[idx];
            })
          }
        }, (s: SourceInfo) => `${s.type}`)
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 10 })
      .scrollBar(BarState.Off)

      Button('确定')
        .type(ButtonType.Capsule)
        .width('100%')
        .height(40)
        .fontSize(15)
        .backgroundColor(Theme.ACCENT)
        .margin({ top: 12 })
        .onClick(() => {
          this.sheetShow = false;
        })
    }
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
    .width('100%')
    .height('100%')
  }

  build() {
    NavDestination() {
      Column() {
        // 自定义标题栏：内置标题栏在真机全屏下不避让状态栏（模拟器由 HDS 桥接兜底），
        // 菜单按钮（勾选参与搜索的源）一并挪进来
        PageTitleBar({
          title: '搜索结果',
          onBack: (): void => {
            if (this.pathStack !== null) {
              this.pathStack.pop(true);
            }
          },
          menuIcon: $r('sys.symbol.slider_horizontal_2'),
          onMenu: (): void => {
            this.sheetShow = true;
          }
        })
        // 搜索框：回车或点按钮按当前勾选的源重搜
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
        .margin({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp), top: 4 })

        if (this.searching) {
          Column({ space: 10 }) {
            LoadingProgress().width(36).height(36).color(Theme.ACCENT)
            Text(`正在搜索 ${this.checkedCount()} 个已选源…`)
              .fontSize(12)
              .fontColor($r('sys.color.font_tertiary'))
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .width('100%')
        } else if (this.results.length === 0) {
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
        } else {
          // 状态行 + 结果卡片
          Text(this.statusText)
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
            .padding({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp) })
            .margin({ top: 10 })
            .maxLines(2)
            .width('100%')

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
      .bindSheet(this.sheetShow, this.sourceSheetBuilder(), {
        height: SheetSize.MEDIUM,
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: true,
        showClose: true,
        onDisappear: (): void => {
          this.sheetShow = false;
          this.applySelectionOnSheetClose();
        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor($r('sys.color.background_primary'))
    .onReady((ctx: NavDestinationContext) => {
      // Navigation 标准入口：ctx.pathStack 拿导航控制器，ctx.pathInfo.param 拿路由参数（搜索关键字）
      this.pathStack = ctx.pathStack;
      const p = ctx.pathInfo.param as Object;
      if (typeof p === 'string' && p.length > 0) {
        this.keyword = p;
      }
      this.initSources().then((): void => {
        this.doSearch();
      });
    })
  }
}
