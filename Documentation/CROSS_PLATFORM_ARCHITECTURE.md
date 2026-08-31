# AnyTravel 三端共建方案

目标不是让三端共用一套页面代码，而是让同一个旅行决策只实现一次，同时保留 iOS、Android 与 Web 各自最自然的地图、手势、底部面板和系统能力。

## 推荐结构

```text
apps/
  ios/        SwiftUI + MapKit
  android/    Jetpack Compose + MapLibre/平台地图
  web/        React + TypeScript + MapLibre GL，PWA
Backend/      规划编排、报价、地点适配、智能向导
Contracts/    OpenAPI、JSON Schema、错误码、示例响应
Design/       色彩、圆角、字体阶梯、动效时长与图标语义 token
Fixtures/     苏州等金标行程、空结果、过期价格、单渠道失败样本
```

## 真正共享的部分

- 用 OpenAPI/JSON Schema 定义地点、逐日行程、酒店报价、往返交通、接驳、费用与智能动作。CI 为 Swift、Kotlin、TypeScript 生成客户端类型，避免三端手写字段漂移。
- 把多渠道查询、价格口径归一、住宿与交通联合排序、GLM 指令解释放在伴随服务。三端只渲染带来源的结果并执行本地允许的地图动作。
- 维护同一批金标样本：缺日期、断网、登录过期、只有返程失败、酒店换选、忙碌行程铺松。每端必须得到同样的业务状态。
- 共享设计 token 和语义图标清单，不共享 SwiftUI/Compose/React 视图实现。弹簧、拖拽阈值与地图镜头参数也以 token 表达，再由平台原生 API 实现。

## Web 端落地

Web 采用 React、TypeScript、Vite 与 MapLibre GL，做可安装 PWA。桌面用左侧行程轨道加全屏地图，移动网页沿用底部卡片和抽屉；URL 保存当前旅程、日期和地图焦点，便于分享与恢复。离线先缓存已打开的行程和静态底图范围，实时价格离线时明确过期。

MapLibre 负责地图呈现，地点和路线仍由后端的统一契约返回。这样 Web 不需要复制 iOS 的 MapKit 查询逻辑，也不会因更换底图供应商重写整个规划器。

## 不建议当前整体改成 Flutter 或 React Native

iOS 与 Android 已经有各自的原生工程，整体重写会先消耗版本周期，还会削弱 MapKit、系统分享、钥匙串、动态材质、返回手势和无障碍的细节。近期更省力的路线是共享服务、契约、测试样本与视觉 token；当某一段纯计算逻辑稳定后，再评估以 TypeScript/WASM 或 Kotlin Multiplatform 下沉，而不是先搬页面。

## 发布与回归

- 后端契约变更先跑兼容性检查，新增字段默认可选，删除或改名必须升主版本。
- CI 矩阵分别构建 iOS、Android、Web 和 Backend；同一份 fixtures 跑三端状态断言。
- 每次发布至少实测：首次进入、登录、加载、空结果、刷新、断网恢复、卡片点击、地图聚焦、系统返回和大字体。
- 服务端密钥永远只进部署环境；iOS/Android 自定义 Key 使用系统安全存储，Web 自定义 Key 默认只留在当前浏览器的加密本地会话，且明确提示风险。
