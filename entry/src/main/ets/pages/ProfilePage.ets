/** 我的页：分组卡片式阅读设置。 */

import { Prefs, PrefKeys } from '../data/Prefs';
import Theme from '../common/Theme';
import { SourceManager } from '../source/SourceManager';
import { SourceDao } from '../data/Daos';
import { ImageLoader } from '../image/ImageLoader';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

interface SettingRow {
  icon: Resource;
  iconBg: string;
  label: string;
}

@Component
export struct ProfilePage {
  @StorageLink('bottomInset') bottomInset: number = 0;
  @StorageLink('bp') bp: string = 'sm';
  @State readerMode: number = 1;
  @State turnDirection: number = 0;
  @State whiteEdge: boolean = false;
  @State preload: boolean = true;
  @State preloadCount: number = 2;
  @State keepOn: boolean = true;
  @State refreshing: boolean = false;
  @State sourceCount: number = 0;
  @State cacheText: string = '…';

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    Prefs.getInt(ctx, PrefKeys.READER_MODE, 1).then((v: number) => this.readerMode = v);
    Prefs.getInt(ctx, PrefKeys.READER_TURN_DIRECTION, 0).then((v: number) => this.turnDirection = v);
    Prefs.getBool(ctx, PrefKeys.READER_WHITE_EDGE, false).then((v: boolean) => this.whiteEdge = v);
    Prefs.getBool(ctx, PrefKeys.READER_PRELOAD, true).then((v: boolean) => this.preload = v);
    Prefs.getInt(ctx, PrefKeys.READER_PRELOAD_COUNT, 2).then((v: number) => this.preloadCount = v);
    Prefs.getBool(ctx, PrefKeys.READER_KEEP_ON, true).then((v: boolean) => this.keepOn = v);
    new SourceDao(ctx).list().then((list) => this.sourceCount = list.length);
    // 缓存大小遍历在工作线程执行，完成后回填，渲染路径零同步 IO
    ImageLoader.get(ctx).cacheSize().then((bytes: number) => {
      this.cacheText = this.formatSize(bytes);
    });
  }

  private save(key: string, value: number | boolean): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    if (typeof value === 'number') {
      Prefs.putInt(ctx, key, value);
    } else {
      Prefs.putBool(ctx, key, value);
    }
  }

  private formatSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`;
    }
    if (bytes < 1024 * 1024 * 1024) {
      return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
    }
    return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
  }

  private confirmClearCache(): void {
    AlertDialog.show({
      title: '清理缓存',
      message: '将清理已阅读漫画产生的图片缓存，手动下载的章节不会被清理。确定清理吗？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '清理',
        fontColor: Theme.DANGER,
        action: (): void => {
          this.clearCache();
        }
      }
    });
  }

  private clearCache(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    ImageLoader.get(ctx).clearCache().then((freed: number) => {
      this.cacheText = this.formatSize(freed);
      promptAction.showToast({ message: `已清理 ${this.formatSize(freed)}` });
    });
  }

  /** 导入外部图源目录前必须确认：外部目录可能滞后于内置源修复，误导入会让修复失效。 */
  private confirmRefreshCatalog(): void {
    AlertDialog.show({
      title: '更新图源配置',
      message: '将从图源仓库（Cimoc-Source）导入已验证图源目录，与内置目录合并。\n已删除的图源会随导入恢复，内置修复过的图源受保护，不会被覆盖。\n\n是否继续导入？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '确认导入',
        fontColor: Theme.ACCENT,
        action: (): void => {
          this.refreshCatalog();
        }
      }
    });
  }

  private refreshCatalog(): void {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    const ctx = getContext(this) as common.UIAbilityContext;
    SourceManager.get().refreshRemote(ctx)
      .then((ok: boolean) => {
        this.refreshing = false;
        this.sourceCount = SourceManager.get().catalogSourceInfos().length;
        promptAction.showToast({
          message: ok ? `图源配置已更新，共 ${this.sourceCount} 个图源` : '更新失败，请检查网络'
        });
      })
      .catch(() => {
        this.refreshing = false;
        promptAction.showToast({ message: '更新失败，请检查网络' });
      });
  }

  @Builder
  settingRow(icon: Resource, iconBg: string, label: string) {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph(icon)
          .fontSize(16)
          .fontColor(['#FFFFFF'])
      }
      .width(30)
      .height(30)
      .borderRadius(8)
      .backgroundColor(iconBg)
      .justifyContent(FlexAlign.Center)

      Text(label)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
    }
  }

  build() {
    Scroll() {
      Column() {
        // 规范标题栏：高 56vp，标题 20fp/Medium 靠左（全应用统一）
        Row() {
          Text('我的')
            .fontSize(28)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
        }
        .height(56)
        .width('100%')

        // 阅读偏好分组
        Column() {
          Row({ space: 12 }) {
            this.settingRow($r('sys.symbol.book_open_fill'), Theme.ACCENT, '阅读模式')
            Blank()
            Text(this.readerMode === 0 ? '翻页' : '条漫(卷纸)')
              .fontSize(14)
              .fontColor($r('sys.color.font_tertiary'))
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(13)
              .fontColor([$r('sys.color.font_fourth')])
          }
          .width('100%')
          .padding(Theme.PAD_CARD)
          .onClick(() => {
            this.readerMode = this.readerMode === 0 ? 1 : 0;
            this.save(PrefKeys.READER_MODE, this.readerMode);
          })

          Divider().color($r('sys.color.comp_divider')).margin({ left: 56 })

          Row({ space: 12 }) {
            this.settingRow($r('sys.symbol.arrow_counterclockwise'), '#AF52DE', '翻页方向')
            Blank()
            Text(this.turnDirection === 0 ? '从左到右' : (this.turnDirection === 1 ? '从右到左' : '从上到下'))
              .fontSize(14)
              .fontColor($r('sys.color.font_tertiary'))
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(13)
              .fontColor([$r('sys.color.font_fourth')])
          }
          .width('100%')
          .padding(Theme.PAD_CARD)
          .onClick(() => {
            this.turnDirection = (this.turnDirection + 1) % 3;
            this.save(PrefKeys.READER_TURN_DIRECTION, this.turnDirection);
          })

          Divider().color($r('sys.color.comp_divider')).margin({ left: 56 })

          Row({ space: 12 }) {
            this.settingRow($r('sys.symbol.download_fill'), Theme.WARNING, '预加载')
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.preload })
              .selectedColor(Theme.ACCENT)
              .onChange((on: boolean) => {
                this.preload = on;
                this.save(PrefKeys.READER_PRELOAD, on);
              })
          }
          .width('100%')
          .padding(Theme.PAD_CARD)

          Divider().color($r('sys.color.comp_divider')).margin({ left: 56 })

          Row({ space: 12 }) {
            this.settingRow($r('sys.symbol.eye'), '#5856D6', '预加载数量')
            Blank()
            Counter() {
              Text(`${this.preloadCount}`)
                .fontSize(14)
                .fontColor($r('sys.color.font_primary'))
            }
            .onInc(() => {
              this.preloadCount = Math.min(5, this.preloadCount + 1);
              this.save(PrefKeys.READER_PRELOAD_COUNT, this.preloadCount);
            })
            .onDec(() => {
              this.preloadCount = Math.max(1, this.preloadCount - 1);
              this.save(PrefKeys.READER_PRELOAD_COUNT, this.preloadCount);
            })
          }
          .width('100%')
          .padding(Theme.PAD_CARD)
        }
        .borderRadius(Theme.RADIUS_CARD)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .width('100%')

        // 显示与体验分组
        Column() {
          Row({ space: 12 }) {
            this.settingRow($r('sys.symbol.paintpalette'), '#8E8E93', '裁剪白边')
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.whiteEdge })
              .selectedColor(Theme.ACCENT)
              .onChange((on: boolean) => {
                this.whiteEdge = on;
                this.save(PrefKeys.READER_WHITE_EDGE, on);
              })
          }
          .width('100%')
          .padding(Theme.PAD_CARD)

          Divider().color($r('sys.color.comp_divider')).margin({ left: 56 })

          Row({ space: 12 }) {
            this.settingRow($r('sys.symbol.moon_fill'), '#5AC8FA', '屏幕常亮')
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.keepOn })
              .selectedColor(Theme.ACCENT)
              .onChange((on: boolean) => {
                this.keepOn = on;
                this.save(PrefKeys.READER_KEEP_ON, on);
              })
          }
          .width('100%')
          .padding(Theme.PAD_CARD)
        }
        .borderRadius(Theme.RADIUS_CARD)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .width('100%')
        .margin({ top: Theme.GAP_LIST })

        // 图源分组
        Column() {
          Row({ space: 12 }) {
            this.settingRow($r('sys.symbol.arrow_counterclockwise'), '#34C759', '图源配置')
            Blank()
            Text(this.refreshing ? '更新中…' : `${this.sourceCount} 个图源`)
              .fontSize(14)
              .fontColor($r('sys.color.font_tertiary'))
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(13)
              .fontColor([$r('sys.color.font_fourth')])
          }
          .width('100%')
          .padding(Theme.PAD_CARD)
          .onClick(() => {
            this.confirmRefreshCatalog();
          })
        }
        .borderRadius(Theme.RADIUS_CARD)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .width('100%')
        .margin({ top: Theme.GAP_LIST })

        // 缓存分组
        Column() {
          Row({ space: 12 }) {
            this.settingRow($r('sys.symbol.trash'), '#FF3B30', '清理缓存')
            Blank()
            Text(this.cacheText)
              .fontSize(14)
              .fontColor($r('sys.color.font_tertiary'))
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(13)
              .fontColor([$r('sys.color.font_fourth')])
          }
          .width('100%')
          .padding(Theme.PAD_CARD)
          .onClick(() => {
            this.confirmClearCache();
          })
        }
        .borderRadius(Theme.RADIUS_CARD)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .width('100%')
        .margin({ top: Theme.GAP_LIST })

        Text('Cimoc for HarmonyOS · 原生 ArkTS 移植版')
          .fontSize(11)
          .fontColor($r('sys.color.font_fourth'))
          .margin({ top: 24 })
          .width('100%')
          .textAlign(TextAlign.Center)

        Blank().height(Theme.floatTabBarAvoid(this.bottomInset))
      }
      .width('100%')
      // Scroll 对不足一屏的子组件默认垂直居中（标题被顶到半屏处）；
      // 撑满视口高度后内容始终从顶部排布
      .constraintSize({ minHeight: '100%' })
      .padding({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp) })
    }
    .height('100%')
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}
