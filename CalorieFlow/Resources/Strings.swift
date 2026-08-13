import Foundation

/// ตารางข้อความสองภาษา
///
/// แอปสลับภาษาได้ทันทีโดยไม่ต้องรีสตาร์ท จึงไม่ใช้ `NSLocalizedString` ซึ่งผูกกับ
/// ภาษาของระบบ แต่เก็บข้อความไว้ที่นี่แล้วเลือกตามค่าที่ผู้ใช้ตั้งไว้แทน
struct L10n {
    let language: AppLanguage

    private func s(_ th: String, _ en: String) -> String {
        language == .thai ? th : en
    }

    var locale: Locale { language.locale }

    // MARK: - Tabs

    var tabHome: String { s("หน้าหลัก", "Home") }
    var tabHistory: String { s("ประวัติ", "History") }
    var tabStats: String { s("สถิติ", "Stats") }
    var tabSettings: String { s("ตั้งค่า", "Settings") }

    // MARK: - Shared

    var save: String { s("บันทึก", "Save") }
    var add: String { s("เพิ่ม", "Add") }
    var cancel: String { s("ยกเลิก", "Cancel") }
    var ok: String { s("ตกลง", "OK") }
    var share: String { s("แชร์", "Share") }
    var successTitle: String { s("สำเร็จ", "Success") }
    var errorTitle: String { s("ผิดพลาด", "Error") }
    var kcal: String { s("kcal", "kcal") }

    // MARK: - Enum labels

    func goalLabel(_ goal: GoalType) -> String {
        switch goal {
        case .lose: return s("ลดน้ำหนัก", "Lose weight")
        case .maintain: return s("รักษาน้ำหนัก", "Maintain")
        case .gain: return s("เพิ่มน้ำหนัก", "Gain weight")
        }
    }

    func activityLabel(_ level: ActivityLevel) -> String {
        switch level {
        case .sedentary: return s("ไม่ออกกำลังกาย / น้อยมาก", "Little or no exercise")
        case .lightlyActive: return s("ออกกำลังกายเบาๆ (1-3 วัน/สัปดาห์)", "Light (1-3 days/week)")
        case .moderatelyActive: return s("ออกกำลังกายปานกลาง (3-5 วัน)", "Moderate (3-5 days/week)")
        case .veryActive: return s("ออกกำลังกายหนัก (6-7 วัน)", "Hard (6-7 days/week)")
        case .extraActive: return s("หนักมาก (วันละ 2 เวลา)", "Very hard / physical job")
        }
    }

    func appearanceLabel(_ appearance: AppAppearance) -> String {
        switch appearance {
        case .system: return s("ตามระบบ", "System")
        case .light: return s("สว่าง", "Light")
        case .dark: return s("มืด", "Dark")
        }
    }

    // MARK: - Dashboard

    var wrappedTeaser: String { s("พร้อมหรือยัง?", "Ready?") }
    func wrappedTitle(_ year: Int) -> String { "Wrapped \(String(year))" }

    var streakCaption: String { s("บันทึกต่อเนื่อง", "LOGGING STREAK") }
    func days(_ count: Int) -> String { s("\(count) วัน", "\(count) days") }
    func effortNote(great: Bool) -> String {
        great ? s("ความพยายาม เยี่ยมมาก!", "Great effort!") : s("ความพยายาม สู้ต่อไป!", "Keep it up!")
    }

    func greeting(_ name: String) -> String { s("สวัสดี, \(name)", "Hi, \(name)") }
    func goalLine(_ goal: GoalType) -> String {
        s("เป้าหมาย: \(goalLabel(goal))", "Goal: \(goalLabel(goal))")
    }

    var remainingCaption: String { s("เหลือ (KCAL)", "LEFT (KCAL)") }
    var overCaption: String { s("กินเกิน (KCAL)", "OVER (KCAL)") }
    var consumed: String { s("ทานไปแล้ว", "Consumed") }
    func targetCaption(isManual: Bool) -> String {
        isManual ? s("เป้าหมาย (กำหนดเอง)", "Goal (Custom)") : s("เป้าหมาย (TDEE)", "Goal (TDEE)")
    }

