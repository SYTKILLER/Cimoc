/**
 * 「继续阅读」卡片生命周期（2×2，form_config.json: ContinueReadingCard）。
 * 刷新时钟只有两个：添加卡片（onAddForm）与应用退前台（EntryAbility.onBackground →
 * reloadAllForms → onUpdateForm）；updateDuration=0 且无定点刷新，系统不会按时间表唤醒。
 * 注意：卡片进程与主应用进程隔离，此处构建数据一律经 CardDataProvider（共享沙箱）。
 */

import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common, Want } from '@kit.AbilityKit';
import { CardDataProvider } from '../form/CardDataProvider';

const DOMAIN = 0x0000;
const TAG = 'CimocForm';

export default class EntryFormAbility extends FormExtensionAbility {
  /** 卡片添加：同步回占位数据，异步构建真实数据后 updateForm 补全；同时登记 formId 供应用进程兜底直刷。 */
  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, TAG, 'onAddForm');
    let formId = '';
    try {
      const params: Record<string, Object> | undefined = want.parameters;
      const raw: Object | undefined = params === undefined ? undefined : params[formInfo.FormParam.IDENTITY_KEY];
      if (typeof raw === 'string') {
        formId = raw;
      }
    } catch (e) {
      // ignore
    }
    if (formId.length > 0) {
      const ctx = this.context as object as common.UIAbilityContext;
      CardDataProvider.addFormId(ctx, formId).catch((e: Object) => {
        hilog.error(DOMAIN, TAG, 'addFormId failed: %{public}s', String(e));
      });
      CardDataProvider.build(ctx).then((payload) => {
        formProvider.updateForm(formId, payload.data).then(() => {
          payload.close();
          hilog.info(DOMAIN, TAG, 'onAddForm refresh done');
        }).catch((e: Object) => {
          payload.close();
          hilog.error(DOMAIN, TAG, 'onAddForm updateForm failed: %{public}s', String(e));
        });
      }).catch((e: Object) => {
        hilog.error(DOMAIN, TAG, 'onAddForm build failed: %{public}s', String(e));
      });
    }
    return CardDataProvider.placeholder();
  }

  /** 定时/定点均未配置，本回调实际只由应用进程 reloadAllForms 或兜底链路触发。 */
  onUpdateForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onUpdateForm %{public}s', formId);
    const ctx = this.context as object as common.UIAbilityContext;
    CardDataProvider.build(ctx).then((payload) => {
      formProvider.updateForm(formId, payload.data).then(() => {
        payload.close();
      }).catch((e: Object) => {
        payload.close();
        hilog.error(DOMAIN, TAG, 'onUpdateForm updateForm failed: %{public}s', String(e));
      });
    }).catch((e: Object) => {
      hilog.error(DOMAIN, TAG, 'onUpdateForm build failed: %{public}s', String(e));
    });
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm %{public}s', formId);
    const ctx = this.context as object as common.UIAbilityContext;
    CardDataProvider.removeFormId(ctx, formId).catch((e: Object) => {
      hilog.error(DOMAIN, TAG, 'removeFormId failed: %{public}s', String(e));
    });
  }
}
