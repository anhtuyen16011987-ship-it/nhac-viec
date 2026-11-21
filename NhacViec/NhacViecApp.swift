import SwiftUI
import UserNotifications

// MARK: - 12 hạng mục theo thiết kế

struct Cat: Identifiable, Hashable {
    let id: String, title: String, icon: String, color: Color
}

let allCats: [Cat] = [
    Cat(id: "recheck", title: "Công việc\nkhu vực Recheck", icon: "doc.text.magnifyingglass", color: .blue),
    Cat(id: "cutting", title: "Công việc\nkhu vực Cutting", icon: "gearshape.2.fill", color: .green),
    Cat(id: "abnormal", title: "Xử lý\nbất thường", icon: "light.beacon.max.fill", color: .red),
    Cat(id: "error", title: "Lỗi cần chú ý", icon: "exclamationmark.triangle.fill", color: .orange),
    Cat(id: "important", title: "Công việc\nquan trọng", icon: "checklist.checked", color: .purple),
    Cat(id: "todo", title: "Công việc\ncần làm", icon: "square.and.pencil", color: .green),
    Cat(id: "testroom", title: "Công việc\nkhu vực Test Room", icon: "testtube.2", color: .teal),
    Cat(id: "other", title: "Công việc\nkhác", icon: "square.grid.2x2.fill", color: .indigo),
    Cat(id: "handover", title: "Bàn giao ca", icon: "hands.clap.fill", color: .mint),
    Cat(id: "meeting", title: "Họp đầu ca", icon: "person.3.fill", color: .purple),
    Cat(id: "boss", title: "Công việc\nsếp giao", icon: "person.crop.rectangle.fill", color: .yellow),
    Cat(id: "training", title: "Công việc\nđào tạo", icon: "person.fill.viewfinder", color: .cyan),
]

// MARK: - Model

enum Mode: String, Codable, CaseIterable {
    case once = "1 lần", daily = "Hằng ngày", weekly = "Theo thứ", monthly = "Hằng tháng", multi = "Nhiều giờ"
}

struct TaskItem: Identifiable, Codable {
    var id = UUID()
    var catID: String
    var title = ""
    var time = Date()                    // 1 lần: ngày + giờ; còn lại chỉ dùng giờ:phút
    var mode: Mode = .once
    var weekdays: Set<Int> = []          // 1 = CN ... 7 = T7
    var monthDay = 1
    var doneAt: Date? = nil
    // Kiểu "Nhiều giờ": từ `time` đến `endTime`, mỗi `everyHours` giờ nhắc 1 lần mỗi ngày
    var endTime: Date? = nil
    var everyHours: Int? = nil
    var slotsDone: Int? = nil
    var slotsDay: Date? = nil

    var slotMinutes: [Int] {
        guard mode == .multi else { return [] }
        func m(_ d: Date) -> Int {
            let x = Calendar.current.dateComponents([.hour, .minute], from: d)
            return (x.hour ?? 0) * 60 + (x.minute ?? 0)
        }
        let s = m(time), e = m(endTime ?? time), step = max(1, everyHours ?? 1) * 60
        guard e >= s else { return [s] }
        return Array(stride(from: s, through: e, by: step).prefix(24))
    }
    /// Số lần đã làm trong hôm nay (tự về 0 khi sang ngày mới)
    var doneToday: Int {
        guard let d = slotsDay, Calendar.current.isDateInToday(d) else { return 0 }
        return slotsDone ?? 0
    }

    var isRecurring: Bool { mode != .once }

    /// Tích xong: việc 1 lần ẩn hẳn; hằng ngày/theo thứ ẩn đến hôm sau; hằng tháng ẩn đến tháng sau.
    var isHidden: Bool {
        guard let d = doneAt else { return false }
        switch mode {
        case .once: return true
        case .daily, .weekly, .multi: return Calendar.current.isDateInToday(d)
        case .monthly: return Calendar.current.isDate(d, equalTo: Date(), toGranularity: .month)
        }
    }

