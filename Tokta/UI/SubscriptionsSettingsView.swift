import SwiftUI

/// 계정마다 구독료와 결제일을 적고, 다음 결제가 가까운 순으로 본다.
struct SubscriptionsSettingsView: View {
    @Environment(UsageStore.self) private var store
    @State private var editing: Account.ID?

    private var sortedAccounts: [Account] {
        let now = Date.now
        return store.accounts.sorted { a, b in
            switch (store.renewal(for: a, now: now)?.date, store.renewal(for: b, now: now)?.date) {
            case let (x?, y?): x < y
            case (_?, nil): true
            default: false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(sortedAccounts) { account in
                let renewal = store.renewal(for: account)
                HStack {
                    VStack(alignment: .leading) {
                        Text(account.displayLabel)
                        Text(account.service.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        if let subscription = account.subscription {
                            Text("\(MoneyText.string(subscription.amount, currency: subscription.currency)) / \(subscription.cycle.label)")
                                .monospacedDigit()
                        }
                        if let renewal {
                            Text(RenewalText.string(renewal) + (renewal.isDetected ? String(localized: " · 서비스에서 가져옴") : ""))
                                .font(.caption)
                                .foregroundStyle(renewal.isEnding ? .orange : .secondary)
                        }
                    }
                    Button(account.subscription == nil ? String(localized: "입력") : String(localized: "수정")) { editing = account.id }
                        .popover(isPresented: Binding(get: { editing == account.id }, set: { if !$0 { editing = nil } })) {
                            SubscriptionEditor(account: account, detected: store.detectedBilling(for: account))
                        }
                }
            }
            .overlay {
                if store.accounts.isEmpty { Text("추가한 계정이 없습니다").foregroundStyle(.secondary) }
            }
            HStack {
                Text("월 합계").font(.headline)
                Spacer()
                Text(store.monthlySubscriptionTotal ?? String(localized: "입력한 구독료가 없습니다"))
                    .monospacedDigit()
                    .foregroundStyle(store.monthlySubscriptionTotal == nil ? .secondary : .primary)
            }
            Text("Claude·Cursor는 결제일을 서비스에서 가져옵니다(금액은 직접 입력). Claude Team처럼 조직이 한 번에 내는 구독은 결제 정보를 볼 수 있는 관리자 계정의 결제일을 같은 조직 계정들이 같이 쓰고, **금액은 한 계정에만** 적으세요. 매년 결제는 12로 나눠 더하고, 통화가 다르면 환율 없이 따로 합칩니다. 결제 전날 오전 9시에 알림을 보냅니다(설정 → 알림).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct SubscriptionEditor: View {
    @Environment(UsageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let account: Account
    let detected: DetectedBilling?

    @State private var amount: Decimal
    @State private var currency: String
    @State private var cycle: Subscription.Cycle
    @State private var usesDetectedDate: Bool
    @State private var anchor: Date

    /// 결제일을 알려주는 서비스.
    private var canDetect: Bool { account.service == .claude || account.service == .cursor }

    init(account: Account, detected: DetectedBilling?) {
        self.account = account
        self.detected = detected
        let current = account.subscription
        let canDetect = account.service == .claude || account.service == .cursor
        _amount = State(initialValue: current?.amount ?? 0)
        _currency = State(initialValue: current?.currency ?? detected?.currency ?? "USD")
        _cycle = State(initialValue: current?.cycle ?? detected?.cycle ?? .monthly)
        // 새로 입력할 때, 결제일을 알려주는 서비스면 가져오기를 기본으로 한다.
        _usesDetectedDate = State(initialValue: current.map { $0.anchor == nil } ?? canDetect)
        _anchor = State(initialValue: current?.anchor ?? detected?.nextCharge ?? .now)
    }

    var body: some View {
        Form {
            TextField("금액", value: $amount, format: .number)
            Picker("통화", selection: $currency) {
                ForEach(Subscription.currencies, id: \.self) { Text($0).tag($0) }
            }
            Picker("주기", selection: $cycle) {
                Text("매월").tag(Subscription.Cycle.monthly)
                Text("매년").tag(Subscription.Cycle.yearly)
            }
            .pickerStyle(.segmented)
            if canDetect {
                Toggle("결제일을 \(account.service.displayName)에서 가져오기", isOn: $usesDetectedDate)
            }
            if canDetect && usesDetectedDate {
                Text(detected.map { String(localized: "다음 결제일: \(RenewalText.string($0.nextCharge))") } ?? String(localized: "아직 가져온 결제일이 없습니다. 다음 새로고침 때 가져옵니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                DatePicker(String(localized: "결제일"), selection: $anchor, displayedComponents: .date)
                Text("지난 결제일이나 다음 결제일 중 아무 날이나 하나 넣으면 됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if account.subscription != nil {
                    Button("지우기", role: .destructive) {
                        store.setSubscription(nil, for: account.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("저장") {
                    let date = canDetect && usesDetectedDate ? nil : anchor
                    store.setSubscription(Subscription(amount: amount, currency: currency, cycle: cycle, anchor: date), for: account.id)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(amount <= 0)
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
    }
}