    var dailyStatus: String { s("สถานะรายวัน", "Daily status") }
    var allGoalsMet: String { s("ยอดเยี่ยม! ครบตามเป้าหมายแล้ว", "Excellent! All goals met") }
    func statusBreakdown(food: Int, water: Int) -> String {
        s("เฉลี่ย: อาหาร \(food)%, น้ำ \(water)%", "Avg: food \(food)%, water \(water)%")
    }

    var waterTitle: String { s("ปริมาณน้ำที่ดื่ม", "Water intake") }
    func waterGoalShort(_ ml: Int) -> String { s("เป้าหมาย: \(ml) ml", "Goal: \(ml) ml") }
    var waterGlass: String { s("250 ml (แก้ว)", "250 ml (glass)") }
    var waterBottle: String { s("500 ml (ขวด)", "500 ml (bottle)") }
    var waterAmountPlaceholder: String { s("ระบุจำนวน (ml)", "Enter amount (ml)") }

    var todayItems: String { s("รายการวันนี้", "Today's log") }
    var addItem: String { s("+ เพิ่มรายการ", "+ Add item") }
    var noFoodYet: String { s("ยังไม่มีรายการอาหาร", "No food logged yet") }

    // MARK: - Add food

    var addFoodTitle: String { s("เพิ่มรายการอาหาร", "Add food") }
    var foodNameLabel: String { s("ชื่อเมนูอาหาร", "Food name") }
    var foodNamePlaceholder: String {
        s("เช่น ข้าวมันไก่, กะเพราหมูสับ...", "e.g. Chicken rice, Basil pork...")
    }
    var required: String { s("โปรดระบุ", "Required") }
    var caloriesLabel: String { s("แคลอรี่", "Calories") }
    var saveItem: String { s("บันทึกรายการ", "Save item") }

    // MARK: - History

    var historyTitle: String { s("ประวัติการบันทึก", "History") }
    var totalCalories: String { s("รวมแคลอรี่", "Total calories") }
    var waterShort: String { s("ดื่มน้ำ", "Water") }
    var noFoodItems: String { s("ไม่มีรายการอาหาร", "No food items") }
    var nothingLogged: String { s("ไม่มีการบันทึกข้อมูลในวันนี้", "Nothing logged on this day") }

    var weekdaySymbols: [String] {
        language == .thai
            ? ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"]
            : ["S", "M", "T", "W", "T", "F", "S"]
    }

    var monthNames: [String] {
        language == .thai
            ? ["มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน", "พฤษภาคม", "มิถุนายน",
               "กรกฎาคม", "สิงหาคม", "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม"]
            : ["January", "February", "March", "April", "May", "June",
               "July", "August", "September", "October", "November", "December"]
    }

    /// ไทยใช้ พ.ศ. อังกฤษใช้ ค.ศ.
    func calendarHeader(year: Int, monthIndex: Int) -> String {
        let name = monthNames[monthIndex - 1]
        return language == .thai ? "\(name) \(String(year + 543))" : "\(name) \(String(year))"
    }

    // MARK: - Stats

    var statsTitle: String { s("สถิติภาพรวม", "Statistics") }
    var weeklyCalories: String { s("แคลอรี่รายสัปดาห์", "Weekly calories") }
    var weeklyWater: String { s("ปริมาณน้ำรายสัปดาห์", "Weekly water") }
    var tdeeFootnote: String {
        s("เส้นประคือเป้าหมาย TDEE ปัจจุบันของคุณ", "Dashed line is your current TDEE goal")
    }
    func waterFootnote(_ goal: Int) -> String {
        s("เส้นประคือเป้าหมายการดื่มน้ำ (\(goal) ml)", "Dashed line is your water goal (\(goal) ml)")
    }

