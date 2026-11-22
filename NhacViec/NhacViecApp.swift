import SwiftUI
import Charts
import UIKit
import UserNotifications

// MARK: - Hạng mục (đúng thứ tự các ô trên màn hình chính)

struct Cat: Identifiable, Hashable {
    let id: String, title: String, icon: String, color: Color
    var name: String { title.replacingOccurrences(of: "\n", with: " ") }
}

let allCats: [Cat] = [
    Cat(id: "testroom", title: "Công việc\nkhu vực Test Room", icon: "testtube.2", color: .teal),
    Cat(id: "recheck", title: "Công việc\nkhu vực Recheck", icon: "checklist.checked", color: .blue),
    Cat(id: "cutting", title: "Công việc\nkhu vực Cutting", icon: "gearshape.2.fill", color: .green),
    Cat(id: "abnormal", title: "Xử lý\nbất thường", icon: "light.beacon.max.fill", color: .red),
    Cat(id: "error", title: "Lỗi cần chú ý", icon: "exclamationmark.triangle.fill", color: .orange),
    Cat(id: "important", title: "Công việc\nquan trọng", icon: "star.fill", color: .purple),
    Cat(id: "todo", title: "Công việc\ncần làm", icon: "square.and.pencil", color: .green),
    Cat(id: "research", title: "Công việc\nnghiên cứu", icon: "desktopcomputer", color: .cyan),
    Cat(id: "other", title: "Công việc\nkhác", icon: "square.grid.2x2.fill", color: .indigo),
    Cat(id: "handover", title: "Bàn giao ca", icon: "hands.clap.fill", color: .mint),
    Cat(id: "meeting", title: "Họp đầu ca", icon: "person.3.fill", color: .purple),
    Cat(id: "boss", title: "Công việc\nsếp giao", icon: "person.crop.rectangle.fill", color: .orange),
    Cat(id: "training", title: "Công việc\nđào tạo", icon: "person.fill.viewfinder", color: .blue),
]

/// Nạp ảnh PNG thường nằm trong app (không dùng Assets.xcassets)
func bundleImage(_ name: String) -> Image {
    if let u = UIImage(named: name) { return Image(uiImage: u) }
    return Image(systemName: "photo")
}

func catOf(_ id: String) -> Cat { allCats.first { $0.id == id } ?? allCats[0] }

func minutesOfDay(_ d: Date) -> Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

// MARK: - Cài đặt (lưu trong UserDefaults)

enum Prefs {
    static let areas = ["recheck", "cutting", "testroom"]
    static var notifOn: Bool { UserDefaults.standard.object(forKey: "notifOn") as? Bool ?? true }
    static var soundOn: Bool { UserDefaults.standard.object(forKey: "soundOn") as? Bool ?? true }
    static var vibrateOn: Bool { UserDefaults.standard.object(forKey: "vibrateOn") as? Bool ?? true }
    /// "recheck" / "cutting" / "testroom" hoặc "none" (không lọc khu vực)
    static var area: String { UserDefaults.standard.string(forKey: "area") ?? "recheck" }

    /// Đã chọn 1 khu vực thì 2 khu vực còn lại bị tắt thông báo; các hạng mục khác vẫn nhắc bình thường.
    static func shouldNotify(_ catID: String) -> Bool {
        guard notifOn else { return false }
        if areas.contains(catID), area != "none", catID != area { return false }
        return true
    }
}

// MARK: - Model

enum Mode: String, Codable, CaseIterable {
    case once = "1 lần", daily = "Hằng ngày", weekly = "Theo thứ"
    case monthly = "Hằng tháng", yearly = "Hằng năm", multi = "Nhiều giờ"

    var badge: String {
        switch self {
        case .once: return "1 lần"
        case .daily: return "Hàng ngày"
        case .weekly: return "Hàng tuần"
        case .monthly: return "Hàng tháng"
        case .yearly: return "Hàng năm"
        case .multi: return "Nhiều giờ"
        }
    }
}

struct TaskItem: Identifiable, Codable {
    var id = UUID()
    var catID: String
    var title = ""
    var place: String? = nil
    var time = Date()                   // 1 lần/hằng năm: ngày + giờ; còn lại chỉ dùng giờ:phút
    var mode: Mode = .once
    var weekdays: Set<Int> = []         // 1 = CN ... 7 = T7
    var monthDay = 1
    var doneAt: Date? = nil
    var endTime: Date? = nil            // kiểu "Nhiều giờ": từ time đến endTime, mỗi everyHours giờ
    var everyHours: Int? = nil
    var slotsDone: Int? = nil
    var slotsDay: Date? = nil

