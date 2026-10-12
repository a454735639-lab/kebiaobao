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
    /// 解析完暂存，等导入 sheet 关闭后交给确认页
    @State private var stashed: Store.ImportPreview?
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
        let remain = Dictionary(store.courses.map { ($0.id, max(0, store.remaining($0))) }, uniquingKeysWith: { a, _ in a })
        CalendarSync.sync(templates: store.templates, courses: store.courses, remaining: remain,
                          babyNames: Dictionary(store.babies.map { ($0.id, $0.name) },
                                                uniquingKeysWith: { a, _ in a }),
                          skipHolidays: store.skipHolidays) { r in
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
                        if store.loadFailed { loadFailedBanner }
                        profileCard
                        statCard
                        group("数据管理") {
                            navBaby()
                            navCourse()
                            row("plus.circle.fill", "手动记账", "不限日期，手动加课时或打卡") {
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
                            toggleRow("calendar.badge.exclamationmark", "法定节假日不排课",
                                      "节假日当天不显示课、不写日历（排课提醒仍按星期）。单张课可在课程编辑里设为照常上课",
                                      isOn: $store.skipHolidays)
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
                                Text("版本").font(.system(.subheadline)).foregroundStyle(KB.dim)
                                Spacer()
                                Text(appVersion).font(.system(.subheadline)).foregroundStyle(KB.text)
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
                        .font(.system(.title, weight: .bold)).foregroundStyle(KB.text)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(KB.bg)
            }
            .sheet(isPresented: $showImport, onDismiss: {
                if let p = stashed { stashed = nil; pending = p }
            }) { importSheet }
            .onAppear { refreshNotifyStatus() }
            // 开关变动后重写日历，否则关了「节假日不排课」日历仍是旧的跳过结果
            .onChange(of: store.skipHolidays) { _, _ in
                if calendarSync { syncCalendar() }
            }
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

    /// 本地数据无法解析时的提示条：阻止静默写盘，给出唯一的安全出口（从备份恢复）
    private var loadFailedBanner: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("本地数据读取失败", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.subheadline, weight: .semibold)).foregroundStyle(KB.danger)
                Text("原文件已另存为 kebiaobao.bad.json。为避免覆盖，本次启动不再写入任何改动。")
                    .font(.system(.caption)).foregroundStyle(KB.dim)
                if store.hasBackup {
                    KBButton(title: "从备份恢复", icon: "arrow.counterclockwise") {
                        do { try store.restoreBackup(); toast = "已从备份恢复" }
                        catch { toast = "恢复失败：\(error.localizedDescription)" }
                    }
                } else {
                    Text("没有可用备份，请通过「导入 Excel」重建数据。")
                        .font(.system(.caption)).foregroundStyle(KB.dim)
                }
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
                    Circle().fill(KB.accentGradient).frame(width: 54, height: 54)
                    Text(String(store.currentBaby?.name.prefix(1) ?? "宝"))
                        .font(.system(.title2, weight: .bold)).foregroundStyle(KB.onAccent)
                }
                .shadow(color: KB.accent.opacity(0.28), radius: 7, x: 0, y: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.currentBaby?.name ?? "宝贝")
                        .font(.system(.title3, weight: .bold)).foregroundStyle(KB.text)
                    if let bd = store.currentBaby?.birthday {
                        Text("生日 \(KBDate.cnFull.string(from: bd))")
                            .font(.system(.caption)).foregroundStyle(KB.dim)
                    } else {
                        Text("未设置生日").font(.system(.caption)).foregroundStyle(KB.dim)
                    }
                }
                Spacer()
                NavigationLink { BabyManageView() } label: {
                    Image(systemName: "pencil")
                        .font(.system(.subheadline)).foregroundStyle(KB.dim)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("宝贝管理")
            }
        }
    }

    private var statCard: some View {
        let list = store.courses(for: store.scope)
        let remain = store.totalRemaining(babyID: store.scope)
        return HStack(spacing: 0) {
            heroStat("\(list.count)", "总课程")
            heroDivider
            heroStat("\(store.monthConsumed(store.scope))", "本月课时")
            heroDivider
            heroStat("\(remain)", "剩余课时", warn: remain <= 3)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(KB.accentGradient)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: KB.accent.opacity(0.30), radius: 12, x: 0, y: 6)
    }

    private func heroStat(_ value: String, _ label: String, warn: Bool = false) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(warn ? KB.onAccentWarn : KB.onAccent)
            Text(label)
                .font(.system(.caption2, weight: .medium))
                .foregroundStyle(KB.onAccent.opacity(0.92))
        }
        .frame(maxWidth: .infinity)
    }

    private var heroDivider: some View {
        Rectangle().fill(KB.onAccent.opacity(0.22)).frame(width: 1, height: 32)
    }

    @ViewBuilder
    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: groupIcon(title))
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(KB.accent.opacity(0.8))
                Text(title)
                    .font(.system(.caption, weight: .semibold)).foregroundStyle(KB.dim)
            }
            .padding(.leading, 4)
            Card(padding: 0) {
                VStack(spacing: 0) { content() }
            }
        }
    }

    private func groupIcon(_ title: String) -> String {
        switch title {
        case "数据管理": return "square.stack.3d.up.fill"
        case "提醒": return "bell.badge.fill"
        case "外观": return "paintbrush.fill"
        case "备份与恢复": return "externaldrive.fill"
        case "关于": return "info.circle.fill"
        default: return "circle.fill"
        }
    }

    @ViewBuilder
    private func row(_ icon: String, _ title: String, _ sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(.subheadline)).foregroundStyle(KB.accent)
                    .frame(minWidth: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.subheadline, weight: .medium)).foregroundStyle(KB.text)
                    Text(sub).font(.system(.caption2)).foregroundStyle(KB.dim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .semibold)).foregroundStyle(KB.line)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    /// 带开关的行（用于「法定节假日不排课」这类规则）
    private func toggleRow(_ icon: String, _ title: String, _ sub: String,
                           isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(.subheadline)).foregroundStyle(KB.accent)
                .frame(minWidth: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.subheadline, weight: .medium)).foregroundStyle(KB.text)
                Text(sub).font(.system(.caption2)).foregroundStyle(KB.dim)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(KB.accent)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
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
                IconBadge(icon: icon, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.subheadline, weight: .medium)).foregroundStyle(KB.text)
                    Text(sub).font(.system(.caption2)).foregroundStyle(KB.dim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .semibold)).foregroundStyle(KB.line)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    private func navLedger() -> some View {
        navRow("list.bullet.rectangle", "记录", "课时／缴费／打卡记录") { RecordsView() }
    }

    @ViewBuilder
    private func navAnalytics() -> some View {
        navRow("chart.bar.xaxis", "数据分析", "消耗统计与支出估算") { AnalyticsView() }
    }

    private var importSheet: some View {
        NavigationStack {
            ZStack {
                KB.bg.ignoresSafeArea()
                VStack(spacing: 14) {
                    Text("选择导出的 .xlsx 文件，导入后覆盖当前全部数据")
                        .font(.system(.caption)).foregroundStyle(KB.dim)
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
            // 暂存解析结果，等导入 sheet 真正消失后由 onDismiss 同步弹出确认页。
            // 原来的做法是延后 0.35s 赋值，用户若先关掉 sheet 数据就悄悄丢了。
            stashed = p
            showImport = false
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
                            Text("即将导入").font(.system(.subheadline, weight: .semibold)).foregroundStyle(KB.text)
                            Text(p.summary).font(.system(.subheadline)).foregroundStyle(KB.text)
                            Text("当前数据：宝贝 \(store.babies.count) · 课程 \(store.courses.count) · 流水 \(store.ledger.count)")
                                .font(.system(.caption)).foregroundStyle(KB.dim)
                            Text("覆盖前会自动备份当前数据，可在「我的 → 备份与恢复」里恢复。")
                                .font(.system(.caption)).foregroundStyle(KB.dim)
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
