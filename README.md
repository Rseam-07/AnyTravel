# AnyTravel

AnyTravel 是一个以真实地图为主界面的 iOS 行程规划原型。用户先说目的地，再选择天数、预算、兴趣、节奏和交通方式；应用从 Apple Maps 搜索地点、安排每日顺序，并在背景地图上逐段画出真实路线。用户拖动地图时，自动镜头会立即停止，避免和手势争夺控制权。

![首次进入](Documentation/Screenshots/welcome.png)

![苏州真实路线](Documentation/Screenshots/route-ready.png)

## 当前可用流程

- 输入城市、区域或目的地，地图自动定位。
- 设置 1–7 天、人均预算、兴趣、行程密度和交通方式。
- 使用 `MKLocalSearch` 获取真实地点，按距离和兴趣平衡分配到每天。
- 只为当前选中的一天请求 `MKDirections`，逐段显示路线并自动移动镜头。
- 点击地图编号或地点条目聚焦地点，并可转到 Apple 地图。
- 用自然语言调整路线，例如“轻松一点”“改成 4 天，预算 5000 元，公交优先”“不要博物馆”。
- 在本机保存、重新打开和删除行程；不需要账号，也没有第三方分析或广告 SDK。
- iOS 26 及以上使用 Liquid Glass；iOS 17–25 使用系统材质回退。

## 工程

- 最低系统：iOS 17
- 已验证工具链：Xcode 27.0 beta、Swift 6.4、iOS 26.5 模拟器
- UI：SwiftUI
- 地图和地点数据：MapKit / Apple Maps
- 本地状态：Observation + JSON 原子写入
- 第三方运行时依赖：无

直接打开 `AnyTravel.xcodeproj`，选择 `AnyTravel` scheme 后运行。工程定义保存在 `project.yml`；若要重新生成项目，可使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```sh
xcodegen generate --spec project.yml
```

调试构建支持 `--demo-ready` 启动参数，用于直接跑通“苏州 → 搜索地点 → 计算路线 → 地图展开”的验收流程。

## 验证

```sh
xcodebuild \
  -project AnyTravel.xcodeproj \
  -scheme AnyTravel \
  -sdk iphonesimulator \
  -configuration Debug \
  -derivedDataPath /tmp/AnyTravelDerived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

最终测试结果为 10/10 通过：8 项单元测试覆盖自然语言指令解析、本地保存/读取/删除，以及磁盘写入失败时不产生“幽灵行程”；2 项 XCUITest 会真实点击欢迎页入口、保存按钮和行程库。地点搜索和路线计算还经过了模拟器联网实测，苏州示例返回 3 天行程，并成功绘制第 1 天的三站步行路线。界面已分别在 iPhone 17 Pro 和 iPad Pro 11 英寸、iOS 26.5 模拟器上检查。

## 数据边界

地点和路线来自 Apple Maps。营业时间、票价、预约规则和临时闭馆可能变化，应用会在界面中提醒用户出发前复核。预算当前作为行程条件保留；由于 MapKit 不提供统一可靠的实时票价，它不会伪造费用或承诺总价。保存的数据只写入本机 Application Support 目录。

参考实现和知识产权边界见 [参考审计](Documentation/REFERENCE_AUDIT.md)。
