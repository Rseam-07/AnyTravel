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
                        LabeledContent("默认模型", value: "GLM-5.3-Flash")
                        Text("模型钥匙只留在 AnyTravel 伴随服务的环境变量里；App 只送出当前行程和这一次指令。")
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
                            Label("听一听智能向导的回声", systemImage: "sparkles")
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
                    Text("自定义服务需兼容 OpenAI 的 chat/completions 接口。任何模型给出的地图动作都会先经过本地白名单校验。")
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
                            serviceHealthy = healthy
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
                            .foregroundStyle(serviceHealthy == true ? AnyTravelPalette.route : AnyTravelPalette.warm)
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
