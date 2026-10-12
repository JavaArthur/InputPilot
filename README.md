# 应用输入法 InputPilot

原生 macOS 菜单栏应用，根据前台应用切换系统输入法。支持 macOS 13+；本机交付为 Apple Silicon 构建。

## 使用

打开 InputPilot.app，点击菜单栏的 `中` / `EN` 图标进入“应用规则与设置”。添加正在运行的应用，或从 Applications 选择应用，然后选择规则：

| 规则 | 行为 |
| --- | --- |
| 指定输入法，例如 ABC 或微信输入法 | 每次进入这个应用都切换到指定输入法；临时手动切换不会改掉预设 |
| 记住上次输入法 | 记录你在这个应用里手动选择的系统输入法，下次恢复；首次无记录时使用全局默认 |
| 使用全局默认 | 始终使用全局默认输入法 |

未预设应用默认启用记忆，可在设置顶部关闭。默认输入法也可选“保持当前输入法”。“暂停切换”暂停自动切换和记忆写入，恢复后按当前应用重新应用规则。

点击菜单栏的“为当前应用预设”可以快速绑定。关闭设置窗口后，应用仍在菜单栏运行。开机启动使用系统 SMAppService，在界面中开启；若系统要求批准，会显示“打开登录项”。初始开机启动开关关闭。

当前版切换的是系统输入源（例如 ABC 和微信输入法）。微信输入法自身的内部中英文状态不是一个独立 TIS 输入源，本版不控制该内部状态。

## 本地数据

规则及记忆保存在 `~/Library/Application Support/InputPilot/config.json`。无网络请求，不读取或改写其他输入法切换软件的配置，不记录输入的文本。规则中保存应用名称、bundle ID、路径及输入源 ID。

固定规则优先于记忆；程序自己引发的输入源变化不会写入记忆。快速切换应用会使旧任务失效。配置损坏或版本不支持时保留原文件并暂停，不用空配置覆盖。

## 构建与检查

```sh
swift run InputPilotCoreChecks
bash scripts/build-app.sh
dist/InputPilot.app/Contents/MacOS/InputPilot --list-inputs
```

构建脚本生成 `dist/InputPilot.app` 并作本机 ad-hoc 签名，无外部包依赖。不需要安装完整 Xcode；核心检查使用独立 Swift 断言程序，因为本机 Command Line Tools 没有 XCTest。

原生集成检查使用隔离配置和四个临时测试应用，会暂时切换前台窗口及输入法，最后恢复原状态。运行前应退出正在使用的 InputPilot，避免单实例复用到其他配置：

```sh
mkdir -p verification
swiftc scripts/Fixture.swift -o verification/Fixture
swiftc scripts/smoke.swift -o verification/smoke
verification/smoke "$PWD"
```

`--config /absolute/path.json` 仅用于隔离测试配置；正常使用无需传入。`--settings` 可在启动时打开设置。请勿将 verification 中的测试配置用作个人配置。

## 实现边界

SwiftUI 设置界面、AppKit 菜单栏和应用通知、Carbon TIS 输入源选择、ServiceManagement 登录启动。基础功能不申请辅助功能或键盘监听权限。

切换请求先延迟 150ms，成功提交后 100ms 回读实际输入源；最多再尝试 3 次。每个请求有独立代次和重试预算。切换过程中及完成后的短暂稳定期抑制记忆写入。实际稳定性仍受系统“自动切换到文稿的输入法”和其他自动切换工具影响。

本机签名适合当前机器使用；没有开发者证书签名、公证或其他 macOS 版本的兼容测试。实际验证结果见 [VERIFICATION.md](VERIFICATION.md)。