    var weeklyAverageCaption: String { s("ค่าเฉลี่ยสัปดาห์นี้", "THIS WEEK'S AVERAGE") }
    var weeklyWaterAverageCaption: String { s("เฉลี่ยดื่มน้ำสัปดาห์นี้", "AVG WATER THIS WEEK") }
    var kcalPerDay: String { s("kcal/วัน", "kcal/day") }
    var mlPerDay: String { s("ml/วัน", "ml/day") }
    var aboveGoal: String { s("เกินเป้าหมายเฉลี่ย", "Above your goal") }
    var belowGoal: String { s("ทำได้ดีมาก! ต่ำกว่าเป้า", "Nice! Under your goal") }
    var waterGoalMet: String { s("ยอดเยี่ยม! ถึงเป้าหมาย", "Excellent! Goal reached") }
    var waterGoalMissed: String { s("พยายามอีกนิดนะ", "A little more to go") }
    var currentStreakCaption: String { s("STREAK ปัจจุบัน", "CURRENT STREAK") }
    var tdeeGoalCaption: String { s("เป้าหมาย TDEE", "TDEE GOAL") }

    // MARK: - Settings

    var settingsTitle: String { s("ตั้งค่า", "Settings") }

    var sectionProfile: String { s("ข้อมูลส่วนตัว", "PROFILE") }
    var sectionGoals: String { s("เป้าหมายและการคำนวณ", "GOALS & CALCULATION") }
    var sectionAppearance: String { s("การแสดงผล", "APPEARANCE") }
    var sectionData: String { s("ข้อมูล", "DATA") }

    var nameLabel: String { s("ชื่อ", "Name") }
    var genderLabel: String { s("เพศ", "Gender") }
    var male: String { s("ชาย", "Male") }
    var female: String { s("หญิง", "Female") }
    var heightLabel: String { s("ส่วนสูง (cm)", "Height (cm)") }
    var ageLabel: String { s("อายุ (ปี)", "Age (years)") }
    var activityFieldLabel: String { s("กิจกรรม", "Activity level") }
    var goalLabelTitle: String { s("เป้าหมาย", "Goal") }
    var currentWeightCaption: String { s("น้ำหนักปัจจุบัน", "Current weight") }
    var targetWeightCaption: String { s("เป้าหมายน้ำหนัก", "Target weight") }

    var updateWeightTitle: String { s("อัปเดตน้ำหนักล่าสุด", "Update weight") }
    var updateWeightHint: String {
        s("การอัปเดตน้ำหนักจะช่วยให้ TDEE คำนวณได้แม่นยำขึ้น",
          "Keeping your weight current makes the TDEE estimate more accurate")
    }
    var weightUpdated: String { s("อัปเดตน้ำหนักเรียบร้อยแล้ว", "Weight updated") }

    var manualCaloriesLabel: String {
        s("ตั้งค่า Calories เอง (ถ้าต้องการ)", "Set calories manually (optional)")
    }
    var resetToAuto: String { s("รีเซ็ตเป็นอัตโนมัติ", "Reset to automatic") }
    func autoSuggestion(_ value: Int) -> String {
        s("ค่าแนะนำอัตโนมัติ: \(value)", "Auto suggestion: \(value)")
    }
    var manualCaloriesHint: String {
        s("ปกติระบบคำนวณจากน้ำหนักปัจจุบัน - 1000 kcal (สำหรับการลดน้ำหนัก) และ + 1000 kcal (สำหรับการเพิ่มน้ำหนัก) หากคุณต้องการใช้สูตรน้ำหนักเป้าหมาย สามารถกรอกค่าที่ต้องการที่นี่",
          "By default the goal is your TDEE minus 1000 kcal (losing) or plus 1000 kcal (gaining). Enter your own value here to override it.")
    }

    var waterGoalTitle: String { s("เป้าหมายการดื่มน้ำ (มิลลิลิตร)", "Water goal (ml)") }
    var waterGoalHint: String {
        s("ปริมาณที่แนะนำคือประมาณ 2000 - 3000 มล. ต่อวัน", "2000 - 3000 ml per day is typical")
    }

    var themeLabel: String { s("ธีม", "Theme") }
    var languageLabel: String { s("ภาษา", "Language") }

    /// `.system` ไม่มีชื่อในภาษาของตัวเอง จึงต้องแปลตามภาษาที่กำลังแสดงอยู่
    func languageOptionLabel(_ language: AppLanguage) -> String {
        language.nativeName ?? s("ตามระบบ", "System")
    }