    var isRecurring: Bool { mode != .once }

    var slotMinutes: [Int] {
        guard mode == .multi else { return [] }
        let s = minutesOfDay(time), e = minutesOfDay(endTime ?? time), step = max(1, everyHours ?? 1) * 60
        guard e >= s else { return [s] }
        return Array(stride(from: s, through: e, by: step).prefix(24))
    }
    var dueMinutes: [Int] { mode == .multi ? slotMinutes : [minutesOfDay(time)] }

    var doneToday: Int {
        guard let d = slotsDay, Calendar.current.isDateInToday(d) else { return 0 }
        return slotsDone ?? 0
    }

    /// Tích xong: việc 1 lần ẩn hẳn; ngày/thứ/nhiều giờ ẩn đến hôm sau; tháng ẩn đến tháng sau; năm ẩn đến năm sau.
    var isHidden: Bool {
        guard let d = doneAt else { return false }
        let c = Calendar.current
        switch mode {
        case .once: return true
        case .daily, .weekly, .multi: return c.isDateInToday(d)
        case .monthly: return c.isDate(d, equalTo: Date(), toGranularity: .month)
        case .yearly: return c.isDate(d, equalTo: Date(), toGranularity: .year)
        }
    }

    func occurs(on d: Date) -> Bool {
        let c = Calendar.current
        switch mode {
        case .once: return c.isDate(time, inSameDayAs: d)
        case .daily, .multi: return true
        case .weekly: return weekdays.contains(c.component(.weekday, from: d))
        case .monthly: return c.component(.day, from: d) == monthDay
        case .yearly:
            return c.component(.month, from: d) == c.component(.month, from: time)
                && c.component(.day, from: d) == c.component(.day, from: time)
        }
    }

    var subtitle: String {
        let f = DateFormatter()
        f.dateFormat = (mode == .once || mode == .yearly) ? "dd/MM HH:mm" : "HH:mm"
        let t = f.string(from: time)
        var s: String
        switch mode {
        case .once, .daily, .yearly: s = t
        case .weekly:
            let n = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"]
            s = "\(t) · " + weekdays.sorted().map { n[$0 - 1] }.joined(separator: ", ")
        case .monthly: s = "\(t) · Ngày \(monthDay)"
        case .multi:
            let ts = slotMinutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }
            s = "\(ts.first ?? "") – \(ts.last ?? "") · mỗi \(everyHours ?? 1)h · \(doneToday)/\(ts.count)"
        }
        if let p = place, !p.isEmpty { s += " • " + p }
        return s
    }
}

struct DoneLog: Codable { var taskID: UUID; var catID: String; var date: Date }

// MARK: - Thông báo (chạy nền, không cần mở app)

enum Notifier {
    static func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    static func ids(_ t: TaskItem) -> [String] {
        (1...7).map { "\(t.id)-w\($0)" } + ["\(t.id)-once", "\(t.id)-daily", "\(t.id)-month", "\(t.id)-year"]
            + (0..<24).map { "\(t.id)-s\($0)" }
    }
    static func cancel(_ t: TaskItem) {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: ids(t))
        c.removeDeliveredNotifications(withIdentifiers: ids(t))
    }
    static func schedule(_ t: TaskItem) {
        cancel(t)
        guard Prefs.shouldNotify(t.catID) else { return }   // khu vực không được chọn: tắt thông báo
        let c = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = catOf(t.catID).name
        content.body = t.title
        content.sound = Prefs.soundOn ? UNNotificationSound.default : nil
        content.interruptionLevel = (t.catID == "abnormal" || t.catID == "important") ? .timeSensitive : .active

        func add(_ id: String, _ dc: DateComponents, repeats: Bool) {
            c.add(UNNotificationRequest(identifier: id, content: content,
                                        trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: repeats)))
        }
        let hm = Calendar.current.dateComponents([.hour, .minute], from: t.time)
        switch t.mode {
        case .once:
            if t.doneAt == nil, t.time > Date() {
                add("\(t.id)-once", Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: t.time), repeats: false)
            }
        case .daily: add("\(t.id)-daily", hm, repeats: true)
        case .weekly:
            for wd in t.weekdays { var dc = hm; dc.weekday = wd; add("\(t.id)-w\(wd)", dc, repeats: true) }
        case .monthly:
            var dc = hm; dc.day = t.monthDay; add("\(t.id)-month", dc, repeats: true)
        case .yearly:
            add("\(t.id)-year", Calendar.current.dateComponents([.month, .day, .hour, .minute], from: t.time), repeats: true)
        case .multi:
            for (i, m) in t.slotMinutes.enumerated() {
                var dc = DateComponents(); dc.hour = m / 60; dc.minute = m % 60
                add("\(t.id)-s\(i)", dc, repeats: true)
            }
        }
    }
}

