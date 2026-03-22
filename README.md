# Type4Me

> macOS 菜单栏语音输入工具，按下快捷键说话，松开即输入。

## 为什么做 Type4Me

macOS 自带的语音输入不支持中文流式识别，第三方工具要么延迟高，要么数据上云，要么不够灵活。
Type4Me 解决的就是这三个问题：**快、本地、可定制**。

## 功能亮点

### 流式语音识别，响应极快

基于火山引擎（豆包）大模型 ASR，WebSocket 双向流式传输，200ms 音频分片，边说边出字。性能模式下还支持双通道识别（流式 + Flash 一次性），取最优结果。

### 自定义处理模式

内置 4 种模式，也可以自定义任意多个：

| 模式 | 说明 |
|---|---|
| **快速模式** | 原样输出 ASR 识别结果，零延迟 |
| **性能模式** | 双通道识别，流式 + Flash 取优 |
| **智能模式** | ASR + LLM 后处理，自动纠错、补标点 |
| **英文翻译** | 说中文，输出英文翻译 |
| **自定义** | 自己写 prompt，用 LLM 做任何后处理 |

每个模式可以绑定独立的全局快捷键，支持「按住说话」和「按一下开始/再按停止」两种触发方式。

### 数据完全本地，支持导出

- 所有凭证存在本地文件 `~/Library/Application Support/Type4Me/credentials.json`（权限 0600），不经过任何中间服务器
- 识别历史记录存在本地 SQLite 数据库，支持按日期范围导出 CSV
- 无遥测、无数据上报、无云同步

### 词汇管理

- **ASR 热词**：添加专有名词（如 `Claude`、`Kubernetes`），提升识别准确率
- **片段替换**：语音说「我的邮箱」，自动替换为实际邮箱地址

### 更多特性

- 中英双语 UI，跟随系统语言自动切换
- 浮窗实时显示识别文本，带录音动画
- 首次使用有引导设置向导
- Swift Package Manager 构建，无第三方依赖
- 支持 macOS 14+

## 快速开始

### 前置条件

- macOS 14.0 (Sonoma) 或更高版本
- Swift 6.0+
- 火山引擎账号（获取 ASR 凭证）

### 构建

```bash
git clone https://github.com/joewongjc/type4me.git
cd type4me
swift build -c release
```

### 打包为 App

```bash
bash scripts/deploy.sh
```

脚本会构建、打包为 `.app`、签名并启动。

### 配置凭证

首次启动会弹出设置向导，填入火山引擎的 App Key、Access Key 和 Resource ID 即可。

## 架构概览

```
Type4Me/
├── ASR/                    # ASR 引擎抽象层
│   ├── ASRProvider.swift          # Provider 枚举 + 协议
│   ├── ASRProviderRegistry.swift  # 注册表
│   ├── Providers/                 # 各厂商配置（12 家）
│   ├── VolcASRClient.swift        # 火山引擎流式 ASR
│   └── VolcFlashASRClient.swift   # 火山引擎 Flash ASR
├── Audio/                  # 音频采集
├── Session/                # 核心状态机：录音 → ASR → 注入
├── Input/                  # 全局快捷键管理
├── Services/               # 凭证存储、热词、片段替换
├── Protocol/               # 火山引擎 WebSocket 协议编解码
└── UI/                     # SwiftUI 界面
    ├── FloatingBar/               # 浮窗
    └── Settings/                  # 设置界面（5 个 Tab）
```

ASR Provider 架构设计为可插拔：每个云厂商实现 `ASRProviderConfig`（定义凭证字段）和 `SpeechRecognizer`（实现识别逻辑），注册到 `ASRProviderRegistry` 即可。

## 参与贡献

**这个项目需要你的帮助。**

目前我个人只完成了**火山引擎（Volcengine）**的 ASR 适配和调试。项目架构已经预留了 12 家云厂商的接口定义（OpenAI Whisper、Google、AWS、Azure、阿里云、腾讯云、百度、讯飞等），但客户端实现还是空的。

如果你在用其他语音识别服务，欢迎提交 PR 补充实现。添加一个新 Provider 只需要三步：

1. 在 `Type4Me/ASR/Providers/` 新建 Config 文件，实现 `ASRProviderConfig` 协议
2. 编写 ASR Client，实现 `SpeechRecognizer` 协议
3. 在 `ASRProviderRegistry.all` 中注册你的 `createClient`

当然，不只是 ASR Provider，任何形式的贡献都欢迎：

- 发现 bug？[提 Issue](../../issues)
- 有好想法？[开 Discussion](../../discussions)
- 想改代码？直接 Fork & PR

## 许可证

[MIT License](LICENSE)
