# AnyTravel Android

Android 客户端使用 Kotlin、Jetpack Compose 与 MapLibre Native。最低系统为 Android 12（API 31），地图样式来自 OpenFreeMap；地图归属信息由 MapLibre 保留。

## 当前可用流程

- 四页欢迎与初始偏好；默认松弛节奏。
- 地图背景上的目的地、天数、预算、兴趣、住宿和交通选择。
- 苏州人工核对地点包；其他目的地调用 Android 系统地理编码服务寻找地点、酒店与枢纽。
- 完整日程、住宿、交通、费用与本地保存。
- 住宿变化后重新计算车站/机场接驳与交通排序。
- 连接同一 AnyTravel 报价节点，读取 RollingGo/携程酒店报价和铁路12306结果。
- 平台购买页、错误重试、深浅色、TalkBack 语义与“移除动画”降级。

地图上的彩色线段在 0.4.0 是游览顺序示意，不是逐路段导航几何；应用会在日程页明确提示。实时数据只有在返回来源、金额和抓取时间后才标为实时价。

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

## 0.4.0 验证范围

- Android 12（API 31、arm64）模拟器完成首次欢迎、跳过设置、苏州方案生成和日程/住宿/交通/费用切换。
- 4 个规划逻辑单元测试、1 个 Compose 端到端测试和 Android lint 通过。
- Android App 实际连接本地报价节点，显示 RollingGo 酒店实时价与铁路 12306 车次、票价、余票和抓取时间。
- 发布 APK 使用 Android 调试签名，便于开源预览和侧载；生产签名、Play 发布、真机弱网、大字体、TalkBack、横屏和平板仍待后续验收。