    var languageRestartNote: String {
        s("บางส่วนของแอป เช่น รูปแบบวันที่และเมนูของระบบ จะเปลี่ยนครบหลังเปิดแอปใหม่",
          "Some parts — date formats and system menus — only update fully after you restart the app")
    }

    // MARK: - Settings categories

    var settingsProfileSubtitle: String {
        s("ชื่อ เพศ ส่วนสูง อายุ และน้ำหนักล่าสุด", "Name, gender, height, age and latest weight")
    }
    var settingsGoalsSubtitle: String {
        s("เป้าหมาย แคลอรี่ และการดื่มน้ำ", "Goal, calories and water target")
    }
    var settingsAppearanceSubtitle: String {
        s("ธีม ภาษา และคำแนะนำจาก AI", "Theme, language and AI suggestions")
    }
    var settingsDataSubtitle: String {
        s("สำรองและกู้คืนข้อมูล", "Back up and restore your data")
    }
    var settingsModelTitle: String { s("โมเดล AI", "AI model") }
    var settingsModelSubtitle: String {
        s("ดาวน์โหลดโมเดลสำหรับใช้งานแบบออฟไลน์", "Download the model for offline use")
    }

    var dataManagement: String { s("จัดการข้อมูล (Data)", "Data management") }
    var exportButton: String { s("ส่งออก (.wgd)", "Export (.wgd)") }
    var importButton: String { s("นำเข้า (.wgd)", "Import (.wgd)") }
    var wgdHint: String {
        s("ไฟล์ .wgd ใช้สำหรับสำรองข้อมูลหรือย้ายเครื่อง",
          "A .wgd file backs up your data or moves it to another device")
    }
    var confirmImportTitle: String { s("ยืนยันการนำเข้า", "Confirm import") }
    var confirmImportMessage: String {
        s("ข้อมูลปัจจุบันทั้งหมดจะถูกแทนที่ด้วยข้อมูลในไฟล์",
          "All current data will be replaced by the contents of this file")
    }
    var importOverwrite: String { s("นำเข้าและเขียนทับข้อมูลเดิม", "Import and overwrite") }
    func importSuccess(_ name: String) -> String {
        s("นำเข้าข้อมูลสำเร็จ! ยินดีต้อนรับ \(name)", "Import complete. Welcome back, \(name)")
    }
    var exportFailed: String { s("ไม่สามารถสร้างไฟล์สำรองข้อมูลได้", "Could not create the backup file") }
    var readFailed: String { s("อ่านไฟล์ไม่สำเร็จ", "Could not read the file") }
    var invalidBackup: String {
        s("รูปแบบไฟล์ไม่ถูกต้อง: ไม่พบข้อมูล user หรือ logs",
          "Invalid file: no user or logs data found")
    }

    // MARK: - Wrapped

    func wrappedStepTitle(_ step: Int) -> String {
        switch step {
        case 0: return s("ปีที่ผ่านมายอดเยี่ยมมาก!", "What a year!")
        case 1: return s("พลังงานที่คุณเติมเต็ม", "The energy you fuelled")
        case 2: return s("ความชุ่มชื้นไม่เคยขาด", "Always hydrated")
        case 3: return s("เมนูโปรดของคุณ", "Your favourite meals")
        default: return s("สรุปการเดินทาง", "The journey")
        }
    }

    func wrappedIntro(_ year: Int) -> String {
        s("ปี \(String(year)) เป็นปีแห่งการดูแลตัวเองของคุณ",
          "\(String(year)) was your year of taking care of yourself")
    }
    var wrappedKcalCaption: String { s("KCAL ทั้งปี", "KCAL THIS YEAR") }
    func wrappedDailyAverage(_ value: Int) -> String {
        s("เฉลี่ยวันละ \(value) kcal", "About \(value) kcal per day")
    }
    var wrappedLitres: String { s("ลิตร", "litres") }
    var wrappedWaterCaption: String {
        s("คือปริมาณน้ำทั้งหมดที่คุณดื่มในปีนี้", "of water you drank this year")
    }
    var wrappedNoFoods: String {
        s("ยังไม่มีเมนูที่บันทึกไว้ในปีนี้", "No meals logged this year yet")
    }
    func wrappedTimes(_ count: Int) -> String { s("\(count) ครั้ง", "\(count)×") }
    var wrappedMaxStreak: String { s("STREAK สูงสุด", "LONGEST STREAK") }
    var wrappedFoodsLogged: String { s("อาหารที่บันทึก", "MEALS LOGGED") }
    var wrappedTotalWater: String { s("ปริมาณน้ำรวม", "TOTAL WATER") }
    func wrappedItems(_ count: Int) -> String { s("\(count) รายการ", "\(count) items") }

