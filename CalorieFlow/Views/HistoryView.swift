import SwiftUI

struct HistoryView: View {
    @Environment(AppStore.self) private var store

    @State private var selectedDate = DateKey.today
    @State private var viewMonth = Date.now

    private var log: DailyLog? { store.logs[selectedDate] }

    private var hasData: Bool {
        guard let log else { return false }
        return !log.foods.isEmpty || log.waterIntake > 0
    }

    var body: some View {
        ScreenScroll(title: "ประวัติการบันทึก") {
            CalendarGrid(
                month: $viewMonth,
                selectedDate: $selectedDate,
                markedDates: Set(store.logs.keys)
            )

            VStack(alignment: .leading, spacing: 16) {
                Text(DateKey.date(from: selectedDate)?.shortThaiWeekday ?? selectedDate)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)

                if let log, hasData {
                    summaryRow("รวมแคลอรี่", "\(log.totalCalories) kcal", tint: Palette.greenDeep)
                    summaryRow("ดื่มน้ำ", "\(log.waterIntake) ml", tint: Palette.blueDeep)

                    ForEach(log.foods) { food in
                        HStack {
                            Text(food.name).font(.subheadline).foregroundStyle(Palette.inkSoft)
                            Spacer()
                            Text("\(food.calories) kcal")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.ink)
                        }
                    }

                    if log.foods.isEmpty {
                        Text("ไม่มีรายการอาหาร")
                            .font(.caption2)
                            .foregroundStyle(Palette.inkFaint)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Text("ไม่มีการบันทึกข้อมูลในวันนี้")
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
            Divider().background(Palette.border)
        }
    }
}

/// ปฏิทินรายเดือน พร้อมจุดบอกวันที่มีข้อมูล — พุทธศักราชเหมือนเวอร์ชันเว็บ
struct CalendarGrid: View {
    @Binding var month: Date
    @Binding var selectedDate: String
    let markedDates: Set<String>

    private let calendar = Calendar(identifier: .gregorian)
    private let weekdaySymbols = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"]
    private let monthNames = [
        "มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน", "พฤษภาคม", "มิถุนายน",
        "กรกฎาคม", "สิงหาคม", "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม"
    ]

    private var year: Int { calendar.component(.year, from: month) }
    private var monthIndex: Int { calendar.component(.month, from: month) }

    /// ช่องว่างนำหน้า (nil) ตามด้วยเลขวันที่ 1...n
    private var slots: [Int?] {
        guard
            let first = calendar.date(from: DateComponents(year: year, month: monthIndex, day: 1)),
            let range = calendar.range(of: .day, in: .month, for: first)
        else { return [] }

        let leading = calendar.component(.weekday, from: first) - 1
        return Array(repeating: nil, count: leading) + range.map { Optional($0) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                stepButton(-1, icon: "chevron.left")
                Spacer()
                Text("\(monthNames[monthIndex - 1]) \(String(year + 543))")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                stepButton(1, icon: "chevron.right")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.inkFaint)
                        .padding(.vertical, 6)
                }

                ForEach(Array(slots.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit)
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

        return Button {
            selectedDate = key
        } label: {
            ZStack {
                if isSelected { Circle().fill(Palette.green) }
                Text("\(day)")
                    .font(.system(size: 14, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : Palette.inkSoft)
                if isMarked && !isSelected {
                    Circle()
                        .fill(Palette.green)
                        .frame(width: 4, height: 4)
                        .offset(y: 12)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
    }
}
