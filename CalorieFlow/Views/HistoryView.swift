import SwiftUI

struct HistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.l10n) private var t

    @State private var selectedDate = DateKey.today
    @State private var viewMonth = Date.now

    private var log: DailyLog? { store.logs[selectedDate] }

    private var hasData: Bool { log?.hasEntries ?? false }

    /// เอาเฉพาะวันที่มีข้อมูลจริง ไม่ใช่ทุกวันที่มี record — ดู `DailyLog.hasEntries`
    private var markedDates: Set<String> {
        Set(store.logs.filter { $0.value.hasEntries }.keys)
    }

    var body: some View {
        ScreenScroll(title: t.historyTitle) {
            CalendarGrid(
                month: $viewMonth,
                selectedDate: $selectedDate,
                markedDates: markedDates
            )

            VStack(alignment: .leading, spacing: 16) {
                Text(DateKey.date(from: selectedDate)?.shortWeekday(locale: t.locale) ?? selectedDate)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)

                if let log, hasData {
                    summaryRow(t.totalCalories, "\(log.totalCalories) \(t.kcal)", tint: Palette.greenDeep)
                    summaryRow(t.waterShort, "\(log.waterIntake) ml", tint: Palette.blueDeep)

                    // วันที่บันทึกแค่น้ำหนักก็นับว่ามีข้อมูลและได้จุดบนปฏิทิน
                    // ถ้าไม่แสดงตรงนี้ การ์ดจะโชว์ 0 kcal / 0 ml เฉย ๆ โดยไม่บอกว่าจุดนั้นมาจากอะไร
                    if let weight = log.weightRecorded {
                        summaryRow(t.currentWeightCaption, "\(weight.clean) kg", tint: Palette.purple)
                    }

                    ForEach(log.foods) { food in
                        HStack {
                            Text(food.name).font(.subheadline).foregroundStyle(Palette.inkSoft)
                            Spacer()
                            Text("\(food.calories) \(t.kcal)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.ink)
                        }
                    }

                    if log.foods.isEmpty {
                        Text(t.noFoodItems)
                            .font(.caption2)
                            .foregroundStyle(Palette.inkFaint)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Text(t.nothingLogged)
                        .foregroundStyle(Palette.inkFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .cardStyle()
        }
    }

    private func summaryRow(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(Palette.inkSoft)
                Spacer()
                Text(value).font(.subheadline.bold()).foregroundStyle(tint)
            }
            Rectangle().fill(Palette.border).frame(height: 1)
        }
    }
}

/// ปฏิทินรายเดือน พร้อมจุดบอกวันที่มีข้อมูล — ไทยแสดง พ.ศ. อังกฤษแสดง ค.ศ.
struct CalendarGrid: View {
    @Binding var month: Date
    @Binding var selectedDate: String
    let markedDates: Set<String>

    @Environment(\.l10n) private var t

    /// `t.weekdaySymbols` เริ่มที่อาทิตย์ตายตัวทั้งสองภาษา จึงต้องล็อก `firstWeekday`
    /// ให้ตรงกัน ไม่งั้นเครื่องที่ locale ขึ้นต้นสัปดาห์วันจันทร์จะได้ช่องว่างเพี้ยนไปหนึ่งวัน
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1
        return c
    }()

    /// ความสูงขั้นต่ำของช่องวัน — `aspectRatio(1)` ล้วน ๆ ให้ช่องราว 41pt บนเครื่องเล็ก
    /// ซึ่งต่ำกว่าเป้าแตะ 44pt และทำให้จุดบอกข้อมูลไปชนกับตัวเลข
    private let cellHeight: CGFloat = 44

    private var year: Int { calendar.component(.year, from: month) }
    private var monthIndex: Int { calendar.component(.month, from: month) }

    /// ช่องว่างนำหน้า (nil) ตามด้วยเลขวันที่ 1...n
    private var slots: [Int?] {
        guard
            let first = calendar.date(from: DateComponents(year: year, month: monthIndex, day: 1)),
            let range = calendar.range(of: .day, in: .month, for: first)
        else { return [] }

        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.map { Optional($0) }
    }

    /// ย้ายวันที่เลือกตามเดือนที่กำลังดู เพราะหัวข้อกับการ์ดสรุปข้างล่างอ้างอิง
    /// `selectedDate` ตัวเดียวกัน ถ้าปล่อยไว้จะกลายเป็นโชว์วันของเดือนที่มองไม่เห็นในกริด
    private func syncSelection(to newMonth: Date) {
        let y = calendar.component(.year, from: newMonth)
        let m = calendar.component(.month, from: newMonth)

        guard
            let first = calendar.date(from: DateComponents(year: y, month: m, day: 1)),
            let range = calendar.range(of: .day, in: .month, for: first)
        else { return }

        // คงวันที่เดิมไว้ถ้าเดือนใหม่มีวันนั้น (31 -> 30/28 ให้หล่นมาวันสุดท้าย)
        let currentDay = Int(selectedDate.suffix(2)) ?? 1
        let day = min(currentDay, range.count)
        selectedDate = String(format: "%04d-%02d-%02d", y, m, day)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                stepButton(-1, icon: "chevron.left")
                Spacer()
                Text(t.calendarHeader(year: year, monthIndex: monthIndex))
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                stepButton(1, icon: "chevron.right")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(t.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.inkFaint)
                        .padding(.vertical, 6)
                }

                ForEach(Array(slots.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: cellHeight)
                    }
                }
            }
        }
        .cardStyle(padding: 16)
    }

    private func stepButton(_ delta: Int, icon: String) -> some View {
        Button {
            if let next = calendar.date(byAdding: .month, value: delta, to: month) {
                month = next
                syncSelection(to: next)
            }
        } label: {
            Image(systemName: icon).foregroundStyle(Palette.inkSoft).padding(8)
        }
        .buttonStyle(.plain)
    }

    private func dayCell(_ day: Int) -> some View {
        let key = String(format: "%04d-%02d-%02d", year, monthIndex, day)
        let isSelected = key == selectedDate
        let isMarked = markedDates.contains(key)
        let isToday = key == DateKey.today

        return Button {
            selectedDate = key
        } label: {
            ZStack {
                if isSelected {
                    Circle().fill(Palette.green)
                } else if isToday {
                    // วันนี้ใช้เส้นขอบจาง ๆ ให้ต่างจากวงทึบของวันที่เลือก
                    // เพราะสองสถานะนี้เกิดพร้อมกันได้ ต้องอ่านออกว่าอันไหนคืออันไหน
                    Circle().strokeBorder(Palette.green.opacity(0.45), lineWidth: 1.5)
                }
                Text("\(day)")
                    .font(.system(size: 14, weight: isSelected || isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Palette.card : Palette.inkSoft)
                if isMarked && !isSelected {
                    Circle()
                        .fill(Palette.green)
                        .frame(width: 4, height: 4)
                        // 14 พอดีขอบล่างของตัวเลข ยังอยู่ในวงขอบของวันนี้และไม่ทับกัน
                        .offset(y: 14)
                }
            }
            .frame(maxWidth: .infinity, minHeight: cellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