    // MARK: - AI coach (UI)

    var aiCardTitle: String { s("โค้ชส่วนตัว", "Your coach") }
    var aiThinking: String { s("กำลังคิด...", "Thinking...") }
    var aiRefresh: String { s("ขอคำแนะนำใหม่", "New suggestion") }
    var aiOpenChat: String { s("คุยกับโค้ช", "Chat with coach") }
    var aiWeeklyTitle: String { s("สรุปสัปดาห์นี้", "This week in review") }
    var aiChatTitle: String { s("โค้ชส่วนตัว", "Coach") }
    var aiChatPlaceholder: String { s("ถามอะไรก็ได้เกี่ยวกับมื้ออาหาร...", "Ask anything about your meals...") }
    var aiChatFailed: String {
        s("ขออภัย ตอบไม่ได้ในตอนนี้ ลองถามใหม่อีกครั้ง", "Sorry, I couldn't answer that. Please try again.")
    }
    func aiChatGreeting(_ name: String) -> String {
        s("สวัสดี \(name) ถามได้เลยว่าวันนี้ควรกินอะไรดี หรืออยากให้ช่วยดูอะไรเป็นพิเศษ",
          "Hi \(name) — ask me what to eat today, or anything you'd like a second opinion on.")
    }

    var aiEstimateButton: String { s("ประมาณแคลอรี่", "Estimate calories") }
    var aiEstimateFromTable: String {
        s("ค่าประมาณจากตารางเมนูทั่วไป", "Estimated from a table of common dishes")
    }
    var aiEstimateFailed: String {
        s("ประมาณค่าไม่ได้ ลองกรอกเอง", "Couldn't estimate — please enter it manually")
    }

    var aiSettingsLabel: String { s("คำแนะนำจาก AI", "AI suggestions") }
    var aiSettingsHint: String {
        s("ประมวลผลในเครื่องทั้งหมด ข้อมูลของคุณไม่ถูกส่งออกไปไหน",
          "Runs entirely on your device — your data never leaves it")
    }
    var aiFallbackNotice: String {
        s("กำลังใช้คำแนะนำแบบพื้นฐาน", "Using basic suggestions")
    }

    func aiUnavailableReason(_ reason: String) -> String {
        switch reason {
        case "requiresOS":
            return s("ต้องใช้ iOS 26 ขึ้นไป", "Requires iOS 26 or later")
        case "deviceNotEligible":
            return s("เครื่องนี้ไม่รองรับ Apple Intelligence", "This device doesn't support Apple Intelligence")
        case "notEnabled":
            return s("ยังไม่ได้เปิด Apple Intelligence ในการตั้งค่าเครื่อง",
                     "Apple Intelligence is turned off in system Settings")
        case "modelNotReady":
            return s("โมเดลกำลังดาวน์โหลด ลองใหม่อีกครั้งภายหลัง",
                     "The model is still downloading — try again later")
        case "coreMLUnusable":
            return s("โมเดลในเครื่องรันไม่ได้บนอุปกรณ์นี้ — simulator ไม่มีเอนจิน MPSGraph ต้องทดสอบบนเครื่องจริง",
                     "The on-device model can't run here — the simulator has no MPSGraph engine, so try a real device")
        default:
            return s("ใช้ AI ไม่ได้ในขณะนี้", "AI is unavailable right now")
        }
    }

    // MARK: - AI coach (prompts)

