import DeviceActivity
import FamilyControls
import SwiftUI

@main
struct SleepFirstApp: App {
    var body: some Scene {
        WindowGroup { BedtimeView() }
    }
}

struct BedtimeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("selectedApps") private var selectionData = Data()
    @AppStorage("betaConsent") private var consent = false
    @AppStorage("betaID") private var participant = ""
    @AppStorage("betaFirst") private var first = ""
    @AppStorage("betaSecond") private var second = ""
    @State private var selection = FamilyActivitySelection()
    @State private var approved = false
    @State private var requesting = false
    @State private var choosing = false
    @State private var end: Date?
    @State private var error: String?
    @State private var confirmingStop = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.indigo)
                        .accessibilityHidden(true)
                    Text("폰을 먼저 재운다")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("잠들기 전, 선택한 앱을 1시간 쉬게 해요.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    if let end {
                        Text("폰이 쉬는 중")
                            .font(.title2.bold())
                        Text("해제 예정 \(end.formatted(date: .abbreviated, time: .shortened))")
                        Button("지금 제한 풀기") { confirmingStop = true }
                    } else if !approved {
                        Button("스크린 타임 권한 허용") {
                            requesting = true
                            Task { await authorize() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(requesting)
                    } else {
                        Button(selection.applicationTokens.isEmpty
                               ? "제한할 앱 고르기"
                               : "제한할 앱 변경 · \(selection.applicationTokens.count)개") {
                            choosing = true
                        }
                        Text("릴스나 쇼츠를 보는 앱만 선택해 주세요. 전화와 시계는 선택에서 빼 주세요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("폰 재우기", action: start)
                            .buttonStyle(.borderedProminent)
                            .disabled(selection.applicationTokens.isEmpty)
                    }
                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                DisclosureGroup("무료 베타 · 사용 기록 공유") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("재사용 측정에 참여", isOn: $consent)
                        Text("동의한 뒤의 첫 두 번의 제한 시작 시각과 무작위 참여 번호를 기기에 저장합니다. 공유 버튼을 누르면 직접 보낼 수 있습니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if consent && !first.isEmpty {
                            ShareLink(item: betaReport) {
                                Label("베타 기록 공유", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(28)
            .frame(maxWidth: 540, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .tint(.indigo)
        .familyActivityPicker(isPresented: $choosing, selection: $selection)
        .onChange(of: selection) { _, value in
            if let data = try? JSONEncoder().encode(value) { selectionData = data }
        }
        .onChange(of: consent) { _, optedIn in
            if optedIn {
                if participant.isEmpty { participant = UUID().uuidString }
            } else {
                participant = ""
                first = ""
                second = ""
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .confirmationDialog("지금 제한을 풀까요?", isPresented: $confirmingStop) {
            Button("제한 풀기", role: .destructive) { stop() }
        }
        .task {
            selection = (try? JSONDecoder().decode(FamilyActivitySelection.self,
                                                     from: selectionData)) ?? FamilyActivitySelection()
            refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { break }
                if scenePhase == .active && end != nil { refresh() }
            }
        }
    }

    private var betaReport: String {
        "participant,first_start,second_start,observed_at\n" +
        "\(participant),\(first),\(second),\(Date.now.ISO8601Format())\n"
    }

    @MainActor
    private func authorize() async {
        defer { requesting = false }
        error = nil
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            self.error = "스크린 타임 권한을 확인해 주세요."
        }
        refresh()
    }

    private func refresh() {
        approved = AuthorizationCenter.shared.authorizationStatus == .approved
        if !approved {
            if Restriction.defaults?.object(forKey: Restriction.endKey) != nil { stop() }
            return
        }
        Restriction.clearIfExpired()
        end = Restriction.defaults?.object(forKey: Restriction.endKey) as? Date
    }

    private func start() {
        refresh()
        guard approved, end == nil, !selection.applicationTokens.isEmpty else { return }
        guard let defaults = Restriction.defaults else {
            error = "제한 기능을 설정할 수 없어요."
            return
        }

        error = nil
        let now = Date.now
        let expires = Date(timeIntervalSince1970: ceil(now.timeIntervalSince1970) + Restriction.duration)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let fields: Set<Calendar.Component> = [
            .calendar, .timeZone, .year, .month, .day, .hour, .minute, .second
        ]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(fields, from: now),
            intervalEnd: calendar.dateComponents(fields, from: expires),
            repeats: false
        )

        let center = DeviceActivityCenter()
        center.stopMonitoring([Restriction.activity])
        defaults.set(expires, forKey: Restriction.endKey)
        do {
            try center.startMonitoring(Restriction.activity, during: schedule)
        } catch {
            Restriction.clear()
            self.error = "1시간 제한을 시작할 수 없어요. 다시 시도해 주세요."
            return
        }

        Restriction.store.shield.applications = selection.applicationTokens
        end = expires
        if consent {
            if participant.isEmpty { participant = UUID().uuidString }
            if first.isEmpty {
                first = now.ISO8601Format()
            } else if second.isEmpty {
                second = now.ISO8601Format()
            }
        }
    }

    private func stop() {
        Restriction.clear()
        DeviceActivityCenter().stopMonitoring([Restriction.activity])
        end = nil
    }
}
