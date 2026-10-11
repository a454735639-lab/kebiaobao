import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications
import EventKit

struct MeView: View {
    @EnvironmentObject var store: Store
    @State private var showImport = false
    @State private var showAppearance = false
    @AppStorage("kb.appearance") private var appearance = KBAppearance.system.rawValue
    @State private var showManual = false
    @State private var showPicker = false
    @State private var shareItem: ShareItem?
    @State private var toast: String?
    @State private var pending: Store.ImportPreview?
    @State private var confirmRestore = false

    private var backupSub: String {
        store.backupDate.map { "覆盖前自动快照 · \(KBDate.mdhm.string(from: $0))" } ?? "覆盖前自动快照"
    }

    @State private var notifyStatus: UNAuthorizationStatus = .notDetermined

    private var reminderSub: String {
        switch notifyStatus {
        case .authorized, .provisional:
            let n = store.templates.filter { $0.remindMinutes > 0 }.count
            return n > 0 ? "已开启 · \(n) 条排课提前提醒" : "已开启（排课里设置提前分钟数后生效）"
        case .denied: return "已关闭 · 点这里去系统设置开启"
        default: return "点这里授权，按排课时间提醒"
        }
    }

    private func handleReminderTap() {
        switch notifyStatus {
        case .denied:
            if let u = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(u)
            }
        default:
            KBReminder.requestAuth {
                KBReminder.sync(templates: store.templates, courses: store.courses)
                refreshNotifyStatus()
            }
        }
    }

    private func refreshNotifyStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async { notifyStatus = s.authorizationStatus }
        }
    }

    // MARK: - 系统日历同步

    @State private var calStatus: EKAuthorizationStatus = CalendarSync.status
    @AppStorage("kb.calendarSync") private var calendarSync = false
    @State private var calBusy = false

    private var calSub: String {
        if calBusy { return "同步中…" }
        if !CalendarSync.isAuthorized {
            return calStatus == .denied ? "未授权 · 点这里去系统设置开启"
                                        : "点这里授权，把排课写入系统日历"
        }
        return calendarSync ? "已开启 · 排课自动写入「课时宝」日历" : "关闭中 · 点这里开启"
    }

    private func handleCalendarTap() {
        if !CalendarSync.isAuthorized {
            if calStatus == .denied, let u = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(u)
            } else {
                CalendarSync.requestAccess { ok in
                    calStatus = CalendarSync.status
                    if ok { calendarSync = true; syncCalendar() }
                }
            }
            return
        }
        calendarSync.toggle()
        if calendarSync { syncCalendar() } else { clearCalendar() }
    }

    private func syncCalendar() {
        calBusy = true
        CalendarSync.sync(templates: store.templates, courses: store.courses) { r in
            calBusy = false
            switch r {
            case .ok(let n): toast = "已同步 \(n) 条排课到系统日历"
            case .denied: calendarSync = false; toast = "未获得日历权限"
            case .failed(let m): toast = "同步失败：\(m)"
            }
        }
    }

    private func clearCalendar() {
        calBusy = true
        CalendarSync.clear { r in
            calBusy = false
            if case .ok(let n) = r { toast = "已从系统日历移除 \(n) 条" }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KB.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        profileCard
                        statCard
                        group("数据管理") {
                            navBaby()
                            navCourse()
                            row("plus.circle.fill", "手动记账", "不限日期，直接加／扣课时") {
                                showManual = true
                            }
                            navLedger()
                            navAnalytics()
                        }
                        group("提醒") {
                            row("bell.badge", "排课提醒",
                                reminderSub) { handleReminderTap() }
                            row("calendar.badge.plus", "同步到系统日历",
                                calSub) { handleCalendarTap() }
                        }
                        group("外观") {
                            row("moon.stars", "深色模式",
                                KBAppearance(rawValue: appearance)?.title ?? "跟随系统") {
                                showAppearance = true
                            }
                        }
                        group("备份与恢复") {
                            row("square.and.arrow.up", "导出 Excel",
                                "全部宝贝／课程／排课／流水 (.xlsx)") { exportAll() }
                            row("doc.badge.plus", "导入 Excel",
                                "选择 .xlsx 文件，确认后覆盖当前数据") { showImport = true }
                            if store.hasBackup {
                                row("arrow.uturn.backward", "恢复上次导入前的数据",
                                    backupSub) { confirmRestore = true }
                            }
                        }
                        group("关于") {
                            HStack {
                                Text("版本").font(.system(size: 14)).foregroundStyle(KB.dim)
                                Spacer()
                                Text(appVersion).font(.system(size: 14)).foregroundStyle(KB.text)
                            }
                            .padding(.vertical, 4)
                        }
                        Color.clear.frame(height: 80)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                HStack {
                    Text("我的")
                        .font(.system(size: 28, weight: .bold)).foregroundStyle(KB.text)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(KB.bg)
            }
            .sheet(isPresented: $showImport) { importSheet }
            .onAppear { refreshNotifyStatus() }
            .sheet(item: $pending) { p in importConfirmSheet(p) }
            .sheet(item: $shareItem) { item in
                ShareSheet(url: item.url)
            }
            .sheet(isPresented: $showManual) {
                ManualEntryEditorView(preset: nil, onDone: { showManual = false })
            }
            .confirmationDialog("深色模式", isPresented: $showAppearance, titleVisibility: .visible) {
                ForEach(KBAppearance.allCases) { a in
                    Button(a.title) { appearance = a.rawValue }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("当前：\(KBAppearance(rawValue: appearance)?.title ?? "跟随系统")")
            }
            .alert("提示", isPresented: Binding(
                get: { toast != nil },
                set: { if !$0 { toast = nil } }
            )) {
                Button("好") { toast = nil }
            } message: { Text(toast ?? "") }
            .confirmationDialog("恢复上次导入前的数据？", isPresented: $confirmRestore,
                                titleVisibility: .visible) {
                Button("恢复", role: .destructive) {
                    do { try store.restoreBackup(); toast = "已恢复" }
                    catch { toast = "恢复失败：\(error.localizedDescription)" }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("当前数据会被备份内容覆盖。")
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var profileCard: some View {
        Card {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(KB.accentSoft).frame(width: 54, height: 54)
                    Text(String(store.currentBaby?.name.prefix(1) ?? "宝"))
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(KB.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.currentBaby?.name ?? "宝贝")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(KB.text)
                    if let bd = store.currentBaby?.birthday {
                        Text("生日 \(KBDate.cnFull.string(from: bd))")
                            .font(.system(size: 12)).foregroundStyle(KB.dim)
                    } else {
                        Text("未设置生日").font(.system(size: 12)).foregroundStyle(KB.dim)
                    }
                }
                Spacer()
                NavigationLink { BabyManageView() } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14)).foregroundStyle(KB.dim)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var statCard: some View {
        let list = store.courses(for: store.scope)
        let remain = list.reduce(0) { $0 + store.remaining($1) }
        return Card {
            HStack(spacing: 0) {
                StatTile(value: "\(list.count)", label: "总课程")
                Divider().frame(height: 34)
                StatTile(value: "\(store.monthConsumed(store.scope))", label: "本月课时")
                Divider().frame(height: 34)
                StatTile(value: "\(remain)", label: "剩余课时")
            }
        }
    }

    @ViewBuilder
    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium)).foregroundStyle(KB.dim)
                .padding(.leading, 4)
            Card(padding: 0) {
                VStack(spacing: 0) { content() }
            }
        }
    }

    @ViewBuilder
    private func row(_ icon: String, _ title: String, _ sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15)).foregroundStyle(KB.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(KB.text)
                    Text(sub).font(.system(size: 11)).foregroundStyle(KB.dim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(KB.line)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    private func navBaby() -> some View {
        navRow("person.2", "宝贝管理", "查看、添加、编辑宝贝档案") { BabyManageView() }
    }

    private func navCourse() -> some View {
        navRow("book.closed", "课程管理", "查看、新增、编辑课程") { CourseManageView() }
    }

    @ViewBuilder
    private func navRow<D: View>(_ icon: String, _ title: String, _ sub: String,
                                 @ViewBuilder dest: () -> D) -> some View {
        NavigationLink { dest() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15)).foregroundStyle(KB.accent).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(KB.text)
                    Text(sub).font(.system(size: 11)).foregroundStyle(KB.dim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(KB.line)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    private func navLedger() -> some View {
        NavigationLink {
            RecordsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 15)).foregroundStyle(KB.accent).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("记录").font(.system(size: 15, weight: .medium)).foregroundStyle(KB.text)
                    Text("课时／缴费／打卡记录").font(.system(size: 11)).foregroundStyle(KB.dim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(KB.line)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func navAnalytics() -> some View {
        NavigationLink {
            AnalyticsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 15)).foregroundStyle(KB.accent).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("数据分析").font(.system(size: 15, weight: .medium)).foregroundStyle(KB.text)
                    Text("消耗统计与支出估算").font(.system(size: 11)).foregroundStyle(KB.dim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(KB.line)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    private var importSheet: some View {
        NavigationStack {
            ZStack {
                KB.bg.ignoresSafeArea()
                VStack(spacing: 14) {
                    Text("选择导出的 .xlsx 文件，导入后覆盖当前全部数据")
                        .font(.system(size: 13)).foregroundStyle(KB.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    KBButton(title: "选择 Excel 文件", icon: "folder") { showPicker = true }
                }
                .padding(16)
            }
            .navigationTitle("导入 Excel")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: [.init(filenameExtension: "xlsx") ?? .data]) { result in
                handleImport(result)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showImport = false }
                }
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let p = try store.parseXLSX(Data(contentsOf: url))
            showImport = false
            // 等导入 sheet 完全消失再弹确认页，避免同帧切换 sheet 丢失
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { pending = p }
        } catch {
            toast = "导入失败：\(error.localizedDescription)"
        }
    }

    /// 导入确认：先展示解析结果，确认后才覆盖
    private func importConfirmSheet(_ p: Store.ImportPreview) -> some View {
        NavigationStack {
            ZStack {
                KB.bg.ignoresSafeArea()
                VStack(spacing: 14) {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("即将导入").font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                            Text(p.summary).font(.system(size: 14)).foregroundStyle(KB.text)
                            Text("当前数据：宝贝 \(store.babies.count) · 课程 \(store.courses.count) · 流水 \(store.ledger.count)")
                                .font(.system(size: 12)).foregroundStyle(KB.dim)
                            Text("覆盖前会自动备份当前数据，可在「我的 → 备份与恢复」里恢复。")
                                .font(.system(size: 12)).foregroundStyle(KB.dim)
                        }
                    }
                    KBButton(title: "确认覆盖导入", icon: "exclamationmark.triangle.fill") {
                        store.commitImport(p)
                        pending = nil
                        toast = "导入成功"
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("确认导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { pending = nil }
                }
            }
        }
    }

    private func exportAll() { share(store.exportXLSX(), name: "课时宝-全部") }

    /// 导出单个课程（课程详情页复用）
    static func writeFile(_ data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).xlsx")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url
    }

    private func share(_ data: Data, name: String) {
        guard let url = Self.writeFile(data, name: name) else {
            toast = "导出失败：无法写入文件"; return
        }
        shareItem = ShareItem(url: url)
    }

    struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }
}

/// 系统分享面板（用于导出文件）
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ v: UIActivityViewController, context: Context) {}
}