// MARK: - Lưu trữ

final class Store: ObservableObject {
    @Published var tasks: [TaskItem] = [] { didSet { save() } }
    @Published var log: [DoneLog] = [] { didSet { save() } }

    init() {
        let u = UserDefaults.standard
        if let d = u.data(forKey: "tasks.v3"), let l = try? JSONDecoder().decode([TaskItem].self, from: d) { tasks = l }
        if let d = u.data(forKey: "log.v3"), let l = try? JSONDecoder().decode([DoneLog].self, from: d) { log = l }
    }
    private func save() {
        let u = UserDefaults.standard
        if let d = try? JSONEncoder().encode(tasks) { u.set(d, forKey: "tasks.v3") }
        if let d = try? JSONEncoder().encode(log) { u.set(d, forKey: "log.v3") }
    }

    func todayPending() -> [TaskItem] { tasks.filter { !$0.isHidden && $0.occurs(on: Date()) } }
    func upsert(_ t: TaskItem) {
        if let i = tasks.firstIndex(where: { $0.id == t.id }) { tasks[i] = t } else { tasks.append(t) }
        Notifier.schedule(t)
    }
    func delete(_ t: TaskItem) { Notifier.cancel(t); tasks.removeAll { $0.id == t.id } }
    func rescheduleAll() { tasks.forEach { Notifier.schedule($0) } }

    func toggle(_ t: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == t.id }) else { return }
        log.append(DoneLog(taskID: t.id, catID: t.catID, date: Date()))
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Notifier.ids(t))
        if tasks[i].mode == .multi {
            let n = tasks[i].doneToday + 1
            tasks[i].slotsDone = n; tasks[i].slotsDay = Date()
            if n >= tasks[i].slotMinutes.count { tasks[i].doneAt = Date() }
            return
        }
        tasks[i].doneAt = Date()
        if !tasks[i].isRecurring { Notifier.cancel(tasks[i]) }
    }
    /// Lỡ tích nhầm: bỏ tích
    func undo(_ t: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == t.id }) else { return }
        if let k = log.lastIndex(where: { $0.taskID == t.id }) { log.remove(at: k) }
        if tasks[i].mode == .multi {
            tasks[i].slotsDone = max(0, tasks[i].doneToday - 1); tasks[i].slotsDay = Date()
            tasks[i].doneAt = nil
            return
        }
        tasks[i].doneAt = nil
        Notifier.schedule(tasks[i])
    }
}

// MARK: - Điều hướng

enum AppTab: CaseIterable {
    case home, stats, settings
    var title: String { self == .home ? "Trang chủ" : (self == .stats ? "Thống kê" : "Cài đặt") }
    var icon: String { self == .home ? "house.fill" : (self == .stats ? "chart.bar.fill" : "gearshape.fill") }
}
enum Route: Hashable { case cat(Cat), all }

final class AppState: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var path: [Route] = []
}

@main
struct NhacViecApp: App {
    @StateObject private var store = Store()
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var phase
    init() { Notifier.requestAuth() }

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environmentObject(app)
                .onChange(of: phase) { _, p in if p == .active { store.objectWillChange.send() } }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        switch app.tab {
        case .home: HomeStack()
        case .stats: StatsView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - Thành phần giao diện chung

struct SkyBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.30, green: 0.62, blue: 1.0), Color(red: 0.62, green: 0.84, blue: 1.0),
                                Color(red: 0.88, green: 0.96, blue: 1.0)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

struct HeaderBar: View {
    @EnvironmentObject var store: Store
    let title: String, subtitle: String
    var back: (() -> Void)? = nil
    var onBell: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let back {
                Button(action: back) {
                    Image(systemName: "arrow.left").font(.title3.bold()).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Circle().fill(Color.blue.gradient))
                }
            } else { Color.clear.frame(width: 44, height: 44) }
            VStack(spacing: 2) {
                Text(title).font(.title3.bold()).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                Text(subtitle).font(.caption2.bold()).foregroundStyle(.white.opacity(0.9)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(Capsule().fill(Color.blue.gradient))
            Button { onBell?() } label: {
                Image(systemName: "bell.fill").font(.title3).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Circle().fill(Color.blue.gradient))
                    .overlay(alignment: .topTrailing) {
                        let n = store.todayPending().count
                        if n > 0 {
                            Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                .frame(minWidth: 18, minHeight: 18).background(.red, in: Circle())
                        }
                    }
            }
        }
        .padding(.horizontal, 12)
    }
}

