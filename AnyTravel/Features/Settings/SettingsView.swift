import SwiftUI

struct SettingsView: View {
    @Bindable var model: PlannerViewModel
    @Bindable var sessionStore: ProviderSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var activeProvider: ProviderAccount?
    @AppStorage(PricingBackendClient.serviceURLDefaultsKey) private var pricingServiceURL = ""
    @State private var serviceCheckResult: String?
    @State private var checkingService = false

    var body: some View {
        NavigationStack {
            Form {
                Section("每段旅程的底色") {
                    TextField("常用出发地", text: Binding(
                        get: { model.draft.logistics.origin },
                        set: { model.draft.logistics.origin = $0 }
                    ))
                    Stepper(
                        "默认人数：\(model.draft.logistics.travelers)",
                        value: $model.draft.logistics.travelers,
                        in: 1...8
                    )
                    Stepper(
                        "人均预算：¥\(model.draft.budgetPerPerson.formatted(.number.grouping(.automatic)))",
                        value: $model.draft.budgetPerPerson,
                        in: 1_000...30_000,
                        step: 500
                    )
                    LabeledContent("默认脚步", value: "轻松")
                }

                Section {
                    ForEach(ProviderAccount.allCases) { provider in
                        HStack {
                            Label(provider.title, systemImage: provider.symbolName)
                            Spacer()
                            if sessionStore.isConnected(provider) {
                                Button("清除") {
                                    Task { await sessionStore.disconnect(provider) }
                                }
                                .foregroundStyle(.red)
                                Button("重连") { activeProvider = provider }
                            } else {
                                Button("登录") { activeProvider = provider }
                            }
                        }
                    }
                } header: {
                    Text("随身的价格渠道")
                } footer: {
                    Text("平台登录在应用内网页中完成。报价与预订页会沿用同一会话；AnyTravel 不读取密码。清除后，该平台留在应用里的 Cookie 也会一并离开。自建采集节点使用独立浏览器会话。")
                }

                Section {
                    TextField("例如：http://192.168.1.10:8787/", text: $pricingServiceURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        checkingService = true
                        serviceCheckResult = nil
                        Task {
                            let healthy = await PricingBackendClient().healthCheck(urlText: pricingServiceURL)
                            serviceCheckResult = healthy ? "报价节点已经接上旅程" : "还没接上，请检查地址和服务状态"
                            checkingService = false
                        }
                    } label: {
                        HStack {
                            Label("试着接通开源报价节点", systemImage: "network")
                            Spacer()
                            if checkingService { ProgressView() }
                        }
                    }
                    if let serviceCheckResult {
                        Text(serviceCheckResult)
                            .font(.caption)
                            .foregroundStyle(serviceCheckResult.contains("成功") ? AnyTravelPalette.route : AnyTravelPalette.warm)
                    }
                } header: {
                    Text("自己的报价驿站")
                } footer: {
                    Text("连接仓库内的伴随服务后，RollingGo、携程网页采集与后续渠道会从同一处归来；密钥只留在服务端。")
                }
            }
            .navigationTitle("旅途偏好与价格渠道")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                model.persistPlanningDefaults()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .sheet(item: $activeProvider) { provider in
            ProviderLoginView(provider: provider, sessionStore: sessionStore)
        }
    }
}
