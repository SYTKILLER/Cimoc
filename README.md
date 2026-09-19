# Cimoc

Cimoc Android 漫画阅读器的 HarmonyOS 原生移植版。非跨端框架套壳，全部页面基于 ArkUI / ArkTS 原生实现。

> 图源目录仓库：[SYTKILLER/Cimoc-Source](https://github.com/SYTKILLER/Cimoc-Source)（只收录经全链路验证的图源，应用内「我的 → 更新图源配置」可在线更新）

## 功能特性

- 多图源并行搜索、发现页浏览、详情、收藏、历史与阅读进度记忆
- 阅读器：翻页 / 条漫流式双模式随时切换，沉浸式全屏，退出重进精确恢复进度
- 离线缓存：章节下载队列、完全离线的本地漫画库、缓存清理
- 深色模式、断点自适应布局（手机 / 平板 / 2in1）
- 数据模型与 Android 版 1:1 对应，支持原版 `index.cdif` 漫画索引导入

## 下载

前往 [Releases](https://github.com/SYTKILLER/Cimoc/releases) 下载 HAP 安装包（unsigned，需自行签名后安装）。

## 构建

1. 使用 DevEco Studio 打开工程（compatibleSdkVersion：6.1.1 / API 24）
2. File → Project Structure → Signing Configs 配置签名（默认不签名）
3. Build → Build App(s)/HAP(s)，或命令行 `devecocli build --build-mode release`

## 许可证

[GPL-3.0](LICENSE)。基于 [Haleydu/Cimoc](https://github.com/Haleydu/Cimoc) 与 [PFPT/CimocPlus](https://github.com/PFPT/CimocPlus) 移植，感谢原项目作者。

本项目仅供学习交流，漫画内容均来自各公开站点，请支持正版。
