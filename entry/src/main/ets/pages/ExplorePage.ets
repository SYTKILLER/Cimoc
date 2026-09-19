/** 发现页：漫画源管理（启用/停用/左滑删除）。 */

import { SourceInfo } from '../model/Model';
import { SourceDao } from '../data/Daos';
import Theme from '../common/Theme';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

@Component
export struct ExplorePage {
  @Consume('nav') navStack: NavPathStack;
  @StorageLink('bottomInset') bottomInset: number = 0;
  @StorageLink('bp') bp: string = 'sm';
  @State sources: SourceInfo[] = [];
  private sourceDao: SourceDao | null = null;

  aboutToAppear(): void {
    this.sourceDao = new SourceDao(getContext(this) as common.UIAbilityContext);
    this.reload();
  }

  reload(): void {
    const dao = this.sourceDao;
    if (dao === null) {
      return;
    }
    dao.list().then((list: SourceInfo[]) => {
      this.sources = list;
    });
  }

  /** 删除图源前必须确认：删除后源从列表彻底移除，避免滑动误触。 */
  confirmDelete(s: SourceInfo): void {
    AlertDialog.show({
      title: '删除图源',
      message: `确定删除图源「${s.title}」吗？\n删除后可在「我的」页更新图源配置找回。`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Theme.DANGER,
        action: (): void => {
          this.deleteSource(s);
        }
      }
    });
  }

  async deleteSource(s: SourceInfo): Promise<void> {
    if (this.sourceDao === null) {
      return;
    }
    await this.sourceDao.delete(s.type);
    promptAction.showToast({ message: `已删除「${s.title}」，更新图源配置可找回` });
    this.reload();
  }

  // 左滑露出的删除按钮
  @Builder
  deleteCell(s: SourceInfo) {
    Row() {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(20)
        .fontColor([Color.White])
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .borderRadius(Theme.RADIUS_ITEM)
    .backgroundColor(Theme.DANGER)
    .margin({ left: 8 })
    .onClick(() => {
      this.confirmDelete(s);
    })
  }

  build() {
    Column() {
      // 规范标题栏：高 56vp，标题 20fp/Medium 靠左（全应用统一）
      Row() {
        Text('发现')
          .fontSize(28)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
      }
      .height(56)
      .width('100%')
      .padding({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp) })

      Text('关闭的源不参与搜索，左滑可删除源')
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
        .padding({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp) })
        .margin({ bottom: 12 })
        .width('100%')

      List({ space: Theme.GAP_LIST }) {
        ForEach(this.sources, (s: SourceInfo) => {
          ListItem() {
            Row({ space: 12 }) {
              // 源图标：圆角方块 + 首字
              Text(s.title.substring(0, 1))
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .width(44)
                .height(44)
                .borderRadius(Theme.RADIUS_SMALL)
                .backgroundColor(s.enable ? Theme.ACCENT : $r('sys.color.font_fourth'))
                .textAlign(TextAlign.Center)
              Column({ space: 3 }) {
                Text(s.title)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_primary'))
                Text(s.enable ? '已启用' : '已停用')
                  .fontSize(11)
                  .fontColor($r('sys.color.font_tertiary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: s.enable })
                .selectedColor(Theme.ACCENT)
                .onChange((on: boolean) => {
                  if (this.sourceDao !== null) {
                    this.sourceDao.setEnable(s.type, on).then(() => this.reload());
                  }
                })
            }
            .width('100%')
            .padding(Theme.PAD_CARD)
            .borderRadius(Theme.RADIUS_ITEM)
            .backgroundColor($r('sys.color.comp_background_primary'))
          }
          .swipeAction({ end: this.deleteCell(s) })
        }, (s: SourceInfo) => `${s.type}_${s.enable ? 1 : 0}`)
      }
      .width('100%')
      .padding({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp) })
      .contentEndOffset(Theme.floatTabBarAvoid(this.bottomInset))
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .height('100%')
    .width('100%')
  }
}
