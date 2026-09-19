/** 书库页：收藏 / 历史。胶囊分段与 Swiper 双向联动。
 *  本地漫画管理已拆分至独立的"本地"页签（LocalLibraryPage），本页不涉及任何下载数据。 */

import { Comic } from '../model/Model';
import { ComicDao } from '../data/Daos';
import Theme from '../common/Theme';
import { common } from '@kit.AbilityKit';

@Component
export struct LibraryPage {
  @Consume('nav') navStack: NavPathStack;
  @StorageLink('bottomInset') bottomInset: number = 0;
  @StorageLink('bp') bp: string = 'sm';
  @State tab: number = 0;
  @State favComics: Comic[] = [];
  @State histComics: Comic[] = [];
  // 收藏/进度等数据在详情页、阅读器中变更时置脏，本页无论是否可见都立即重载
  @StorageLink('library_dirty') @Watch('onDirty') dirty: number = 0;
  private comicDao: ComicDao | null = null;
  private swiperController: SwiperController = new SwiperController();

  onDirty(): void {
    this.reload();
  }

  aboutToAppear(): void {
    this.comicDao = new ComicDao(getContext(this) as common.UIAbilityContext);
    this.reload();
  }

  reload(): void {
    const dao = this.comicDao;
    if (dao === null) {
      return;
    }
    dao.listFavorite().then((list: Comic[]) => {
      this.favComics = list;
    }).catch(() => {
      this.favComics = [];
    });
    dao.listHistory().then((list: Comic[]) => {
      this.histComics = list;
    }).catch(() => {
      this.histComics = [];
    });
  }

  openDetail(comic: Comic): void {
    const c = new Comic(comic.source, comic.cid, comic.title, comic.cover, comic.update, comic.author);
    c.id = comic.id;
    this.navStack.pushPathByName('detail', c);
  }

  @Builder
  emptyState(icon: Resource, message: string) {
    Column({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(52)
        .fontColor([$r('sys.color.font_fourth')])
      Text(message)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .width('100%')
  }

  @Builder
  comicCell(c: Comic) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        Image(c.cover.length > 0 ? c.cover : undefined)
          .width('100%')
          .height(150)
          .borderRadius(Theme.RADIUS_ITEM)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .objectFit(ImageFit.Cover)
        if (c.history > 0 && c.chapter.length > 0) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.clock'))
              .fontSize(11)
              .fontColor(['#FFFFFF'])
            Text(`${c.chapter} ${c.page > 0 ? `P${c.page}` : ''}`)
              .fontSize(10)
              .fontColor('#FFFFFF')
              .maxLines(1)
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(Theme.RADIUS_PILL)
          .backgroundColor('#66000000')
          .margin(6)
        }
        if (c.highlight) {
          Text('有更新')
            .fontSize(9)
            .fontColor('#FFFFFF')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(Theme.RADIUS_PILL)
            .backgroundColor(Theme.DANGER)
            .margin({ left: 6, bottom: 6 })
        }
      }
      Text(c.title)
        .fontSize(12)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(16)
        .height(32)
    }
    .onClick(() => {
      this.openDetail(c);
    })
  }

  @Builder
  comicGrid(comics: Comic[], keyPrefix: string) {
    Scroll() {
      Grid() {
        ForEach(comics, (c: Comic) => {
          GridItem() {
            this.comicCell(c)
          }
          .stateStyles({
            pressed: { .opacity(Theme.PRESS_OPACITY) },
            normal: { .opacity(1) }
          })
        }, (c: Comic) => `${keyPrefix}_${c.id}_${c.highlight ? 'h' : 'n'}_${c.page}`)
      }
      .columnsTemplate(Theme.coverCols(this.bp))
      .columnsGap(10)
      .rowsGap(14)
      .padding({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp), top: 8 })
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .contentEndOffset(Theme.floatTabBarAvoid(this.bottomInset))
  }

  build() {
    Column() {
      // 顶部：规范标题栏（56vp，标题 28fp/Medium 居左）+ 胶囊分段选择（点击切换 Swiper，滑动时随 onChange 回亮）
      Row() {
        Text('书库')
          .fontSize(28)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Row({ space: 4 }) {
          ForEach(['收藏', '历史'], (label: string, idx: number) => {
            Text(label)
              .fontSize(13)
              .fontColor(this.tab === idx ? '#FFFFFF' : $r('sys.color.font_secondary'))
              .fontWeight(this.tab === idx ? FontWeight.Medium : FontWeight.Normal)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .borderRadius(Theme.RADIUS_PILL)
              .backgroundColor(this.tab === idx ? Theme.ACCENT : Color.Transparent)
              .animation({ duration: Theme.ANIM_FAST, curve: Curve.Ease })
              .onClick(() => {
                if (this.tab !== idx) {
                  this.tab = idx;
                  this.reload();
                }
              })
          }, (label: string) => label)
        }
        .padding(3)
        .borderRadius(Theme.RADIUS_PILL)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
      }
      .padding({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp) })
      .height(56)
      .width('100%')

      Swiper(this.swiperController) {
        // 收藏
        Column() {
          if (this.favComics.length === 0) {
            this.emptyState($r('sys.symbol.heart'), '还没有收藏的漫画\n去搜索页找一本吧')
          } else {
            this.comicGrid(this.favComics, 'fav')
          }
        }
        .width('100%')
        .height('100%')

        // 历史
        Column() {
          if (this.histComics.length === 0) {
            this.emptyState($r('sys.symbol.clock'), '暂无阅读记录')
          } else {
            this.comicGrid(this.histComics, 'hist')
          }
        }
        .width('100%')
        .height('100%')
      }
      .index(this.tab)
      .loop(false)
      .indicator(false)
      .duration(300)
      .nestedScroll(SwiperNestedScrollMode.SELF_FIRST)
      .onChange((idx: number) => {
        if (idx !== this.tab) {
          this.tab = idx;
          this.reload();
        }
      })
      .layoutWeight(1)
      .width('100%')
    }
    .height('100%')
    .width('100%')
  }
}
