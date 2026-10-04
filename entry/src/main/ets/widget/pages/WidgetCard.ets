/**
 * 桌面「继续阅读」卡片（2×2）：全卡封面 + 底部渐变遮罩 + 左下文案（继续阅读/章节）+ 右下跳转符号。
 * 数据经 formImages（memory://）注入封面；整卡点击 router 回 EntryAbility 带 comicId 深跳阅读器。
 */

let storage = new LocalStorage();

@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('hasHistory') hasHistory: boolean = false;
  @LocalStorageProp('comicId') comicId: number = 0;
  @LocalStorageProp('chapter') chapter: string = '打开应用，开始阅读';
  @LocalStorageProp('loaded') loaded: boolean = false;
  @LocalStorageProp('imgName') imgName: string = '';

  /** 封面源：已加载走 memory://（formImages 注入），否则应用图标占位。 */
  private coverSrc(): string | Resource {
    return this.loaded ? `memory://${this.imgName}` : $r('app.media.startIcon');
  }

  /** 有历史带 comicId 深跳阅读器；空态仅打开应用。 */
  private cardParams(): Record<string, Object> {
    const p: Record<string, Object> = {};
    if (this.hasHistory && this.comicId > 0) {
      p['comicId'] = this.comicId;
    }
    return p;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 底部渐变遮罩：白字在任意封面/深浅色下可读
      Column()
        .width('100%')
        .height('48%')
        .linearGradient({
          angle: 180,
          colors: [['rgba(0, 0, 0, 0)', 0], ['rgba(0, 0, 0, 0.55)', 1]]
        })

      Row({ space: 6 }) {
        Column({ space: 2 }) {
          Text('继续阅读')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.chapter)
            .fontSize(11)
            .fontColor('#E6FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 与应用内「继续阅读」按钮同款符号（SymbolGlyph 自 API 12 起支持卡片）
        SymbolGlyph($r('sys.symbol.book_badge_play'))
          .fontSize(20)
          .fontColor(['#FFFFFF'])
      }
      .width('100%')
      .padding(10)
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .height('100%')
    .backgroundImage(this.coverSrc())
    .backgroundImageSize(ImageSize.Cover)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: this.cardParams()
      });
    })
  }
}
