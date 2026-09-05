import SwiftUI

struct SettingsView: View {
    @Bindable var model: PlannerViewModel
    @Bindable var sessionStore: ProviderSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var activeProvider: ProviderAccount?
    @AppStorage(PricingBackendClient.serviceURLDefaultsKey) private var pricingServiceURL = ""
    @State private var serviceCheckResult: String?
    @State private var serviceHealthy: Bool?
    @State private var checkingService = false
    @State private var customAPIKey = ""
    @State private var assistantCheckResult: String?
    @State private var checkingAssistant = false

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
                    Picker(
                        "回应来自",
                        selection: Binding(
                            get: { model.assistantSettings.mode },
                            set: {
                                model.assistantSettings.mode = $0
                                assistantCheckResult = nil
                            }
                        )
                    ) {
                        ForEach(AssistantProviderMode.allCases) { provider in
                            Text(provider.title)
                                .tag(provider)
                                .accessibilityIdentifier("assistant-mode-\(provider.rawValue)")
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("assistant-provider-picker")

                    if model.assistantSettings.mode == .managed {
                        LabeledContent("使用方式", value: "沿用应用预设")
                        Text("无需填写接口或密钥。只发送这次的问题与当前旅行条件；在线向导暂时不可用时，仍可继续使用本机基础规划。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        TextField(
                            "OpenAI 兼容 Base URL",
                            text: Binding(
                                get: { model.assistantSettings.customBaseURL },
                                set: { model.assistantSettings.customBaseURL = $0 }
                            )
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityIdentifier("assistant-custom-base-url")

                        TextField(
                            "模型名称",
                            text: Binding(
                                get: { model.assistantSettings.customModel },
                                set: { model.assistantSettings.customModel = $0 }
                            )
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("assistant-custom-model")

                        SecureField(
                            model.assistantSettings.hasCustomAPIKey ? "已安全存入钥匙串；填写可替换" : "API Key",
                            text: $customAPIKey
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("assistant-custom-api-key")

                        HStack {
                            Button(model.assistantSettings.hasCustomAPIKey ? "替换钥匙" : "存入钥匙串") {
                                do {
                                    try model.assistantSettings.saveCustomAPIKey(customAPIKey)
                                    customAPIKey = ""
                                    assistantCheckResult = "钥匙已经收好，页面不会再把它读出来。"
                                } catch {
                                    assistantCheckResult = error.localizedDescription
                                }
                            }
                            .disabled(customAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Spacer()
                            if model.assistantSettings.hasCustomAPIKey {
                                Button("删除钥匙", role: .destructive) {
                                    do {
                                        try model.assistantSettings.deleteCustomAPIKey()
                                        assistantCheckResult = "这把钥匙已经从本机离开。"
                                    } catch {
                                        assistantCheckResult = error.localizedDescription
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        checkingAssistant = true
                        assistantCheckResult = nil
                        Task {
                            assistantCheckResult = await model.testAssistantConnection()
                            checkingAssistant = false
                        }
                    } label: {
                        HStack {
                            Label("检查智能服务", systemImage: "sparkles")
                            Spacer()
                            if checkingAssistant { ProgressView() }
                        }
                    }
                    .disabled(checkingAssistant)
                    .accessibilityIdentifier("assistant-connection-test")

                    if let assistantCheckResult {
                        Text(assistantCheckResult)
                            .font(.caption)
                            .foregroundStyle(AnyTravelPalette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("旅途里的智能向导")
                } footer: {
                    Text("自定义服务是可选项。向导的修改会经过本机检查；选择酒店或班次不代表已经预订。")
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
                    DisclosureGroup("自建服务（高级选项）") {
                    TextField("例如：http://192.168.1.10:8787/", text: $pricingServiceURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        checkingService = true
                        serviceCheckResult = nil
                        Task {
                            let healthy = await PricingBackendClient().healthCheck(urlText: pricingServiceURL)
                            serviceHealthy = healthy
                            serviceCheckResult = healthy ? "已连接 AnyTravel；是否有房、有票以本次查询为准" : "在线服务暂未连接，内置规划仍可用，请稍后重试"
                            checkingService = false
                        }
                    } label: {
                        HStack {
                            Label("检查自建服务", systemImage: "network")
                            Spacer()
                            if checkingService { ProgressView() }
                        }
                    }
                    if let serviceCheckResult {
                        Text(serviceCheckResult)
                            .font(.caption)
                            .foregroundStyle(serviceHealthy == true ? AnyTravelPalette.route : AnyTravelPalette.warm)
                    }
                    Button("恢复应用预设") { pricingServiceURL = ""; serviceCheckResult = "已恢复应用预设" }
                    }
                } header: {
                    Text("高级设置")
                } footer: {
                    Text("普通使用无需修改。留空将沿用此版本的默认服务。")
                }

                Section {
                    Link(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
                        Label("OpenStreetMap 地图与地点", systemImage: "map")
                    }
                    Link(destination: URL(string: "https://www.wikidata.org/wiki/Wikidata:Licensing")!) {
                        Label("Wikidata 公共知识", systemImage: "books.vertical")
                    }
                    Link(destination: URL(string: "https://audiala.com/")!) {
                        Label("Data by Audiala · 旅行资料", systemImage: "book.pages")
                    }
                    Link(destination: URL(string: "https://sjfw.mct.gov.cn/site/dataservice/base")!) {
                        Label("文化和旅游部 A 级景区名录", systemImage: "checkmark.seal")
                    }
                } header: {
                    Text("这张地图从哪里生长")
                } footer: {
                    Text("内置攻略用于发现与排序，已经过城市归属、重复地点和代表性地标校验；营业、预约和票价仍会按你的出行日期重新查询。")
                }
            }
            .navigationTitle("旅途偏好与价格渠道")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                model.persistPlanningDefaults()
            }
            .task {
                await sessionStore.reconcileSavedSessions()
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
