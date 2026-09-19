/** 偏好封装（key 与 Android 版 PreferenceManager 沿用，便于理解与备份兼容）。 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export class PrefKeys {
  static readonly READER_MODE = 'pref_reader_mode';               // 0=翻页 1=条漫
  static readonly READER_PRELOAD = 'pref_reader_preload';
  static readonly READER_PRELOAD_COUNT = 'pref_reader_preload_count';
  static readonly READER_WHITE_EDGE = 'pref_reader_white_edge';
  static readonly READER_BRIGHTNESS = 'pref_reader_brightness';
  static readonly READER_KEEP_ON = 'pref_reader_keep_on';
  static readonly READER_VOLUME_KEY = 'pref_reader_volume_key_controls_page_turning';
  static readonly READER_TURN_DIRECTION = 'pref_reader_turn_direction'; // 0=LTR 1=RTL 2=上下
  static readonly NIGHT = 'pref_night';
  static readonly EXPLORE_SOURCE = 'pref_explore_source';
  static readonly SEARCH_HISTORY = 'pref_search_history';
  static readonly DOWNLOAD_THREAD = 'pref_download_thread';
}

export class Prefs {
  private static store: preferences.Preferences | null = null;

  static async get(context: common.UIAbilityContext): Promise<preferences.Preferences> {
    if (Prefs.store !== null) {
      return Prefs.store;
    }
    Prefs.store = await preferences.getPreferences(context, 'cimoc_preferences');
    return Prefs.store;
  }

  static async getString(context: common.UIAbilityContext, key: string, def: string = ''): Promise<string> {
    const p = await Prefs.get(context);
    const v = await p.get(key, def);
    return typeof v === 'string' ? v as string : def;
  }

  static async putString(context: common.UIAbilityContext, key: string, value: string): Promise<void> {
    const p = await Prefs.get(context);
    await p.put(key, value);
    await p.flush();
  }

  static async getBool(context: common.UIAbilityContext, key: string, def: boolean = false): Promise<boolean> {
    const p = await Prefs.get(context);
    const v = await p.get(key, def);
    return typeof v === 'boolean' ? v as boolean : def;
  }

  static async putBool(context: common.UIAbilityContext, key: string, value: boolean): Promise<void> {
    const p = await Prefs.get(context);
    await p.put(key, value);
    await p.flush();
  }

  static async getInt(context: common.UIAbilityContext, key: string, def: number = 0): Promise<number> {
    const p = await Prefs.get(context);
    const v = await p.get(key, def);
    return typeof v === 'number' ? v as number : def;
  }

  static async putInt(context: common.UIAbilityContext, key: string, value: number): Promise<void> {
    const p = await Prefs.get(context);
    await p.put(key, value);
    await p.flush();
  }

  static async putStringArray(context: common.UIAbilityContext, key: string, value: string[]): Promise<void> {
    const p = await Prefs.get(context);
    await p.put(key, JSON.stringify(value));
    await p.flush();
  }

  static async getStringArray(context: common.UIAbilityContext, key: string): Promise<string[]> {
    const s = await Prefs.getString(context, key, '[]');
    try {
      const o: object = JSON.parse(s) as object;
      if (Array.isArray(o)) {
        return o as string[];
      }
    } catch (e) {
      // ignore
    }
    return [];
  }
}
