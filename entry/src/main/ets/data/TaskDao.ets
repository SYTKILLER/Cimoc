/** 下载任务 DAO。 */

import { relationalStore } from '@kit.ArkData';
import { Db } from './Db';
import { Task } from '../model/Model';
import { common } from '@kit.AbilityKit';

export class TaskDao {
  private ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  private async store(): Promise<relationalStore.RdbStore> {
    return Db.get(this.ctx);
  }

  private static fromRow(rs: relationalStore.ResultSet): Task {
    const t = new Task(
      rs.getLong(rs.getColumnIndex('KEY')),
      rs.getString(rs.getColumnIndex('PATH')) ?? '',
      rs.getString(rs.getColumnIndex('TITLE')) ?? '',
      rs.getLong(rs.getColumnIndex('PROGRESS')),
      rs.getLong(rs.getColumnIndex('MAX')));
    t.id = rs.getLong(rs.getColumnIndex('_id'));
    t.state = t.isFinish() ? Task.STATE_FINISH : Task.STATE_PAUSE;
    return t;
  }

  /** 全部任务，_id 倒序（新任务在前，供 UI 列表）。不能过滤 MAX=0：新任务插入时 MAX=0，必须可见。 */
  async list(): Promise<Task[]> {
    return this.queryOrdered(false);
  }

  /** 全部任务，_id 正序（供 pump FIFO 调度：先加入的章节先下载）。 */
  async listPendingAsc(): Promise<Task[]> {
    return this.queryOrdered(true);
  }

  private async queryOrdered(asc: boolean): Promise<Task[]> {
    const store = await this.store();
    const pred = new relationalStore.RdbPredicates('TASK');
    if (asc) {
      pred.orderByAsc('_id');
    } else {
      pred.orderByDesc('_id');
    }
    const rs = await store.query(pred, ['_id', 'KEY', 'PATH', 'TITLE', 'PROGRESS', 'MAX']);
    const out: Task[] = [];
    while (rs.goToNextRow()) {
      out.push(TaskDao.fromRow(rs));
    }
    rs.close();
    return out;
  }

  async load(key: number, path: string): Promise<Task | null> {
    const store = await this.store();
    const pred = new relationalStore.RdbPredicates('TASK');
    pred.equalTo('KEY', key).and().equalTo('PATH', path);
    const rs = await store.query(pred, ['_id', 'KEY', 'PATH', 'TITLE', 'PROGRESS', 'MAX']);
    let found: Task | null = null;
    if (rs.goToFirstRow()) {
      found = TaskDao.fromRow(rs);
    }
    rs.close();
    return found;
  }

  async insertIfNotExist(task: Task): Promise<void> {
    const old = await this.load(task.key, task.path);
    if (old !== null) {
      task.id = old.id;
      task.progress = old.progress;
      task.max = old.max;
      return;
    }
    const store = await this.store();
    const row: relationalStore.ValuesBucket = {
      'KEY': task.key,
      'PATH': task.path,
      'TITLE': task.title,
      'PROGRESS': task.progress,
      'MAX': task.max,
    };
    task.id = await store.insert('TASK', row);
  }

  async update(task: Task): Promise<void> {
    const store = await this.store();
    const row: relationalStore.ValuesBucket = {
      'PROGRESS': task.progress,
      'MAX': task.max,
    };
    const pred = new relationalStore.RdbPredicates('TASK');
    pred.equalTo('_id', task.id);
    await store.update(row, pred);
  }

  async delete(task: Task): Promise<void> {
    const store = await this.store();
    const pred = new relationalStore.RdbPredicates('TASK');
    pred.equalTo('_id', task.id);
    await store.delete(pred);
  }
}
