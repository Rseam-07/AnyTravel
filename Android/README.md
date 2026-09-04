# AnyTravel Android

Android 客户端使用 Kotlin、Jetpack Compose 与 MapLibre Native。最低系统为 Android 12（API 31），地图样式来自 OpenFreeMap；地图归属信息由 MapLibre 保留。

## 当前可用流程（0.8.0）

- 四页欢迎与初始偏好；默认松弛节奏。
- 地图背景上的开放式自然语言输入，以及目的地、天数、预算、兴趣、住宿和交通选择。
- 生成前按热度排列景点，允许先勾选主要游览点或直接跳过交给应用补齐。
- 与 iOS/Web 共用 162 个目的地、其中 141 个国内目的地、1,234 个地点的可追溯资料快照；其他目的地继续调用 Android 系统地理编码服务寻找地点、酒店与枢纽。
- 完整日程、住宿、交通、费用与本地保存。
- 住宿变化后重新计算车站/机场接驳与交通排序。
- 应用内直连 RollingGo 酒店、铁路 12306 去返程班次与席别价、飞猪航班与起价；同一 AnyTravel 报价节点可继续补充其他渠道。
- 住宿按价格、景点距离、枢纽距离与实时价筛选；交通按去返程与方式筛选，同一住宿或班次的多渠道报价合并展示。
- Apple 地图式连续底部面板：可在 18%–94% 高度自由拖动，完成选择或调整后按内容自动回到合适高度。
- 平台购买页、错误重试、深浅色、TalkBack 语义与“移除动画”降级。
- 默认或自定义 OpenAI 兼容智能向导；自定义 Key 由 Android Keystore 加密保存，模型动作经过本地白名单后才改变地图。

地图上的彩色线段目前是游览顺序示意，不是逐路段导航几何；应用会在日程页明确提示。实时数据只有在返回来源、金额和抓取时间后才标为实时价。

## 构建

要求：JDK 17、Android SDK Platform 37.0、Build Tools 37.0.0。

```sh
cd Android
./gradlew testDebugUnitTest assembleDebug
```

构建会输出按处理器拆分的 APK 和一个通用 APK。绝大多数现代 Android 手机优先使用 `app-arm64-v8a-debug.apk`；不确定处理器时使用 `app-universal-debug.apk`。

连接 Android 12 或更新版本的设备/模拟器后运行：

```sh
./gradlew connectedDebugAndroidTest
```

调试 APK 默认允许连接局域网 HTTP 报价节点；Release 构建默认只允许 HTTPS。模拟器连接电脑上的节点时可填写 `http://10.0.2.2:8787/`。

## 0.8.0 验证范围

- 规划逻辑单元测试、RollingGo/12306/飞猪三类实时源联网测试和 Android lint 通过。
- 实时数据测试按实际入住日期取得 RollingGo 酒店数字价格，按往返日期取得铁路 12306 班次/席别价和飞猪航班起价。
- Compose 端到端测试覆盖首次欢迎、景点勾选、方案生成以及日程/住宿/交通/费用切换；当前构建机没有连接 Android 设备，也没有安装 emulator/system image，本轮未执行 `connectedDebugAndroidTest`。
- 发布 APK 使用 Android 调试签名，便于开源预览和侧载；生产签名、Play 发布、真机弱网、大字体、TalkBack、横屏和平板仍待后续验收。
