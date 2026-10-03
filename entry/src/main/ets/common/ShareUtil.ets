/** 系统分享封装：把 `[标题][链接]` 文本交给系统分享面板（@kit.ShareKit）。
 *  签名与枚举以本机 SDK（6.1.1）d.ts 为准：previewMode 是 SharePreviewMode.DETAIL
 *  （网上教程常见的 DETAIL_PREVIEW 在该 SDK 不存在），show 的 options 必填；发送侧无权限要求。 */

import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';

/** 拉起系统分享面板分享 `[标题][链接]` 文本；标题为空（如网页入口详情未加载完）时只分享链接。 */
export async function shareComicText(context: common.UIAbilityContext, title: string, url: string): Promise<void> {
  const text = title.length > 0 ? `[${title}][${url}]` : url;
  const data: systemShare.SharedData = new systemShare.SharedData({
    utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
    content: text
  });
  const controller: systemShare.ShareController = new systemShare.ShareController(data);
  try {
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DETAIL
    });
  } catch (e) {
    const err = e as BusinessError;
    promptAction.showToast({ message: `分享失败（${err.code}）` });
  }
}
