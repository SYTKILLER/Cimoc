/**
 * 设计令牌：对齐 Pixark 的圆角/间距/按压体系；
 * 颜色一律使用 sys.color 系统资源以自动适配深色模式。
 */

export default class Theme {
  /** 圆角体系 */
  static readonly RADIUS_CARD: number = 24;    // 大卡片 / 分组容器
  static readonly RADIUS_ITEM: number = 16;    // 行内卡片 / 输入框 / 封面
  static readonly RADIUS_SMALL: number = 12;   // 小格子
  static readonly RADIUS_PILL: number = 999;   // 胶囊

  /** 间距 */
  static readonly PAD_PAGE: number = 16;       // 页面左右边距
  static readonly PAD_CARD: number = 14;       // 卡片内边距
  static readonly GAP_LIST: number = 10;       // 列表间距

  /** HdsTabs 悬浮页签栏自身高度（悬浮样式官方默认值 56vp） */
  static readonly FLOATING_BAR_HEIGHT: number = 56;

  /**
   * 断点（Index 写入 AppStorage 'bp'）：'sm' <600vp / 'md' 600–840 / 'lg' ≥840。
   * 以下辅助按鸿蒙排版规范给出对应档位的页面边距与网格列数。
   */

  /** 页面左右边距：sm 16 / md 24 / lg 32（规范：大屏可增大至 24 或 32） */
  static pagePad(bp: string): number {
    return bp === 'lg' ? 32 : (bp === 'md' ? 24 : Theme.PAD_PAGE);
  }

  /** 封面网格列数：sm 3 / md 4 / lg 6 */
  static coverCols(bp: string): string {
    return bp === 'lg'
      ? '1fr 1fr 1fr 1fr 1fr 1fr'
      : (bp === 'md' ? '1fr 1fr 1fr 1fr' : '1fr 1fr 1fr');
  }

  /** 章节网格列数：sm 2 / md 3 / lg 4 */
  static chapterCols(bp: string): string {
    return bp === 'lg' ? '1fr 1fr 1fr 1fr' : (bp === 'md' ? '1fr 1fr 1fr' : '1fr 1fr');
  }

  /**
   * 悬浮页签栏底部避让总高 = 底部安全区(无指示器时 16) + 栏高 56 + 12vp 呼吸空间。
   * 可滚动列表用作 contentEndOffset（滚动途中内容穿过栏下，滚到底时最后一项完整露出）；
   * 静态页面用作 padding.bottom。
   */
  static floatTabBarAvoid(bottomInset: number): number {
    return (bottomInset > 0 ? bottomInset : 16) + Theme.FLOATING_BAR_HEIGHT + 12;
  }

  /** 动效 */
  static readonly ANIM_FAST: number = 200;
  static readonly ANIM_NORMAL: number = 300;
  static readonly PRESS_SCALE: number = 0.97;
  static readonly PRESS_OPACITY: number = 0.85;

  /** 强调色（HarmonyOS 蓝，深浅色下均可读） */
  static readonly ACCENT: string = '#007DFF';
  static readonly ACCENT_SOFT: string = '#1A007DFF';
  static readonly WARNING: string = '#FF9500';
  static readonly SUCCESS: string = '#4CAF50';
  static readonly DANGER: string = '#CC0000';

  /** 卡片阴影 */
  static readonly CARD_SHADOW: ShadowOptions = {
    radius: 16,
    color: '#14000000',
    offsetY: 2,
  };
}
