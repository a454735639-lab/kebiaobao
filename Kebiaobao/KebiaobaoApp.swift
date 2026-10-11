import SwiftUI
import UIKit

/// 外观偏好：跟随系统 / 强制浅色 / 强制深色
enum KBAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

@main
struct KebiaobaoApp: App {
    @StateObject private var store = Store()
    @AppStorage("kb.appearance") private var appearance = KBAppearance.system.rawValue
    /// 提醒重建的防抖句柄
    @State private var resyncWork: DispatchWorkItem?

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(KB.accent)
                .preferredColorScheme(KBAppearance(rawValue: appearance)?.scheme)
                .task {
                    // 授权结果回来后再建提醒，否则首启时 status 还是 notDetermined
                    KBReminder.requestAuth {
                        KBReminder.sync(templates: store.templates, courses: store.courses)
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) private var scheme
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(0)

            ScheduleView()
                .tabItem { Label("课表", systemImage: "calendar") }
                .tag(1)

            MeView()
                .tabItem { Label("我的", systemImage: "person.fill") }
                .tag(2)
        }
        .onAppear { applyTabBar() }
        // scheme 变化时重建 tab bar 外观
        .onChange(of: scheme) { _, _ in applyTabBar() }
        // 排课／课程变动后重建提醒（防抖 1s：数组每次改动都全量重建通知太浪费）
        .onChange(of: store.templates) { _, _ in resyncReminders() }
        .onChange(of: store.courses) { _, _ in resyncReminders() }
    }

    private func resyncReminders() {
        resyncWork?.cancel()
        let work = DispatchWorkItem { KBReminder.sync(templates: store.templates, courses: store.courses) }
        resyncWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func applyTabBar() {
        let dark = scheme == .dark
        let ap = UITabBarAppearance()
        ap.configureWithOpaqueBackground()
        ap.backgroundColor = dark ? UIColor(hex: 0x1C1C1E) : .white
        ap.shadowColor = dark ? UIColor(hex: 0x2C2C2E) : UIColor(hex: 0xECECEF)
        UITabBar.appearance().standardAppearance = ap
        UITabBar.appearance().scrollEdgeAppearance = ap
    }
}