struct BottomBar: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        HStack {
            ForEach(AppTab.allCases, id: \.self) { t in
                let selected = app.path.isEmpty && app.tab == t
                Button { app.path = []; app.tab = t } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.title2)
                        Text(t.title).font(.footnote.bold())
                        Rectangle().fill(selected ? Color.blue : Color.clear).frame(height: 3).padding(.horizontal, 10)
                    }
                    .foregroundStyle(Color(red: 0.05, green: 0.3, blue: 0.8)).frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 8)
        .background(.white.opacity(0.92), in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        .padding(.horizontal, 12).padding(.bottom, 4)
    }
}

// MARK: - Màn hình chính (dùng đúng ảnh thiết kế, ô bấm đặt lên ảnh)

struct PressStyle: ButtonStyle {
    let radius: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.3 : 0), in: RoundedRectangle(cornerRadius: radius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct HomeStack: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        NavigationStack(path: $app.path) {
            HomeView()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { r in
                    switch r {
                    case .cat(let c): TaskListView(cat: c)
                    case .all: TaskListView(cat: nil)
                    }
                }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var app: AppState
    private let W: CGFloat = 942, H: CGFloat = 1670
    private let navy = Color(red: 0.05, green: 0.25, blue: 0.75)

    /// Vùng bấm 13 ô theo thứ tự allCats (toạ độ trên ảnh gốc)
    private let rects: [CGRect] = [
        (25, 435, 325, 625), (332, 435, 620, 625), (627, 435, 918, 625),
        (28, 633, 468, 805), (476, 633, 918, 805),
        (28, 813, 468, 975), (475, 813, 915, 975),
        (28, 982, 468, 1133), (475, 982, 915, 1133),
        (30, 1140, 468, 1272), (475, 1140, 915, 1272),
        (30, 1280, 468, 1415), (475, 1280, 915, 1415),
    ].map { CGRect(x: $0.0, y: $0.1, width: $0.2 - $0.0, height: $0.3 - $0.1) }

    private let tabRects: [(AppTab, CGRect)] = [
        (.home, CGRect(x: 20, y: 1530, width: 305, height: 120)),
        (.stats, CGRect(x: 330, y: 1530, width: 290, height: 120)),
        (.settings, CGRect(x: 625, y: 1530, width: 295, height: 120)),
    ]

    var body: some View {
        ZStack {
            Color(red: 0.55, green: 0.85, blue: 1.0).ignoresSafeArea()
            VStack(spacing: 0) {
                bundleImage("poster_top").resizable().frame(height: 160)
                Spacer(minLength: 0)
                bundleImage("poster_bottom").resizable().frame(height: 420)
            }
            .ignoresSafeArea()

            GeometryReader { geo in
                let s = min(geo.size.width / W, geo.size.height / H)   // co vừa màn hình
                poster(s)
                    .frame(width: W * s, height: H * s, alignment: .topLeading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    func poster(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            bundleImage("poster").resizable().frame(width: W * s, height: H * s)

            TimelineView(.periodic(from: .now, by: 20)) { ctx in
                HStack(spacing: 0) {
                    Image(systemName: "calendar").font(.system(size: 36 * s)).foregroundStyle(navy)
                    Text(dateText(ctx.date)).font(.system(size: 27 * s, weight: .bold)).foregroundStyle(navy)
                        .lineLimit(1).minimumScaleFactor(0.5).padding(.leading, 16 * s)
                    Spacer()
                    Rectangle().fill(navy.opacity(0.6)).frame(width: 3 * s, height: 48 * s)
                    Spacer()
                    Image(systemName: "clock").font(.system(size: 44 * s)).foregroundStyle(navy)
                    Text(timeText(ctx.date)).font(.system(size: 50 * s, weight: .heavy)).foregroundStyle(navy)
                        .padding(.leading, 14 * s)
                }
                .padding(.horizontal, 44 * s)
                .frame(width: 774 * s, height: 74 * s)
                .background(Capsule().fill(Color(red: 0.93, green: 0.97, blue: 1.0)))
                .overlay(Capsule().stroke(.white, lineWidth: 2 * s))
            }
            .position(x: 471 * s, y: 399 * s)

            ForEach(Array(allCats.enumerated()), id: \.element.id) { i, cat in
                let r = rects[i]
                let n = store.todayPending().filter { $0.catID == cat.id }.count
                Button { app.path.append(.cat(cat)) } label: {
                    Color.clear
                        .frame(width: r.width * s, height: r.height * s)
                        .contentShape(Rectangle())
                        .overlay(alignment: .topTrailing) {
                            if n > 0 {
                                Text("\(n)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                    .frame(minWidth: 22, minHeight: 22).background(.red, in: Circle()).padding(6)
                            }
                        }
                }
                .buttonStyle(PressStyle(radius: 26 * s))
                .position(x: r.midX * s, y: r.midY * s)
            }

            ForEach(tabRects, id: \.0) { t, r in
                Button { app.tab = t } label: {
                    Color.clear.frame(width: r.width * s, height: r.height * s).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(radius: 30 * s))
                .position(x: r.midX * s, y: r.midY * s)
            }
        }
    }

    func dateText(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "EEEE, dd/MM/yyyy"
        return f.string(from: d).capitalized
    }
    func timeText(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
}

// MARK: - Danh sách công việc (theo thiết kế: Hôm nay / Ngày mai / Hàng tuần / tháng / năm)

struct Sec: Identifiable {
    let id: String, title: String
    let color: Color
    let items: [TaskItem]
    let canTick: Bool
    var remaining: String? = nil
}

struct TaskListView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var app: AppState
    let cat: Cat?

    enum F: String, CaseIterable {
        case all = "Tất cả", day = "Theo ngày", week = "Theo tuần", month = "Theo tháng", year = "Theo năm"
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2.fill"
            case .day: return "sun.max.fill"
            case .week: return "calendar.badge.clock"
            case .month: return "calendar"
            case .year: return "gift.fill"
            }
        }
    }
    @State private var f: F = .all
    @State private var search = ""
    @State private var catFilter: String? = nil
    @State private var editing: TaskItem?

    private func match(_ t: TaskItem) -> Bool {
        if let c = cat, t.catID != c.id { return false }
        if cat == nil, let cf = catFilter, t.catID != cf { return false }
        if !search.isEmpty && !t.title.localizedCaseInsensitiveContains(search) { return false }
        switch f {
        case .all: return true
        case .day: return [Mode.once, .daily, .multi].contains(t.mode)
        case .week: return t.mode == .weekly
        case .month: return t.mode == .monthly
        case .year: return t.mode == .yearly
        }
    }
    private func byTime(_ a: TaskItem, _ b: TaskItem) -> Bool { minutesOfDay(a.time) < minutesOfDay(b.time) }

    private func remaining(_ items: [TaskItem]) -> String? {
        let now = minutesOfDay(Date())
        guard let n = items.flatMap({ $0.dueMinutes }).filter({ $0 >= now }).min() else { return nil }
        let d = n - now
        return d >= 60 ? "Còn lại: \(d / 60)h \(d % 60)p" : "Còn lại: \(d)p"
    }

    private var sections: [Sec] {
        let now = Date(), tom = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        let all = store.tasks.filter(match)
        let today = all.filter { !$0.isHidden && $0.occurs(on: now) }.sorted(by: byTime)
        let tomorrow = all.filter { $0.occurs(on: tom) && !($0.mode == .once && $0.doneAt != nil) }.sorted(by: byTime)
        func rest(_ m: Mode) -> [TaskItem] {
            all.filter { $0.mode == m && !$0.isHidden && !$0.occurs(on: now) && !$0.occurs(on: tom) }.sorted(by: byTime)
        }
        let list: [Sec] = [
            Sec(id: "today", title: "Công việc cần làm hôm nay", color: .blue, items: today, canTick: true, remaining: remaining(today)),
            Sec(id: "tom", title: "Công việc ngày mai", color: .green, items: tomorrow, canTick: false),
            Sec(id: "week", title: "Công việc hàng tuần", color: .purple, items: rest(.weekly), canTick: true),
            Sec(id: "month", title: "Công việc hàng tháng", color: .green, items: rest(.monthly), canTick: true),
            Sec(id: "year", title: "Công việc hàng năm", color: .pink, items: rest(.yearly), canTick: true),
            Sec(id: "later", title: "Công việc sắp tới", color: .orange, items: rest(.once), canTick: true),
        ]
        return list.filter { !$0.items.isEmpty }
    }
    private var dones: [TaskItem] {
        store.tasks.filter { match($0) && $0.isHidden }.sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SkyBackground()
            VStack(spacing: 10) {
                HeaderBar(title: cat?.name ?? "Công việc của tôi", subtitle: "Làm đúng việc – Đúng thời gian – Hiệu quả cao",
                          back: { if !app.path.isEmpty { app.path.removeLast() } },
                          onBell: { if cat != nil { app.path = [.all] } })
                chips
                searchBar
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(sections) { sec in section(sec) }
                        if !dones.isEmpty { doneCard }
                        if sections.isEmpty && dones.isEmpty {
                            Text("Chưa có việc nào\nBấm + để thêm công việc").multilineTextAlignment(.center)
                                .foregroundStyle(.secondary).padding(.top, 60)
                        }
                        Color.clear.frame(height: 70)
                    }
                    .padding(.horizontal, 12)
                }
            }
            Button { editing = TaskItem(catID: cat?.id ?? "todo") } label: {
                Image(systemName: "plus").font(.title.bold()).foregroundStyle(.white)
                    .frame(width: 56, height: 56).background(Circle().fill(Color.blue.gradient)).shadow(radius: 4)
            }
            .padding(.trailing, 20).padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom) { BottomBar() }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { EditView(task: $0) }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(F.allCases, id: \.self) { x in
                    Button { f = x } label: {
                        Label(x.rawValue, systemImage: x.icon).font(.subheadline.bold())
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Capsule().fill(f == x ? Color.blue : Color.white.opacity(0.85)))
                            .foregroundStyle(f == x ? .white : Color(red: 0.05, green: 0.3, blue: 0.8))
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.blue)
                TextField("Tìm kiếm công việc...", text: $search)
            }
            .padding(10).background(.white.opacity(0.9), in: Capsule())
            if cat == nil {
                Menu {
                    Button("Tất cả hạng mục") { catFilter = nil }
                    ForEach(allCats) { c in Button(c.name) { catFilter = c.id } }
                } label: {
                    Label("Lọc", systemImage: "line.3.horizontal.decrease").font(.subheadline.bold())
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.white.opacity(0.9), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func section(_ sec: Sec) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sec.title).font(.headline).foregroundStyle(Color(red: 0.05, green: 0.3, blue: 0.8))
                Text("\(sec.items.count) việc").font(.caption.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(sec.color))
                Spacer()
                if let r = sec.remaining {
                    Label(r, systemImage: "clock").font(.caption.bold()).foregroundStyle(.green)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.green.opacity(0.15)))
                }
            }
            VStack(spacing: 0) {
                ForEach(sec.items) { t in row(t, tick: sec.canTick); if t.id != sec.items.last?.id { Divider() } }
            }
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 22).fill(sec.color.opacity(0.18)))
    }

    private var doneCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("✓ Đã làm (\(dones.count))").font(.headline).foregroundStyle(Color(red: 0.05, green: 0.3, blue: 0.8))
            VStack(spacing: 0) {
                ForEach(dones) { t in
                    HStack(spacing: 10) {
                        Button { withAnimation { store.undo(t) } } label: {
                            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(catOf(t.catID).color)
                        }.buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title).strikethrough().foregroundStyle(.secondary)
                            Text(t.subtitle + " · xong " + (t.doneAt?.formatted(date: .omitted, time: .shortened) ?? ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
                    .onTapGesture { editing = t }
                    if t.id != dones.last?.id { Divider() }
                }
            }
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.gray.opacity(0.18)))
    }

    @ViewBuilder
    private func row(_ t: TaskItem, tick: Bool) -> some View {
        let c = catOf(t.catID)
        HStack(spacing: 10) {
            if tick {
                Button { withAnimation { store.toggle(t) } } label: {
                    Image(systemName: "circle").font(.title2).foregroundStyle(c.color)
                }.buttonStyle(.plain)
            } else {
                Image(systemName: "clock").font(.title3).foregroundStyle(.secondary)
            }
            Image(systemName: c.icon).foregroundStyle(.white).frame(width: 34, height: 34)
                .background(c.color.gradient, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.subheadline.bold())
                Text(t.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if tick && t.mode == .multi && t.doneToday > 0 {
                Button { store.undo(t) } label: { Image(systemName: "arrow.uturn.backward") }.buttonStyle(.plain)
            }
            Text(t.mode.badge).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5)
                .background(c.color.opacity(0.18), in: Capsule()).foregroundStyle(c.color)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.blue)
        }
        .padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
        .onTapGesture { editing = t }
    }
}

