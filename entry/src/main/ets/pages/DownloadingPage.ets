/** 下载中页：章节缓存任务队列。上段"下载中"（等待/下载中/失败），下段"已完成"。
 *  实时进度（@Observed + @ObjectLink 原位刷新，不闪烁）；横滑删除：队列任务直接移除，已完成删缓存（带确认）。 */

import { Comic, Task } from '../model/Model';
import { ComicDao } from '../data/Daos';
import { DownloadManager } from '../download/DownloadManager';
import Theme from '../common/Theme';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

/** 系统路由表入口（router_map.json → DownloadingPageBuilder）。 */
@Builder
export function DownloadingPageBuilder() {
  DownloadingPage()
}

/** 任务行：@ObjectLink 持有 @Observed Task，progress/max/comicTitle 变化只重绘本行内容，不整行重建。 */
@Component
struct TaskRow {
  @ObjectLink task: Task;

  isDoing(): boolean {
    return DownloadManager.get(getContext(this) as common.UIAbilityContext).currentId() === this.task.id;
  }

  statusText(): string {
    if (this.task.isFinish()) {
      return '已完成';
    }
    if (this.task.max < 0) {
      return '下载失败 · 点击重试';
    }
    if (this.task.max === 0) {
      return this.isDoing() ? '解析中…' : '等待中';
    }
    if (this.isDoing()) {
      return `下载中 ${this.task.progress}/${this.task.max}`;
    }
    return this.task.progress > 0 ? `等待中 ${this.task.progress}/${this.task.max}` : '等待中';
  }

  statusColor(): ResourceColor {
    if (this.task.isFinish()) {
      return Theme.SUCCESS;
    }
    if (this.task.max < 0) {
      return Theme.DANGER;
    }
    return this.isDoing() ? Theme.ACCENT : $r('sys.color.font_tertiary');
  }

  statusIcon(): Resource {
    if (this.task.isFinish()) {
      return $r('sys.symbol.checkmark_circle_fill');
    }
    if (this.task.max < 0) {
      return $r('sys.symbol.exclamationmark_triangle');
    }
    return $r('sys.symbol.download_fill');
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        SymbolGlyph(this.statusIcon())
          .fontSize(18)
          .fontColor([this.statusColor()])

        Column({ space: 3 }) {
          Text(this.task.comicTitle.length > 0 ? this.task.comicTitle : '漫画')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.task.title)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.statusText())
          .fontSize(11)
          .fontColor(this.statusColor())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Progress({ value: this.task.progress, total: Math.max(this.task.max, 1), type: ProgressType.Linear })
        .width('100%')
        .height(4)
        .color(this.task.isFinish() ? Theme.SUCCESS : Theme.ACCENT)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
    }
    .width('100%')
    .padding(Theme.PAD_CARD)
    .borderRadius(Theme.RADIUS_ITEM)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .onClick(() => {
      if (this.task.max < 0) {
        DownloadManager.get(getContext(this) as common.UIAbilityContext).retry(this.task);
        promptAction.showToast({ message: '已重新加入队列' });
      }
    })
  }
}

@Component
export struct DownloadingPage {
  @StorageLink('bottomInset') bottomInset: number = 0;
  @StorageLink('bp') bp: string = 'sm';
  @State doingTasks: Task[] = [];
  @State doneTasks: Task[] = [];
  // DownloadManager 每页进度/队列变化都会置脏；reload 原地合并，行不重建
  @StorageLink('download_dirty') @Watch('onDirty') dirty: number = 0;
  private comicDao: ComicDao | null = null;

  onDirty(): void {
    this.reload();
  }

  aboutToAppear(): void {
    this.comicDao = new ComicDao(getContext(this) as common.UIAbilityContext);
    this.reload();
  }

  reload(): void {
    DownloadManager.get(getContext(this) as common.UIAbilityContext).taskDaoRef().list().then((list: Task[]) => {
      const doing: Task[] = [];
      const done: Task[] = [];
      for (const t of list) {
        if (t.isFinish()) {
          done.push(t);
        } else {
          doing.push(t);
        }
      }
      this.doingTasks = this.mergeInto(this.doingTasks, doing);
      this.doneTasks = this.mergeInto(this.doneTasks, done);
    }).catch(() => {
      this.doingTasks = [];
      this.doneTasks = [];
    });
  }

  /** 原地合并：已存在的行复用同一 Task 对象只更新 progress/max（@ObjectLink 原位刷新）；
   *  ForEach key 只含 id，进度跳动不重建行 → 进度条不闪烁。 */
  private mergeInto(current: Task[], incoming: Task[]): Task[] {
    const merged: Task[] = [];
    for (const t of incoming) {
      let existing: Task | null = null;
      for (const e of current) {
        if (e.id === t.id) {
          existing = e;
          break;
        }
      }
      if (existing !== null) {
        existing.progress = t.progress;
        existing.max = t.max;
        merged.push(existing);
      } else {
        merged.push(t);
        this.fillTitle(t);
      }
    }
    return merged;
  }

  private fillTitle(t: Task): void {
    const dao = this.comicDao;
    if (dao === null || t.comicTitle.length > 0) {
      return;
    }
    dao.loadById(t.key).then((c: Comic | null) => {
      if (c !== null) {
        t.comicTitle = c.title;
      }
    });
  }

  // 左滑：队列任务直接移除（未完成章节的"缓存中"标记一并清除）
  @Builder
  deleteCellQueue(t: Task) {
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
      DownloadManager.get(getContext(this) as common.UIAbilityContext).deleteTask(t);
    })
  }

  // 左滑：已完成任务删除本地缓存（带确认）
  @Builder
  deleteCellCache(t: Task) {
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
      this.confirmDeleteCache(t);
    })
  }

  confirmDeleteCache(t: Task): void {
    AlertDialog.show({
      title: '删除缓存',
      message: `确定删除「${t.title}」的本地缓存吗？`,
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
          DownloadManager.get(getContext(this) as common.UIAbilityContext).deleteChapterCache(t.key, t.path);
        }
      }
    });
  }

  @Builder
  sectionHeader(text: string, count: number) {
    Text(`${text} · ${count}`)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 4, top: 6 })
  }

  @Builder
  emptyState() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.download'))
        .fontSize(52)
        .fontColor([$r('sys.color.font_fourth')])
      Text('暂无下载任务\n在详情页右上角可缓存章节')
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .width('100%')
  }

  build() {
    NavDestination() {
      Column() {
        if (this.doingTasks.length === 0 && this.doneTasks.length === 0) {
          this.emptyState()
        } else {
          List({ space: Theme.GAP_LIST }) {
            // 上段：下载中（等待 / 下载中 / 失败）
            if (this.doingTasks.length > 0) {
              ListItem() {
                this.sectionHeader('下载中', this.doingTasks.length)
              }
            }
            ForEach(this.doingTasks, (t: Task) => {
              ListItem() {
                TaskRow({ task: t })
              }
              .swipeAction({ end: this.deleteCellQueue(t) })
            }, (t: Task) => `doing_${t.id}`)

            // 下段：已完成
            if (this.doneTasks.length > 0) {
              ListItem() {
                this.sectionHeader('已完成', this.doneTasks.length)
              }
            }
            ForEach(this.doneTasks, (t: Task) => {
              ListItem() {
                TaskRow({ task: t })
              }
              .swipeAction({ end: this.deleteCellCache(t) })
            }, (t: Task) => `done_${t.id}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: Theme.pagePad(this.bp), right: Theme.pagePad(this.bp), top: 4 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .height('100%')
    }
    .title('下载中')
    .backgroundColor($r('sys.color.background_primary'))
  }
}
