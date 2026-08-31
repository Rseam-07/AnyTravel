# FocusFlight IPA 参考审计

用户提供的参考包：`net.cementpla.FocusFlights_2.0_und3fined.ipa`

- SHA-256：`337cb0f822cf91b3a5d56ffb6457642d4ff725af50189e73db8839bd89c41361`
- 应用版本：2.0（build 265）
- Bundle ID：`net.cementpla.FocusFlights`
- 最低系统：iOS 17

本项目只对 IPA 做了只读解包和元数据/框架清单检查，用来理解它的地图优先结构、路线表达、Widget/Live Activity 能力和技术选择。检查到的相关系统能力包括 SwiftUI、MapKit、CoreLocation、WidgetKit 和 ActivityKit；包内还包含第三方分析、订阅与数据库框架。

AnyTravel 没有复制或重新分发参考应用的二进制代码、图片、字体、声音、数据库、文案、品牌标识或私有接口，也没有把其闭源包作为工程基础。当前实现为独立 SwiftUI/MapKit 代码，第一版刻意不引入广告归因、账号、订阅、Firebase 或第三方机场数据库。

采用这一边界的原因很实际：界面和交互规律可以学习，但闭源资源和实现不能据此取得授权。它也让 AnyTravel 的数据来源、隐私行为和故障恢复更容易审计。

## 使用的官方接口

- [MapKit for SwiftUI](https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui)
- [MKLocalSearch](https://developer.apple.com/documentation/mapkit/mklocalsearch)
- [MKDirections](https://developer.apple.com/documentation/mapkit/mkdirections)
- [MapCameraPosition](https://developer.apple.com/documentation/mapkit/mapcameraposition)
- [MapPolyline](https://developer.apple.com/documentation/mapkit/mappolyline)
- [Liquid Glass](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
