import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { AppBootstrap } from '../app/AppBootstrap';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  // 主窗口引用：onConfigurationUpdate / avoidAreaChange 重放沉浸设置用
  private mainWin: window.Window | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // ArkWeb 引擎前置初始化（使用 Web 组件前建议调用，幂等）
    webview.WebviewController.initializeWebEngine();
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'Cimoc', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    AppBootstrap.init(this.context).then(() => {
      hilog.info(DOMAIN, 'Cimoc', 'bootstrap done');
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'Cimoc', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      // 全应用统一沉浸式：窗口内容画满整屏，状态栏/导航条区域由页面主题底色铺满，
      // 各页面避让交给各自的 padding / contentEndOffset（阅读器不再需要进出切换布局）。
      // 窗口底色兜底取 sys.color.background_primary：即使某瞬间页面未铺满也不露异色。
      try {
        const mainWin = windowStage.getMainWindowSync();
        this.mainWin = mainWin;
        this.applyImmersiveMode();
        // 三键/手势切换、分屏等改变避让区的场景里保持沉浸不变量
        mainWin.on('avoidAreaChange', (): void => this.applyImmersiveMode());
      } catch (e) {
        hilog.error(DOMAIN, 'Cimoc', 'Failed to apply immersive mode. Cause: %{public}s', JSON.stringify(e));
      }
    });
  }

  /** 全屏布局 + 主题底色兜底；可重复调用（幂等）。 */
  private applyImmersiveMode(): void {
    if (this.mainWin === null) {
      return;
    }
    this.mainWin.setWindowLayoutFullScreen(true).then((): void => {
      // 全屏切换会改变 TYPE_SYSTEM 避让值（HDS 桥接系统上状态栏避让归 0、页面根被推到
      // 状态栏下；普通真机仍报状态栏高度），且 avoidAreaChange 不保证对布局模式切换触发；
      // 启动早期读到的多为切换前旧值，广播 UI 层重读一次（Index @Watch insetEpoch）
      AppStorage.setOrCreate('insetEpoch', Date.now());
    }).catch((e: BusinessError) => {
      hilog.error(DOMAIN, 'Cimoc', 'Failed to set full screen layout. Cause: %{public}s', JSON.stringify(e));
    });
    try {
      this.mainWin.setWindowBackgroundColor(this.themeWindowBg());
    } catch (e) {
      hilog.error(DOMAIN, 'Cimoc', 'Failed to set window background. Cause: %{public}s', JSON.stringify(e));
    }
  }

  /** 主题底色：解析 sys.color.background_primary 随深浅色自动适配；解析失败按 colorMode 回退。 */
  private themeWindowBg(): string {
    try {
      const c = this.context.resourceManager.getColorSync($r('sys.color.background_primary'));
      return '#' + (c >>> 0).toString(16).padStart(8, '0');
    } catch (e) {
      const dark = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      return dark ? '#FF000000' : '#FFFFFFFF';
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 系统深浅色切换等配置变化：重放全屏与底色，保证兜底色与页面主题一致
    hilog.info(DOMAIN, 'Cimoc', 'configuration update: %{public}s', JSON.stringify(newConfig));
    this.applyImmersiveMode();
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