    var subtitle: String {
        let f = DateFormatter()
        f.dateFormat = mode == .once ? "dd/MM HH:mm" : "HH:mm"
        let t = f.string(from: time)
        switch mode {
        case .once: return t
        case .daily: return "\(t) · Hằng ngày"
        case .weekly:
            let n = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"]
            return "\(t) · " + weekdays.sorted().map { n[$0 - 1] }.joined(separator: ", ")
        case .monthly: return "\(t) · Ngày \(monthDay) hằng tháng"
        case .multi:
            let ts = slotMinutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }
            return "\(ts.first ?? "") – \(ts.last ?? "") · mỗi \(everyHours ?? 1) giờ · \(doneToday)/\(ts.count) hôm nay"
        }
    }
}

// MARK: - Thông báo (chạy nền, không cần mở app)

enum Notifier {
    static func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func ids(_ t: TaskItem) -> [String] {
        (1...7).map { "\(t.id)-w\($0)" } + ["\(t.id)-once", "\(t.id)-daily", "\(t.id)-month"]
            + (0..<24).map { "\(t.id)-s\($0)" }
    }

    static func cancel(_ t: TaskItem) {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: ids(t))
        c.removeDeliveredNotifications(withIdentifiers: ids(t))
    }

    static func schedule(_ t: TaskItem) {
        cancel(t)
        let c = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = allCats.first { $0.id == t.catID }?.title.replacingOccurrences(of: "\n", with: " ") ?? "Nhắc việc"
        content.body = t.title
        content.sound = .default
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
    private let key = "tasks.v2"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let l = try? JSONDecoder().decode([TaskItem].self, from: d) { tasks = l }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(tasks) { UserDefaults.standard.set(d, forKey: key) }
    }
    private func mins(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    func pending(_ catID: String) -> [TaskItem] {
        tasks.filter { $0.catID == catID && !$0.isHidden }
            .sorted { mins($0.time) < mins($1.time) }
    }
    func upsert(_ t: TaskItem) {
        if let i = tasks.firstIndex(where: { $0.id == t.id }) { tasks[i] = t } else { tasks.append(t) }
        Notifier.schedule(t)
    }
    func delete(_ t: TaskItem) { Notifier.cancel(t); tasks.removeAll { $0.id == t.id } }
    func done(_ catID: String) -> [TaskItem] {
        tasks.filter { $0.catID == catID && $0.isHidden }
            .sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }
    /// Lỡ tích nhầm: bỏ tích để việc quay lại danh sách và đặt lại thông báo
    func undo(_ t: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == t.id }) else { return }
        if tasks[i].mode == .multi {
            tasks[i].slotsDone = max(0, tasks[i].doneToday - 1); tasks[i].slotsDay = Date()
            tasks[i].doneAt = nil
            return
        }
        tasks[i].doneAt = nil
        Notifier.schedule(tasks[i])
    }
    func toggle(_ t: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == t.id }) else { return }
        if tasks[i].mode == .multi {   // tích từng lần trong ngày
            let n = tasks[i].doneToday + 1
            tasks[i].slotsDone = n; tasks[i].slotsDay = Date()
            if n >= tasks[i].slotMinutes.count { tasks[i].doneAt = Date() }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Notifier.ids(t))
            return
        }
        tasks[i].doneAt = Date()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Notifier.ids(t))
        if !tasks[i].isRecurring { Notifier.cancel(tasks[i]) }
    }
}

// MARK: - App

@main
struct NhacViecApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var phase
    init() { Notifier.requestAuth() }

    var body: some Scene {
        WindowGroup {
            HomeView().environmentObject(store)
                .onChange(of: phase) { _, p in if p == .active { store.objectWillChange.send() } }
        }
    }
}

// MARK: - Màn hình chính

