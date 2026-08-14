import SwiftUI

/// หน้าจัดการโมเดล AI ในเครื่อง
///
/// ทั้งหน้ามีปุ่มเดียวที่เริ่มดาวน์โหลดได้ และเขียนขนาดไว้บนปุ่มเลย — กว่าหนึ่ง
/// กิกะไบต์ต้องเป็นการตัดสินใจที่ผู้ใช้เห็นตัวเลขก่อนกด ไม่ใช่รู้ทีหลังตอนเน็ตหมด
struct ModelDownloadView: View {
    @Environment(\.l10n) private var t
    @Environment(AICoach.self) private var coach

    @State private var downloader = ModelDownloader.shared

    var body: some View {
        SettingsDetailScreen(title: t.modelTitle) {
            header
            backendCard
            statusCard
            footnote
        }
        // `AICoach` เช็กไฟล์บนดิสก์ครั้งเดียวตอนสร้าง ต้องบอกให้ประเมินใหม่เมื่อ
        // สถานะเปลี่ยน ไม่งั้นโหลดเสร็จแล้วก็ยังได้คำแนะนำแบบกฎธรรมดาจนกว่าจะรีสตาร์ท
        // (และเช่นเดียวกันตอนลบโมเดล ต้องปล่อย backend ที่ถืออยู่ทิ้ง)
        .onChange(of: downloader.phase) { coach.refreshAvailability() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(Palette.green)

            Text(t.modelIntro)
                .font(.subheadline)
                .foregroundStyle(Palette.inkSoft)
        }
        .cardStyle()
    }

    /// ชั้นไหนกำลังตอบอยู่จริง
    ///
    /// มีเพราะทั้งสามชั้นตกทอดกันเงียบ ๆ ตามการออกแบบ — ผู้ใช้ที่ได้คำตอบไม่เข้าท่า
    /// จึงไม่มีทางรู้เลยว่ากำลังคุยกับโมเดล 1.5B ในเครื่องอยู่ ทั้งที่เปิด Apple
    /// Intelligence แล้วจะดีขึ้นทันที การเงียบตรงนี้ทำให้คุณภาพที่ต่างกันมากดูเหมือน
    /// เป็นความผิดของแอปเอง
    private var backendCard: some View {
        let (name, note, tint) = backendDetails

        return VStack(alignment: .leading, spacing: 10) {
            Text(t.backendCardTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.inkFaint)

            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 10, height: 10)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
            }

            Text(note)
                .font(.footnote)
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var backendDetails: (name: String, note: String, tint: Color) {
        switch coach.activeBackend {
        case .foundationModels:
            (t.backendFoundationModels, t.backendFoundationModelsNote, Palette.green)
        case .coreML:
            (t.backendCoreML, t.backendCoreMLNote, Palette.purple)
        case .ruleBased:
            (t.backendRuleBased, t.backendRuleBasedNote, Palette.inkFaint)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(statusTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
            }

            switch downloader.phase {
            case .notInstalled:
                sizeRows
                startButton

            case let .downloading(progress):
                downloading(progress)

            case .compiling:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(t.modelCompilingNote)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSoft)
                }

            case .ready:
                // ไฟล์ครบแต่รอบก่อนแครชคาการเรียกโมเดล — แอปจะไม่แตะมันอีกจนกว่าจะลบ
                // ถ้าไม่บอกตรงนี้ ผู้ใช้จะเห็นแค่ "พร้อมใช้" แล้วสงสัยว่าทำไมโค้ชเงียบ
                if ModelStore.isDisabledByCrash {
                    Label(t.modelCrashedNote, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Palette.orange)
                    // ให้ลองใหม่ได้โดยไม่ต้องโหลดซ้ำ 1.6 GB
                    action(t.modelRetryButton, tint: Palette.green) {
                        ModelStore.allowRetryAfterCrash()
                        coach.refreshAvailability()
                    }
                } else {
                    Text(t.modelFallbackNote)
                        .font(.caption)
                        .foregroundStyle(Palette.inkFaint)
                }
                deleteButton

            case let .failed(failure):
                Text(failure.message(t))
                    .font(.caption)
                    .foregroundStyle(Palette.red)
                HStack(spacing: 12) {
                    action(t.modelRetryButton, tint: Palette.green) { downloader.retry() }
                    action(t.modelDeleteButton, tint: Palette.track, ink: Palette.ink) {
                        downloader.deleteModel()
                    }
                }
            }
        }
        .cardStyle()
    }

    private var sizeRows: some View {
        VStack(spacing: 8) {
            row(t.modelDownloadSizeLabel, ModelDownloader.formatted(ModelDownloader.downloadBytes))
            row(t.modelDiskNeededLabel, ModelDownloader.formatted(ModelDownloader.requiredDiskBytes))
        }
    }

    private func downloading(_ progress: ModelDownloader.Progress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView(value: progress.fraction)
                .tint(Palette.green)

            HStack {
                Text(t.modelStepLabel(progress.fileIndex, progress.fileCount))
                Spacer()
                Text("\(ModelDownloader.formatted(progress.received)) / \(ModelDownloader.formatted(progress.expected))")
            }
            .font(.caption)
            .foregroundStyle(Palette.inkSoft)
            .monospacedDigit()

            action(t.modelCancelButton, tint: Palette.track, ink: Palette.ink) {
                downloader.cancel()
            }
        }
    }

    private var startButton: some View {
        action(
            t.modelStartButton(ModelDownloader.formatted(ModelDownloader.downloadBytes)),
            tint: Palette.green
        ) {
            downloader.start()
        }
    }

    private var deleteButton: some View {
        action(t.modelDeleteButton, tint: Palette.track, ink: Palette.red) {
            downloader.deleteModel()
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(t.modelWifiNote, systemImage: "wifi")
            Label(t.modelFallbackNote, systemImage: "info.circle")
        }
        .font(.caption2)
        .foregroundStyle(Palette.inkFaint)
        .padding(.horizontal, 4)
    }

    // MARK: - Bits

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.inkSoft)
            Spacer()
            Text(value).foregroundStyle(Palette.ink).monospacedDigit()
        }
        .font(.subheadline)
    }

    private func action(
        _ title: String,
        tint: Color,
        ink: Color = .white,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(tint, in: RoundedRectangle(cornerRadius: Metrics.controlCorner, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var statusTitle: String {
        switch downloader.phase {
        case .notInstalled: return t.modelStateNotInstalled
        case .downloading: return t.modelStateDownloading
        case .compiling: return t.modelStateCompiling
        case .ready: return t.modelStateReady
        case .failed: return t.modelStateFailed
        }
    }

    private var statusColor: Color {
        switch downloader.phase {
        case .notInstalled: return Palette.inkFaint
        case .downloading, .compiling: return Palette.blue
        case .ready: return Palette.green
        case .failed: return Palette.red
        }
    }
}
