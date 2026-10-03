/**
 * 次级页通用标题栏：替代 NavDestination 内置标题。
 * 为什么不用内置 .title()：全屏窗口下内置标题栏的顶部避让依赖系统实现——
 * 模拟器上 HDS StatusBarBridge 会把整页推到状态栏下（避让已由桥接做好），
 * 真机上不做（标题顶进状态栏）。本组件统一用 AppStorage 'topInset'
 * （EntryAbility 在全屏切换完成后广播刷新的新鲜值）补差：
 * 框架已避让（topInset=0）时只留 8vp 呼吸；未避让（topInset=状态栏高）时补足，
 * 两类系统上标题落点一致（状态栏下方 8vp）。
 */
import Theme from './Theme';

@Component
export struct PageTitleBar {
  /** @Prop：详情页等场景标题在加载后才回填（@State 变化），需要同步刷新 */
  @Prop title: string = '';
  /** 返回动作（一般传 navStack.pop(true)；页面自行持栈，规避 @Consume 直传限制） */
  onBack: () => void = (): void => {};
  /** 右侧菜单图标（可选） */
  menuIcon: Resource | null = null;
  onMenu: () => void = (): void => {};

  @StorageProp('topInset') topInset: number = 0;

  build() {
    Row({ space: 8 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
      }
      .width(40)
      .height(40)
      .borderRadius(Theme.RADIUS_PILL)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.onBack();
      })

      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (this.menuIcon !== null) {
        Row() {
          SymbolGlyph(this.menuIcon)
            .fontSize(22)
            .fontColor([$r('sys.color.font_primary')])
        }
        .width(40)
        .height(40)
        .borderRadius(Theme.RADIUS_PILL)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.onMenu();
        })
      }
    }
    .padding({ left: 16, right: 16, top: 8 + this.topInset, bottom: 8 })
    .width('100%')
  }
}