    /// บังคับภาษาของคำตอบให้ตรงกับที่ผู้ใช้เลือกในแอป ไม่ใช่ภาษาของคำถาม
    var aiPromptLanguageRule: String {
        s("ตอบเป็นภาษาไทยเท่านั้น", "Answer in English only.")
    }

    var aiSystemInstructions: String {
        s("""
          คุณเป็นโค้ชโภชนาการที่เป็นมิตรและให้กำลังใจในแอปบันทึกแคลอรี่ชื่อ CalorieFlow
          ให้คำแนะนำที่ทำได้จริงและเจาะจง อ้างอิงตัวเลขที่ผู้ใช้บันทึกไว้
          แนะนำอาหารไทยที่หาได้ทั่วไปเมื่อเหมาะสม
          ห้ามวินิจฉัยโรคหรือให้คำแนะนำทางการแพทย์ ถ้าผู้ใช้ถามเรื่องอาการหรือยา
          ให้แนะนำให้ปรึกษาแพทย์หรือนักโภชนาการ
          """,
          """
          You are a friendly, encouraging nutrition coach inside a calorie-logging app called CalorieFlow.
          Give practical, specific advice grounded in the numbers the user has logged.
          Suggest commonly available Thai dishes where relevant.
          Never diagnose conditions or give medical advice. If the user asks about symptoms or
          medication, point them to a doctor or registered dietitian.
          """)
    }

    var aiChatInstructions: String {
        s("ตอบสั้น กระชับ ไม่เกิน 4 ประโยค เว้นแต่ผู้ใช้ขอรายละเอียดเพิ่ม",
          "Keep answers short — at most 4 sentences — unless the user asks for more detail.")
    }

    var aiPromptContextHeader: String { s("ข้อมูลผู้ใช้ปัจจุบัน", "Current user data") }
    var aiPromptWeekHeader: String { s("ข้อมูล 7 วันล่าสุด (เก่าไปใหม่)", "Last 7 days (oldest to newest)") }
    var aiPromptGoalField: String { s("เป้าหมาย", "Goal") }
    var aiPromptTargetField: String { s("เป้าหมายต่อวัน", "Daily target") }
    var aiPromptConsumedField: String { s("ทานไปแล้ว", "Consumed") }
    var aiPromptRemainingField: String { s("เหลือ", "Remaining") }
    var aiPromptWaterField: String { s("น้ำ", "Water") }
    var aiPromptStreakField: String { s("บันทึกต่อเนื่อง (วัน)", "Logging streak (days)") }
    var aiPromptFoodsField: String { s("อาหารวันนี้", "Foods today") }
    var aiPromptWeightField: String { s("น้ำหนัก", "Weight") }
    var aiPromptCaloriesPerDay: String { s("แคลอรี่รายวัน", "Calories per day") }
    var aiPromptWaterPerDay: String { s("น้ำรายวัน (ml)", "Water per day (ml)") }
    var aiPromptAverageField: String { s("ค่าเฉลี่ยสัปดาห์", "Weekly average") }
    var aiPromptDishField: String { s("ชื่อเมนู", "Dish") }

    var aiPromptDailyTask: String {
        s("เขียนคำแนะนำสำหรับวันนี้ 2-3 ประโยค อ้างอิงตัวเลขข้างต้น ให้กำลังใจแต่ตรงไปตรงมา ห้ามใส่หัวข้อหรือ bullet",
          "Write a 2-3 sentence suggestion for today. Reference the numbers above. Be encouraging but direct. No headings or bullets.")
    }

    var aiPromptWeeklyTask: String {
        s("สรุปภาพรวมสัปดาห์นี้ 3-4 ประโยค ชี้จุดที่ทำได้ดีหนึ่งอย่างและจุดที่ควรปรับหนึ่งอย่าง ห้ามใส่หัวข้อหรือ bullet",
          "Summarise the week in 3-4 sentences. Name one thing going well and one thing to adjust. No headings or bullets.")
    }

    var aiPromptEstimateTask: String {
        s("ประมาณแคลอรี่ของเมนูนี้ต่อหนึ่งจานมาตรฐานแบบที่ขายทั่วไปในไทย",
          "Estimate the calories in one standard single serving of this dish as commonly served.")
    }
}