// MARK: - Thêm / sửa việc

struct EditView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var task: TaskItem
    private let labels = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Công việc") {
                    TextField("Tên công việc", text: $task.title)
                    TextField("Nơi / phòng (không bắt buộc)", text: Binding(get: { task.place ?? "" }, set: { task.place = $0 }))
                    Picker("Hạng mục", selection: $task.catID) {
                        ForEach(allCats) { Text($0.name).tag($0.id) }
                    }
                }
                Section("Lặp lại") {
                    Picker("Kiểu", selection: $task.mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu)
                    DatePicker(task.mode == .multi ? "Từ giờ" : "Giờ nhắc", selection: $task.time,
                               displayedComponents: (task.mode == .once || task.mode == .yearly) ? [.date, .hourAndMinute] : [.hourAndMinute])
                    if task.mode == .weekly {
                        HStack {
                            ForEach(1...7, id: \.self) { d in
                                let on = task.weekdays.contains(d)
                                Text(labels[d - 1]).font(.footnote.bold())
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .background(on ? catOf(task.catID).color : Color.gray.opacity(0.15), in: Circle())
                                    .foregroundStyle(on ? .white : .primary)
                                    .onTapGesture { if on { task.weekdays.remove(d) } else { task.weekdays.insert(d) } }
                            }
                        }
                    }
                    if task.mode == .monthly {
                        Stepper("Ngày \(task.monthDay) hằng tháng", value: $task.monthDay, in: 1...31)
                    }
                    if task.mode == .multi {
                        DatePicker("Đến giờ", selection: Binding(get: { task.endTime ?? task.time }, set: { task.endTime = $0 }),
                                   displayedComponents: [.hourAndMinute])
                        Stepper("Mỗi \(task.everyHours ?? 2) giờ", value: Binding(get: { task.everyHours ?? 2 }, set: { task.everyHours = $0 }), in: 1...12)
                        Text("Nhắc lúc: " + task.slotMinutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }.joined(separator: ", "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if store.tasks.contains(where: { $0.id == task.id }) {
                    Section { Button("Xoá công việc", role: .destructive) { store.delete(task); dismiss() } }
                }
            }
            .onChange(of: task.mode) { _, m in
                if m == .multi {
                    if task.everyHours == nil { task.everyHours = 2 }
                    if task.endTime == nil { task.endTime = Calendar.current.date(byAdding: .hour, value: 8, to: task.time) }
                }
            }
            .navigationTitle("Công việc").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        task.doneAt = nil; task.slotsDone = 0
                        store.upsert(task); dismiss()
                    }
                    .disabled(task.title.trimmingCharacters(in: .whitespaces).isEmpty
                              || (task.mode == .weekly && task.weekdays.isEmpty))
                }
            }
        }
    }
}

