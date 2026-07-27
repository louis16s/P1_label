# P1 Label

P1 Label 是为德佟 P1 热敏标签打印机开发的 macOS 原生标签设计与打印工具。

## 主要功能

- USB 自动检测、打印和设备状态读取
- 蓝牙扫描、连接、状态查询和分块发送
- 文字、图片、二维码、Code 128 条码及基础图形
- 字体、粗体、斜体、下划线、删除线、对齐和旋转
- 彩色、灰度与打印效果预览，以及多种黑白转换算法
- 间隙纸、连续纸、黑标纸、浓度、速度、反色、份数和打印偏移
- 缺纸、开盖、过热、电压及打印头等状态提醒
- 标签保存、打开、导出副本、图片导入及 CSV 批量打印
- 撤销、重做、多选、复制粘贴、锁定和键盘移动

## 系统要求

- macOS 26
- Apple 芯片 Mac

## 安装与运行

从 GitHub Actions 构建产物或 Release 下载 `P1Label-macOS26-arm64.zip`，解压后打开 `P1Label.app` 即可。正式交付的应用已经将 `libusb-1.0.0.dylib` 内置在应用包的 `Contents/Frameworks` 中，并使用应用内相对路径加载：

- 普通用户不需要安装 Homebrew
- 普通用户不需要单独安装 `libusb`
- 复制 `P1Label.app` 到另一台符合要求的 Mac 后仍可独立运行

## 从源码构建

只有开发者从源代码编译时才需要通过 Homebrew 提供 `libusb` 的头文件和构建库：

```sh
brew install libusb
swift test
./script/build_and_run.sh
```

构建脚本会自动把 Homebrew 提供的 `libusb` 复制进应用并修正动态链接路径，然后将最新可运行应用固定写入 `artifacts/latest/P1Label.app`，同时生成同目录的 `P1Label-macOS26-arm64.zip`。源代码采用 Swift Package 管理，界面使用 SwiftUI，USB 传输由精简的 C 桥接层连接 `libusb`。目录和交付约定见[本地构建与交付规范](docs/本地构建与交付规范.md)。

每次推送都会由 GitHub Actions 在 macOS 26 ARM64 环境中运行测试、构建独立应用并上传压缩包。推送形如 `v1.0.0` 的版本标签时，会自动创建 GitHub Release。

## SDK 支持范围

P1 Label 没有直接链接只面向 iOS/UIKit 的 LPAPI 静态库，而是依据其公开功能和 P1 协议实现原生 macOS 版本。详细核对结果见 [SDK 功能支持矩阵](docs/SDK功能支持矩阵.md)，也可在应用的“帮助 → SDK 功能支持情况”中查看。

固件升级未开放：在缺少官方 P1 固件校验及恢复规范时，错误升级可能造成设备损坏。

## 参考项目

- [lynzrand/kaori3](https://github.com/lynzrand/kaori3)：P1 通信与打印实现参考（WTFPL）
- [cornradio/web-printer](https://github.com/cornradio/web-printer)：标签编辑交互参考（MIT）
- [德佟官方 SDK](http://detonger.com/#/sdk/detail?sdkID=A47887F7-69D4-4865-9187-E82BD0F70E88)：设备能力与状态定义参考

P1 Label 是独立的 macOS 原生实现；上述项目用于协议研究与交互设计参考。

## 开源协议

本项目采用 [MIT License](LICENSE)。
