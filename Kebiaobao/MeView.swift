import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MeView: View {
    @EnvironmentObject var store: Store
    @State private var sheet: MeSheet?
    @State private var showImport = false
    @State private var showAppearance = false
    @AppStorage("kb.appearance") private var appearance = KBAppearance.system.rawValue
    @State private var showManual = false
    @State private var showPicker = false
    @State private var shareItem: ShareItem?
    @State private var toast: String?

    enum MeSheet: Identifiable {
        case baby, newBaby, addCourse
        var id: String {
            switch self {
            case .baby: return "b"
            case .newBaby: return "nb"
            case .addCourse: return "c"
            }
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
                            row("person.crop.circle", "宝贝管理", "编辑当前宝贝档案") { sheet = .baby }
                            row("person.badge.plus", "添加宝贝", "新增一个宝贝档案") { sheet = .newBaby }
                            row("book.closed", "课程管理", "新增课程、续费记录") { sheet = .addCourse }
                            row("plus.circle.fill", "手动记账", "不限日期，直接加／扣课时") {
                                showManual = true
                            }
                            navLedger()
                            navAnalytics()                        }
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
                                "选择 .xlsx 文件，覆盖当前数据") { showImport = true }
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
            .sheet(item: $sheet) { s in
                switch s {
                case .baby: BabyEditorView(baby: store.currentBaby)
                case .newBaby: BabyEditorView(baby: nil)
                case .addCourse: CourseEditorView(course: nil)
                }
            }
            .sheet(isPresented: $showImport) { importSheet }
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
                Button { sheet = .baby } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14)).foregroundStyle(KB.dim)
                }
            }
        }
    }

    private var statCard: some View {
        let list = store.courses(for: store.currentBabyID)
        let remain = list.reduce(0) { $0 + store.remaining($1) }
        return Card {
            HStack(spacing: 0) {
                StatTile(value: "\(list.count)", label: "总课程")
                Divider().frame(height: 34)
                StatTile(value: "\(store.monthConsumed(store.currentBabyID))", label: "本月课时")
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

    private func navLedger() -> some View {
        NavigationLink {
            LedgerListView(courseID: nil)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 15)).foregroundStyle(KB.accent).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("课时流水").font(.system(size: 15, weight: .medium)).foregroundStyle(KB.text)
                    Text("查看扣费／充值明细").font(.system(size: 11)).foregroundStyle(KB.dim)
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
            try store.importXLSX(Data(contentsOf: url))
            showImport = false
            toast = "导入成功"
        } catch {
            toast = "导入失败：\(error.localizedDescription)"
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
