/** 搜索相关度模糊匹配：关键词 vs 漫画名打分（0–100），供二级搜索页本地排序。
 *
 *  打分模型（阶梯式，高分段 = 连续命中，低分段 = 模糊命中）：
 *  1. 规范化：小写、去空白与中英文标点、全角转半角——装饰符不影响语义；
 *  2. 连续阶梯：相等 100 ＞ 标题以关键词开头 95 ＞ 标题包含关键词 88
 *     ＞ 关键词以标题开头 85（用户多打了后缀，标题是关键词前缀）；
 *  3. 模糊子序列：允许跳字的贪心顺序匹配，双向取优（关键词散布在标题中，
 *     如「开局无敌」→「开局就无敌」；或标题散布在关键词中），得分 =
 *     覆盖率基底 + 连续度加成 − 跳字/位置惩罚，全子序列封顶 80、部分封顶 76，
 *     保证低于任何连续阶梯；
 *  4. 覆盖率不足一半视为不相关，返回 0。
 */

class SubseqStats {
  matched: number = 0;
  totalGap: number = 0;
  bestRun: number = 0;
}

export class FuzzyMatcher {
  /** 匹配下限：关键词（或标题）至少一半字符能顺序命中才视为模糊相关。 */
  private static readonly MIN_COVERAGE: number = 0.5;
  /** 低质量阈值：低于该分视为低质量结果（设置开启时直接隐藏，不参与排序）。 */
  static readonly LOW_QUALITY_THRESHOLD: number = 50;
  /** 单源保留上限：设置开启时每个源最多保留匹配度最高的 N 条。 */
  static readonly MAX_PER_SOURCE: number = 3;
  /** 规范化时剔除的空白与标点（全角标点先转半角再剔除）。 */
  private static readonly STRIP_CHARS: string =
    " \t\n\r\u00A0\u3000,.;:!?\"'`()[]{}<>~@#$%^&*+-=/\\|_"
    + '，。、：；！？·—…“”‘’（）《》【】「」『』〔〕';

  static score(keyword: string, title: string): number {
    const kw = FuzzyMatcher.normalize(keyword);
    const tt = FuzzyMatcher.normalize(title);
    if (kw.length === 0 || tt.length === 0) {
      return 0;
    }
    if (tt === kw) {
      return 100;
    }
    if (tt.startsWith(kw)) {
      return 95;
    }
    if (tt.includes(kw)) {
      return 88;
    }
    if (tt.length >= 2 && kw.startsWith(tt)) {
      return 85;
    }
    const fwd = FuzzyMatcher.greedyMatch(kw, tt);
    const rev = FuzzyMatcher.greedyMatch(tt, kw);
    let best = 0;
    if (fwd.matched / kw.length >= FuzzyMatcher.MIN_COVERAGE) {
      best = Math.max(best, FuzzyMatcher.subseqScore(kw.length, fwd, 80));
    }
    if (rev.matched / tt.length >= FuzzyMatcher.MIN_COVERAGE) {
      best = Math.max(best, FuzzyMatcher.subseqScore(tt.length, rev, 76));
    }
    return Math.floor(best);
  }

  /** 规范化：小写、全角转半角、剔除空白与标点。 */
  static normalize(s: string): string {
    const lower = s.toLowerCase();
    let out = '';
    for (let i = 0; i < lower.length; i++) {
      let code = lower.charCodeAt(i);
      if (code >= 0xFF01 && code <= 0xFF5E) {
        code -= 0xFEE0;
      }
      const ch = String.fromCharCode(code);
      if (FuzzyMatcher.STRIP_CHARS.includes(ch)) {
        continue;
      }
      out += ch;
    }
    return out;
  }

  /** 子序列得分 = 覆盖率基底 + 连续度加成 − 跳字惩罚，封顶 cap。 */
  private static subseqScore(total: number, m: SubseqStats, cap: number): number {
    const coverage = m.matched / total;
    const base = coverage >= 1 ? 62 : 30 + 25 * coverage;
    const contiguity = (m.bestRun / total) * 8;
    const gapPenalty = Math.min(10, m.totalGap * 0.4);
    return Math.max(0, Math.min(cap, base + contiguity - gapPenalty));
  }

  /** 贪心顺序匹配：need 每个字符按序在 hay 中找最早命中；统计覆盖数、
   *  累计跳字（含标题前缀偏移）、最长连续命中段（连续度信号）。 */
  private static greedyMatch(need: string, hay: string): SubseqStats {
    const st = new SubseqStats();
    let ti = 0;
    let run = 0;
    for (let i = 0; i < need.length; i++) {
      const idx = hay.indexOf(need[i], ti);
      if (idx < 0) {
        run = 0;
        continue;
      }
      const gap = idx - ti;
      st.totalGap += gap;
      run = gap === 0 && st.matched > 0 ? run + 1 : 1;
      if (run > st.bestRun) {
        st.bestRun = run;
      }
      st.matched++;
      ti = idx + 1;
    }
    return st;
  }
}