// MARK: - Thống kê

struct DayStat: Identifiable { let id: String; let count: Int }

struct StatsView: View {
    @EnvironmentObject var store: Store

    private var cal: Calendar { Calendar.current }
    private var days: [DayStat] {
        let f = DateFormatter(); f.dateFormat = "dd/MM"
        return (0..<7).reversed().map { off in
            let d = cal.date(byAdding: .day, value: -off, to: Date()) ?? Date()
            return DayStat(id: f.string(from: d), count: store.log.filter { cal.isDate($0.date, inSameDayAs: d) }.count)
        }
    }
    private var weekLogs: [DoneLog] {
        let from = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date())) ?? Date()
        return store.log.filter { $0.date >= from }
    }

    var body: some View {
        let doneToday = store.log.filter { cal.isDateInToday($0.date) }.count
        let pendingToday = store.todayPending().count
        let total = doneToday + pendingToday
        ZStack {
            SkyBackground()
            VStack(spacing: 10) {
                HeaderBar(title: "Thống kê", subtitle: "Theo dõi tiến độ công việc của bạn")
                ScrollView {
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            card("Hôm nay", "\(doneToday)/\(total)", "đã làm", .blue)
                            card("7 ngày qua", "\(weekLogs.count)", "lượt hoàn thành", .green)
                            card("Tỷ lệ", total == 0 ? "–" : "\(doneToday * 100 / total)%", "hôm nay", .purple)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Hoàn thành 7 ngày gần nhất").font(.headline)
                            Chart(days) { d in
                                BarMark(x: .value("Ngày", d.id), y: .value("Số việc", d.count))
                                    .foregroundStyle(Color.blue.gradient)
                                    .annotation(position: .top) { if d.count > 0 { Text("\(d.count)").font(.caption2) } }
                            }
                            .frame(height: 180)
                        }
                        .padding(14).background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 18))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Theo hạng mục").font(.headline)
                            ForEach(allCats) { c in
                                let done = weekLogs.filter { $0.catID == c.id }.count
                                let left = store.tasks.filter { $0.catID == c.id && !$0.isHidden }.count
                                if done + left > 0 {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Image(systemName: c.icon).foregroundStyle(c.color)
                                            Text(c.name).font(.subheadline.bold())
                                            Spacer()
                                            Text("đã làm \(done) · còn \(left)").font(.caption).foregroundStyle(.secondary)
                                        }
                                        ProgressView(value: Double(done), total: Double(done + left)).tint(c.color)
                                    }
                                }
                            }
                            if store.tasks.isEmpty && store.log.isEmpty {
                                Text("Chưa có dữ liệu. Hãy thêm và hoàn thành vài công việc.").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding(14).background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
                        Color.clear.frame(height: 20)
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { BottomBar() }
    }

    private func card(_ t: String, _ v: String, _ s: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(t).font(.caption.bold()).foregroundStyle(.secondary)
            Text(v).font(.title2.bold()).foregroundStyle(c)
            Text(s).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Cài đặt

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var notifOn = Prefs.notifOn
    @State private var soundOn = Prefs.soundOn
    @State private var vibrateOn = Prefs.vibrateOn
    @State private var area = Prefs.area
    @State private var saved = false

    private let areaInfo: [(id: String, title: String, desc: String, img: String)] = [
        ("recheck", "Khu vực Recheck", "Khu vực kiểm tra lại sản phẩm theo tiêu chuẩn", "area_recheck"),
        ("cutting", "Khu vực Cutting", "Khu vực gia công cắt sản phẩm", "area_cutting"),
        ("testroom", "Khu vực Test Room", "Khu vực kiểm tra chất lượng và hiệu suất sản phẩm", "area_testroom"),
    ]

    var body: some View {
        ZStack {
            SkyBackground()
            VStack(spacing: 10) {
                HeaderBar(title: "Cài đặt", subtitle: "Tùy chỉnh ứng dụng theo nhu cầu của bạn")
                ScrollView {
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Thông báo", systemImage: "bell.fill").font(.title3.bold()).foregroundStyle(.blue)
                            toggleRow("Bật thông báo", "Nhận thông báo về công việc, nhắc nhở và các thông tin quan trọng", $notifOn)
                            Divider()
                            toggleRow("Âm thanh thông báo", "Phát âm thanh khi có thông báo", $soundOn)
                            Divider()
                            toggleRow("Rung khi có thông báo", "Rung thiết bị khi có thông báo (iPhone quyết định theo cài đặt hệ thống)", $vibrateOn)
                        }
                        .padding(14).background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 20))

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Chọn vị trí làm việc", systemImage: "mappin.circle.fill").font(.title3.bold()).foregroundStyle(.blue)
                            Text("Chỉ nhận thông báo của khu vực bạn chọn. Hai khu vực còn lại tắt thông báo; các hạng mục khác vẫn nhắc bình thường. Bấm lại khu vực đang chọn để bỏ chọn (tất cả đều nhắc).")
                                .font(.footnote).foregroundStyle(.secondary)
                            ForEach(areaInfo, id: \.0) { a in
                                Button { area = (area == a.id) ? "none" : a.id } label: {
                                    HStack(spacing: 10) {
                                        bundleImage(a.img).resizable().scaledToFit().frame(width: 90, height: 64)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(a.title).font(.headline).foregroundStyle(Color(red: 0.05, green: 0.2, blue: 0.6))
                                            Text(a.desc).font(.caption).foregroundStyle(.blue.opacity(0.8)).multilineTextAlignment(.leading)
                                        }
                                        Spacer()
                                        Image(systemName: area == a.id ? "largecircle.fill.circle" : "circle")
                                            .font(.title2).foregroundStyle(.blue)
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.93, green: 0.96, blue: 1.0)))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(area == a.id ? Color.blue : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14).background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 20))

                        Button { save() } label: {
                            Label("Lưu thay đổi", systemImage: "checkmark.circle.fill").font(.title3.bold()).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Capsule().fill(Color.blue.gradient))
                        }
                        .padding(.horizontal, 20)
                        Color.clear.frame(height: 10)
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { BottomBar() }
        .alert("Đã lưu cài đặt", isPresented: $saved) { Button("OK") {} }
    }

    private func toggleRow(_ t: String, _ d: String, _ b: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.headline)
                Text(d).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: b).labelsHidden().tint(.blue)
        }
        .padding(.vertical, 6)
    }

    private func save() {
        let u = UserDefaults.standard
        u.set(notifOn, forKey: "notifOn"); u.set(soundOn, forKey: "soundOn")
        u.set(vibrateOn, forKey: "vibrateOn"); u.set(area, forKey: "area")
        store.rescheduleAll()          // đặt lại toàn bộ thông báo theo khu vực vừa chọn
        saved = true
    }
}
