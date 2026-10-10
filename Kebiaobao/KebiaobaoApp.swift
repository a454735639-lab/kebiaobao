import SwiftUI
import UIKit

@main
struct KebiaobaoApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(KB.accent)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
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
        .onAppear {
            let ap = UITabBarAppearance()
            ap.configureWithOpaqueBackground()
            ap.backgroundColor = .white
            ap.shadowColor = UIColor(KB.line)
            UITabBar.appearance().standardAppearance = ap
            UITabBar.appearance().scrollEdgeAppearance = ap
        }
    }
}
