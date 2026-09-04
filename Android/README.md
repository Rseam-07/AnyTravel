# AnyTravel Android

Android 客户端使用 Kotlin、Jetpack Compose 与 MapLibre Native。最低系统为 Android 12（API 31），地图样式来自 OpenFreeMap；地图归属信息由 MapLibre 保留。

## 当前可用流程（0.8.1）

- 四页欢迎与初始偏好；默认松弛节奏。
- 地图背景上的开放式自然语言输入，以及目的地、天数、预算、兴趣、住宿和交通选择。
- 生成前按热度排列景点，允许先勾选主要游览点或直接跳过交给应用补齐。
- 与 iOS/Web 共用 162 个目的地、其中 141 个国内目的地、1,234 个地点的可追溯资料快照；其他目的地继续调用 Android 系统地理编码服务寻找地点、酒店与枢纽。
- 完整日程、住宿、交通、费用与本地保存。
- 住宿变化后重新计算车站/机场接驳与交通排序。
- 应用内优先直连 RollingGo 酒店，并并行补充雅高集团官网公开选日房价和希尔顿官网目录；铁路 12306 提供去返程班次与席别价，飞猪提供航班与起价；同一 AnyTravel 报价节点可继续补充其他渠道。
- 住宿按价格、景点距离、枢纽距离与实时价筛选；交通按去返程与方式筛选，同一住宿或班次的多渠道报价合并展示。
- Apple 地图式连续底部面板：可在 18%–94% 高度自由拖动，完成选择或调整后按内容自动回到合适高度。
- 方案生成后可在地图长按添加地点，在日程中前后移动、跨天移动、删除，并使用最多 30 步撤销与重做；变更后路线和价格重新计算。
- Android 原生导出完整方案 PDF 与 `.ics` 日历文件，并交给系统分享页或日历应用。
- 平台购买页、错误重试、深浅色、TalkBack 语义与“移除动画”降级。
- 默认或自定义 OpenAI 兼容智能向导；自定义 Key 由 Android Keystore 加密保存，模型动作经过本地白名单后才改变地图。

地图优先向公开 Valhalla 路由服务请求道路几何；路由不可用时才显示并明确标记游览顺序示意线。实时数据只有在返回来源、金额和抓取时间后才标为实时价。

Android 12 的地图使用 MapLibre OpenGL 与 `TextureView`，限制过高像素倍率和瓦片预取，并按可见日增量更新路线；面板拖动只更新局部偏移，网络结果成批发布，避免整棵 Compose/地图树同时插值。应用也会响应系统低内存回调，并在 `Activity` 生命周期结束时释放地图渲染器。

## 构建

要求：JDK 17、Android SDK Platform 37.0、Build Tools 37.0.0。

```sh
cd Android
./gradlew testDebugUnitTest lintDebug assembleRelease
```

构建会输出按处理器拆分的 APK 和一个通用 APK。GitHub 发布使用 `app-universal-release.apk` 的重命名副本；它采用 Release 编译设置，但仍使用公开预览签名，便于开源侧载，不可视为正式商店签名。

连接 Android 12 或更新版本的设备/模拟器后运行：

```sh
./gradlew connectedDebugAndroidTest
```

调试 APK 默认允许连接局域网 HTTP 报价节点；Release 构建默认只允许 HTTPS。模拟器连接电脑上的节点时可填写 `http://10.0.2.2:8787/`。

## 0.8.1 验证范围

- 规划、路线、行程编辑与导出单元测试、Android lint、Debug 和 Release 通用 APK 构建通过。
- 实时聚合测试按实际入住日期取得带数值的酒店价格，并按往返日期取得铁路 12306 班次/席别价和飞猪航班起价；酒店链路以 RollingGo 为优先来源，雅高官网在 RollingGo 之外提供选日品牌直价。
- Compose 端到端测试覆盖首次欢迎、景点勾选、方案生成以及日程/住宿/交通/费用切换；当前构建机没有连接 Android 设备，也没有安装 emulator/system image，本轮未执行 `connectedDebugAndroidTest`。
- 已加入 `scripts/capture-xperia-crash.sh`，可在 Xperia 1 II 上清理旧日志、启动应用并保存崩溃上下文。当前没有接入该型号实体设备，因此不能把索尼 Android 12 的闪退称为已复现或已验收；生产签名、真机弱网、大字体、TalkBack、横屏和平板仍待后续验收。
