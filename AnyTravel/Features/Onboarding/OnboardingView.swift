import SwiftUI

struct OnboardingView: View {
    @Bindable var model: PlannerViewModel
    @Bindable var sessionStore: ProviderSessionStore
    let completion: () -> Void

    @State private var page = 0
    @State private var activeProvider: ProviderAccount?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.90, green: 0.97, blue: 0.95), .white, Color(red: 1.0, green: 0.94, blue: 0.89)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack {
                    Text("AnyTravel")
                        .font(.headline.weight(.bold))
                    Spacer()
                    if page < 3 {
                        Button("跳过介绍") { page = 3 }
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.horizontal, 22)

                TabView(selection: $page) {
                    introductionPage(
                        symbol: "bird.fill",
                        brandMark: true,
                        eyebrow: "旅行，是一场诗意的迁徙",
                        title: "让每一次选择，都在\n地图上长成一段旅程",
                        detail: "路线沿着街巷舒展，\n住处与车站也会随心意浮现。\n你只管说：下一程，想去哪里？",
                        accent: AnyTravelPalette.route
                    )
                    .tag(0)

                    introductionPage(
                        symbol: "arrow.triangle.branch",
                        eyebrow: "出发没有固定次序",
                        title: "先买一张车票\n或先挑一扇喜欢的窗",
                        detail: "日期、预算、景点、住处与交通，\n都可以随时补上。\n每一次选择，都会让远方更清晰。",
                        accent: AnyTravelPalette.warm
                    )
                    .tag(1)

                    introductionPage(
                        symbol: "text.book.closed.fill",
                        eyebrow: "把远方写成可抵达的日常",
                        title: "从第一程车，到最后一笔花费\n都替你安放妥帖",
                        detail: "每天默认走得松弛一些。\n住宿、交通、时间与费用，会汇成完整方案。\n每一笔价格，都留下来源与时间。",
                        accent: Color(red: 0.38, green: 0.34, blue: 0.72)
                    )
                    .tag(2)

                    initialSettingsPage
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 7) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? AnyTravelPalette.route : Color.secondary.opacity(0.22))
                            .frame(width: index == page ? 26 : 8, height: 8)
                    }
                }

                Button {
                    if page < 3 {
                        withAnimation(.snappy) { page += 1 }
                    } else {
                        completion()
                    }
                } label: {
                    Label(page == 3 ? "开始规划" : "继续", systemImage: page == 3 ? "map" : "arrow.right")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: 520, minHeight: 54)
                        .background(AnyTravelPalette.route, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(AnyTravelPressStyle())
                .padding(.horizontal, 22)
                .padding(.bottom, 10)
            }
            .padding(.top, 12)
        }
        .sheet(item: $activeProvider) { provider in
            ProviderLoginView(provider: provider, sessionStore: sessionStore)
        }
    }

    private func introductionPage(
        symbol: String,
        brandMark: Bool = false,
        eyebrow: String,
        title: String,
        detail: String,
        accent: Color
    ) -> some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .fill(.white.opacity(0.72))
                    .frame(width: 250, height: 250)
                    .rotationEffect(.degrees(-7))
                    .shadow(color: accent.opacity(0.18), radius: 26, y: 15)
                if brandMark {
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 168, height: 168)
                        .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
                        .shadow(color: accent.opacity(0.16), radius: 14, y: 8)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 78, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            VStack(spacing: 14) {
                Text(eyebrow)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 30)
                    .background(accent.opacity(0.09), in: Capsule())
                Text(title)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 350)
                    .padding(.horizontal, 18)
                Text(detail)
                    .font(.system(size: 15.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 350)
                    .padding(.horizontal, 20)
            }
            Spacer()
        }
    }

    private var initialSettingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("出发前，先留下几句偏好")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                    Text("它们会成为每段旅程的底色，之后仍可随时修改；脚步默认放得轻松。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    onboardingField(symbol: "location.circle", title: "常用出发地") {
                        TextField("例如：上海", text: Binding(
                            get: { model.draft.logistics.origin },
                            set: { model.draft.logistics.origin = $0 }
                        ))
                    }
                    onboardingField(symbol: "banknote", title: "默认人均预算") {
                        Stepper(
                            "¥\(model.draft.budgetPerPerson.formatted(.number.grouping(.automatic)))",
                            value: $model.draft.budgetPerPerson,
                            in: 1_000...30_000,
                            step: 500
                        )
                    }
                    onboardingField(symbol: "person.2", title: "默认人数") {
                        Stepper(
                            "\(model.draft.logistics.travelers)人",
                            value: $model.draft.logistics.travelers,
                            in: 1...8
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("把常用平台带上路（也可稍后）")
                        .font(.headline)
                    Text("登录会话会安静地留在应用内，打开报价与预订页时继续使用；密码始终只交给对应平台。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(ProviderAccount.allCases) { provider in
                        Button {
                            activeProvider = provider
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: provider.symbolName)
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(AnyTravelPalette.route, in: Circle())
                                Text(provider.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(sessionStore.isConnected(provider) ? "会话已保存" : "登录")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(sessionStore.isConnected(provider) ? AnyTravelPalette.route : .secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 56)
                            .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                        .buttonStyle(AnyTravelPressStyle())
                    }
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func onboardingField<Content: View>(
        symbol: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(AnyTravelPalette.route)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 62)
        .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}
