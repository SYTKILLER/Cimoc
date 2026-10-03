/**
 * 智感握姿传感层：订阅/退订系统握持事件（左手/右手感知），能力防御。
 * 移植自 Pixark：业务侧只调 start(callback) / stop()，不要绕过它直接调 motion.on。
 * 真机验证：hilog | grep HoldingHandleUtil
 */

import { motion } from '@kit.MultimodalAwarenessKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'HoldingHandleUtil';

export type HoldingHandCallback = (status: motion.HoldingHandStatus) => void;

class _HoldingHandleUtil {
  // 缓存系统能力是否可用（防重复注册）
  private isCapabilityAvailable: boolean = false;
  private callback: HoldingHandCallback | null = null;

  /**
   * 启动握持检测。设备不支持 MultimodalAwareness.Motion 时静默降级（不注册、只告警）。
   */
  start(callback: HoldingHandCallback): void {
    if (!canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      this.isCapabilityAvailable = false;
      hilog.warn(0x4514, TAG, '当前设备不支持握持检测 API');
      return;
    }
    if (this.isCapabilityAvailable) {
      hilog.info(0x4514, TAG, '握持检测已在运行中');
      return;
    }
    this.isCapabilityAvailable = true;
    this.callback = callback;
    try {
      motion.on('holdingHandChanged', (status: motion.HoldingHandStatus) => {
        this.logStatus(status);
        if (this.callback) {
          this.callback(status);
        }
      });
      hilog.info(0x4514, TAG, '握持检测已启动');
    } catch (e) {
      hilog.error(0x4514, TAG, `开启握持事件失败: ${JSON.stringify(e)}`);
      this.isCapabilityAvailable = false;
    }
  }

  stop(): void {
    if (!this.isCapabilityAvailable) {
      return;
    }
    try {
      if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
        motion.off('holdingHandChanged');
        hilog.info(0x4514, TAG, '握持检测已停止');
      }
    } catch (error) {
      hilog.error(0x4514, TAG, `关闭握持事件失败: ${JSON.stringify(error)}`);
    } finally {
      this.isCapabilityAvailable = false;
      this.callback = null;
    }
  }

  private logStatus(status: motion.HoldingHandStatus): void {
    if (!canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      this.isCapabilityAvailable = false;
      hilog.warn(0x4514, TAG, '当前设备不支持握持检测 API');
      return;
    }
    this.isCapabilityAvailable = true;
    let str = '';
    switch (status) {
      case motion.HoldingHandStatus.NOT_HELD: str = '未握持'; break;
      case motion.HoldingHandStatus.LEFT_HAND_HELD: str = '左手握持'; break;
      case motion.HoldingHandStatus.RIGHT_HAND_HELD: str = '右手握持'; break;
      case motion.HoldingHandStatus.BOTH_HANDS_HELD: str = '双手握持'; break;
    }
    hilog.debug(0x4514, TAG, `状态变化: ${status} - ${str}`);
  }
}

export const HoldingHandleUtil = new _HoldingHandleUtil();