struct PressStyle: ButtonStyle {
    let radius: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.3 : 0), in: RoundedRectangle(cornerRadius: radius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct HomeView: View {
    @EnvironmentObject var store: Store
    private let W: CGFloat = 941, H: CGFloat = 1670
    private let navy = Color(red: 0.05, green: 0.25, blue: 0.75)

    /// Vùng bấm của 12 ô, tính theo toạ độ ảnh gốc
    private let rects: [CGRect] = {
        let rows: [(CGFloat, CGFloat)] = [(457, 660), (668, 843), (849, 1016), (1022, 1183), (1190, 1332), (1340, 1495)]
        let cols: [(CGFloat, CGFloat)] = [(90, 466), (477, 852)]
        return rows.flatMap { r in cols.map { c in CGRect(x: c.0, y: r.0, width: c.1 - c.0, height: r.1 - r.0) } }
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                // Nền kéo dài: dải trên và dưới lấy màu từ chính ảnh, lấp đầy mọi kích cỡ iPhone
                Color(red: 0.55, green: 0.85, blue: 1.0).ignoresSafeArea()
                VStack(spacing: 0) {
                    Image("poster_top").resizable().frame(height: 160)
                    Spacer(minLength: 0)
                    Image("poster_bottom").resizable().frame(height: 420)
                }
                .ignoresSafeArea()

                GeometryReader { geo in
                    let s = min(geo.size.width / W, geo.size.height / H)   // co vừa màn hình
                    poster(s)
                        .frame(width: W * s, height: H * s, alignment: .topLeading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .navigationDestination(for: Cat.self) { CategoryView(cat: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    func poster(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image("poster").resizable().frame(width: W * s, height: H * s)

            // Thanh ngày giờ chạy thật, phủ lên thanh trong ảnh
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
                .frame(width: 769 * s, height: 76 * s)
                .background(Capsule().fill(Color(red: 0.93, green: 0.97, blue: 1.0)))
                .overlay(Capsule().stroke(.white, lineWidth: 2 * s))
            }
            .position(x: 470.5 * s, y: 410 * s)

            // 12 vùng bấm, có số việc chưa làm ở góc
            ForEach(Array(allCats.enumerated()), id: \.element.id) { i, cat in
                let r = rects[i]
                let n = store.pending(cat.id).count
                NavigationLink(value: cat) {
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

// MARK: - Danh sách trong hạng mục

struct CategoryView: View {
    @EnvironmentObject var store: Store
    let cat: Cat
    @State private var editing: TaskItem?

    var body: some View {
        let items = store.pending(cat.id)
        let dones = store.done(cat.id)
        List {
            ForEach(items) { t in
                HStack(spacing: 12) {
                    Button { withAnimation { store.toggle(t) } } label: {
                        Image(systemName: "circle").font(.title2).foregroundStyle(cat.color)
                    }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title)
                        Text(t.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if t.mode == .multi && t.doneToday > 0 {
                        Button { store.undo(t) } label: { Image(systemName: "arrow.uturn.backward") }.buttonStyle(.plain)
                    }
                    if t.isRecurring { Image(systemName: "repeat").foregroundStyle(.secondary) }
                }
                .contentShape(Rectangle())
                .onTapGesture { editing = t }
                .swipeActions { Button(role: .destructive) { store.delete(t) } label: { Label("Xoá", systemImage: "trash") } }
            }
            if items.isEmpty && dones.isEmpty {
                ContentUnavailableView("Chưa có việc nào", systemImage: "checkmark.circle",
                                       description: Text("Bấm + để thêm công việc"))
            }
            if !dones.isEmpty {
                Section("✓ Đã làm (\(dones.count))") {
                    ForEach(dones) { t in
                        HStack(spacing: 12) {
                            Button { withAnimation { store.undo(t) } } label: {
                                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(cat.color)
                            }.buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).strikethrough().foregroundStyle(.secondary)
                                Text(t.subtitle + " · xong lúc " + (t.doneAt?.formatted(date: .omitted, time: .shortened) ?? ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .swipeActions { Button(role: .destructive) { store.delete(t) } label: { Label("Xoá", systemImage: "trash") } }
                    }
                }
            }
        }
        .navigationTitle(cat.title.replacingOccurrences(of: "\n", with: " "))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { editing = TaskItem(catID: cat.id) } label: { Image(systemName: "plus") } }
        .sheet(item: $editing) { EditView(task: $0, color: cat.color) }
    }
}

// MARK: - Thêm / sửa việc

struct EditView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var task: TaskItem
    let color: Color
    private let labels = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Công việc") { TextField("Tên công việc", text: $task.title) }
                Section("Lặp lại") {
                    Picker("Kiểu", selection: $task.mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu)
                    DatePicker(task.mode == .multi ? "Từ giờ" : "Giờ nhắc", selection: $task.time,
                               displayedComponents: task.mode == .once ? [.date, .hourAndMinute] : [.hourAndMinute])
                    if task.mode == .weekly {
                        HStack {
                            ForEach(1...7, id: \.self) { d in
                                let on = task.weekdays.contains(d)
                                Text(labels[d - 1]).font(.footnote.bold())
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .background(on ? color : Color.gray.opacity(0.15), in: Circle())
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
