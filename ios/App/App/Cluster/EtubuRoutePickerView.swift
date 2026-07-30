import SwiftUI
import UIKit

/// Tek kutucuk — kalkış sabit “Konumum”, varış araması web RouteGuard ile aynı.
/// Yazım sırasında alan + öneriler klavye altında kalmaz.
struct EtubuRoutePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared

    private let fromFixed = "Konumum"

    @State private var toText = ""
    @State private var suggestions: [EtubuRoutePlace] = []
    @State private var isSearching = false
    @State private var indexReady = false
    @State private var isPlanning = false
    @State private var statusMessage = ""
    @State private var routeStatus = EtubuRouteStatus(active: false, fromLabel: "", toLabel: "", statusText: "", briefText: "")
    @State private var searchTask: Task<Void, Never>?
    @State private var destinationNeedsDistrict = false
    @State private var toResolved = false
    @State private var suppressFieldChange = false
    @State private var showPlanSummary = false
    @State private var keyboardInset: CGFloat = 0
    @State private var sheetDetent: PresentationDetent = .large
    @FocusState private var toFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                LinearGradient(
                    colors: [
                        Color(hue: 0.52, saturation: 0.55, brightness: 0.18),
                        Color.black,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .opacity(0.85)

                VStack(spacing: 0) {
                    // TextField üstte sabit — klavye açılınca yazılan yer görünür kalır
                    destinationCard
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 10)

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 6)
                    }

                    if !indexReady {
                        HStack(spacing: 8) {
                            ProgressView().tint(.cyan).scaleEffect(0.8)
                            Text("TR yer dizini hazırlanıyor…")
                                .font(.caption)
                                .foregroundStyle(.cyan.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 6)
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if !suggestions.isEmpty {
                                    suggestionsCard
                                        .id("suggestions")
                                }
                                actionsRow
                                    .id("actions")
                                if routeStatus.active || !routeStatus.briefText.isEmpty {
                                    activeRouteCard
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: suggestions.count) { _, count in
                            guard count > 0 else { return }
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("suggestions", anchor: .top)
                            }
                        }
                        .onChange(of: keyboardInset) { _, inset in
                            guard inset > 0, !suggestions.isEmpty else { return }
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("suggestions", anchor: .top)
                            }
                        }
                    }

                    if showPlanSummary && keyboardInset <= 0 {
                        routeSummaryBar
                    }
                }
                .padding(.bottom, max(0, keyboardInset > 0 ? max(8, keyboardInset - 12) : 0))
            }
            .navigationTitle(EtubuClusterL10n.route)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(EtubuClusterL10n.close) { dismiss() }
                        .foregroundStyle(.cyan)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Tamam") {
                        toFocused = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .foregroundStyle(.cyan)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.medium, .large], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(toFocused && keyboardInset > 0)
        .onAppear {
            EtubuClusterPresenter.shared.hideCapacitorChrome()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            EtubuRouteBridge.primeWarningAudio()
            EtubuMapLocationHelper.shared.startIfNeeded()
            statusMessage = ""
            sheetDetent = .large
            EtubuRouteBridge.ensureIndex { ready in
                indexReady = ready
                if !ready {
                    statusMessage = "Liste gecikti — yine de arayabilirsiniz"
                }
                EtubuRouteBridge.status { st in
                    routeStatus = st
                    if st.active {
                        showPlanSummary = true
                        if !st.toLabel.isEmpty {
                            toText = st.toLabel
                            toResolved = true
                        }
                    }
                }
                toFocused = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    sheetDetent = .large
                    toFocused = true
                }
                if toText.count >= 2 {
                    refreshSuggestions(for: toText)
                }
            }
        }
        .onChange(of: toFocused) { _, focused in
            if focused {
                withAnimation(.easeOut(duration: 0.2)) {
                    sheetDetent = .large
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            applyKeyboardFrame(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) {
                keyboardInset = 0
            }
        }
    }

    /// Sheet / landscape’te ekran yüksekliği yerine pencere overlap kullan.
    private func applyKeyboardFrame(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        let overlap: CGFloat
        if let window {
            let kb = window.convert(frame, from: nil)
            overlap = max(0, window.bounds.maxY - kb.minY)
        } else {
            let screenH = UIScreen.main.bounds.height
            overlap = max(0, screenH - frame.minY)
        }
        // Sheet zaten kısmen yukarıda; aşırı padding’i kırp
        let capped = min(overlap, UIScreen.main.bounds.height * 0.55)
        withAnimation(.easeOut(duration: 0.2)) {
            keyboardInset = capped
            if capped > 40 { sheetDetent = .large }
        }
    }

    private var routeSummaryBar: some View {
        VStack(spacing: 10) {
            Divider().overlay(Color.white.opacity(0.12))
            HStack {
                Text(EtubuClusterL10n.t("routeSummary"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            }
            Text("\(fromFixed) → \(routeStatus.toLabel.isEmpty ? toText : routeStatus.toLabel)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            if routeStatus.brief.hasAny {
                EtubuRouteBriefChipsView(brief: routeStatus.brief, compact: true)
            } else if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                dismiss()
            } label: {
                Text(EtubuClusterL10n.done)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.black)
                    .background(Color.cyan, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(Color.black.opacity(0.92))
    }

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "flag.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.cyan)
                Text(EtubuClusterL10n.to.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(fromFixed)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.cyan.opacity(0.18)))
                    .foregroundStyle(.cyan.opacity(0.9))
            }
            TextField("yazınız", text: $toText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .keyboardType(.default)
                .textContentType(.none)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .submitLabel(.search)
                .focused($toFocused)
                .onSubmit { commitDestination() }
                .onChange(of: toText) { _, newValue in
                    if suppressFieldChange { return }
                    toResolved = false
                    scheduleSearch(newValue)
                    refreshDistrictRequirement(for: newValue)
                }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Varış")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.45))
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.cyan)
                }
                Spacer()
                Text("\(suggestions.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            // Nested ScrollView yok — ana ScrollView içinde düz liste (ekran dışına taşmaz)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions) { place in
                    Button {
                        select(place)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle()
                                .fill(Color.white.opacity(0.25))
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                                if !place.cityName.isEmpty || !place.districtName.isEmpty {
                                    Text([
                                        place.cityName.isEmpty ? nil : place.cityName.uppercased(),
                                        place.districtName.isEmpty ? nil : place.districtName
                                    ]
                                    .compactMap { $0 }
                                    .joined(separator: " / "))
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white.opacity(0.62))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if place.id != suggestions.last?.id {
                        Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 30)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var actionsRow: some View {
        HStack(spacing: 12) {
            Button {
                planRoute()
            } label: {
                HStack {
                    if isPlanning {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    Text(isPlanning ? EtubuClusterL10n.planning : EtubuClusterL10n.planRoute)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.black)
                .background(
                    (canPlanRoute ? Color.cyan : Color.cyan.opacity(0.35)),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .disabled(!canPlanRoute)

            Button {
                EtubuRouteBridge.clear()
                toText = ""
                toResolved = false
                destinationNeedsDistrict = false
                suggestions = []
                showPlanSummary = false
                routeStatus = EtubuRouteStatus(active: false, fromLabel: fromFixed, toLabel: "", statusText: "", briefText: "")
                statusMessage = ""
                telemetry.routeActive = false
                EtubuDriveWarnings.shared.brief = EtubuRouteBriefSummary()
                EtubuDriveWarnings.shared.remainingBrief = EtubuRouteBriefSummary()
                EtubuDriveWarnings.shared.hazards = []
                EtubuDriveWarnings.shared.remainingHazards = []
                EtubuDriveWarnings.shared.routeCoords = []
                EtubuDriveWarnings.shared.queue = []
                EtubuDriveWarnings.shared.primary = nil
                toFocused = true
            } label: {
                Text(EtubuClusterL10n.clear)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white.opacity(0.85))
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var activeRouteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(routeStatus.navOnly ? Color.cyan : Color.green).frame(width: 8, height: 8)
                Text(routeStatus.navOnly ? "Navigasyon rotası" : "Aktif rota")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(routeStatus.navOnly ? Color.cyan : Color.green)
                Spacer()
                if routeStatus.hazardCount > 0 {
                    Text("\(routeStatus.hazardCount) nokta")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            Text("\(fromFixed) → \(routeStatus.toLabel.isEmpty ? toText : routeStatus.toLabel)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            if routeStatus.navOnly {
                Text("Yurt dışı veya OSRM yedek — radar / koridor / EGM noktaları yok; harita çizimi aktif.")
                    .font(.caption)
                    .foregroundStyle(.cyan.opacity(0.75))
            } else {
                // Kısa özet
                Text("Kısa özet")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.45))
                EtubuRouteBriefChipsView(brief: routeStatus.brief, compact: false)

                // Detaylı liste — şarj / radar / koridor / hava + konum
                if !routeStatus.hazardDetails.isEmpty {
                    Text("Kritik noktalar (detay)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(routeStatus.hazardDetails.enumerated()), id: \.element.id) { idx, h in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: EtubuHazardChrome.icon(h.kind))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(EtubuHazardChrome.tint(h.kind, urgent: false, theme: .aurora))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(h.kindTitleTR)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white.opacity(0.9))
                                    Text(detailLine(for: h, index: idx + 1))
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.55))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            if idx < routeStatus.hazardDetails.count - 1 {
                                Divider().overlay(Color.white.opacity(0.06))
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }
            }
            if !routeStatus.brief.hasAny, !routeStatus.briefText.isEmpty, !routeStatus.navOnly {
                Text(routeStatus.briefText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill((routeStatus.navOnly ? Color.cyan : Color.green).opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder((routeStatus.navOnly ? Color.cyan : Color.green).opacity(0.35), lineWidth: 1)
                )
        )
    }

    private func detailLine(for h: EtubuRouteHazard, index: Int) -> String {
        var parts: [String] = []
        if let along = h.alongKm, along > 0 {
            parts.append(String(format: "rota km %.1f", along))
        } else if let idx = h.routeIdx {
            parts.append("nokta #\(idx)")
        } else {
            parts.append("sıra \(index)")
        }
        if !h.label.isEmpty {
            parts.append(h.label)
        }
        if let lim = h.maxspeed, lim > 0 {
            parts.append("lim \(lim) km/h")
        }
        if let kw = h.kw, kw > 0 {
            parts.append("\(kw) kW")
        }
        if !h.distanceLabel.isEmpty {
            parts.append(h.distanceLabel)
        }
        return parts.joined(separator: " · ")
    }

    private var canPlanRoute: Bool {
        let to = toText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard to.count >= 2, !isPlanning else { return false }
        return !destinationNeedsDistrict
    }

    private func refreshDistrictRequirement(for text: String) {
        EtubuRouteBridge.needsDistrictPick(text: text) { needs in
            destinationNeedsDistrict = needs
            if needs {
                let name = text.trimmingCharacters(in: .whitespaces)
                statusMessage = "\(name) — ilçe seçin (ör. \(name) Çankaya)"
            } else if statusMessage.contains("ilçe seçin") {
                statusMessage = ""
            }
        }
    }

    private func select(_ place: EtubuRoutePlace) {
        suppressFieldChange = true
        searchTask?.cancel()
        toText = place.label
        toResolved = true
        destinationNeedsDistrict = false
        statusMessage = ""
        suggestions = []
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let label = place.label
        EtubuRouteBridge.needsDistrictPick(text: label) { needs in
            if needs {
                toResolved = false
                destinationNeedsDistrict = true
                statusMessage = "\(label) — ilçe seçin (ör. \(label) Çankaya)"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                suppressFieldChange = false
            }
        }
    }

    private func commitDestination() {
        let raw = toText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        EtubuRouteBridge.needsDistrictPick(text: raw) { needs in
            if needs {
                destinationNeedsDistrict = true
                toResolved = false
                statusMessage = "\(raw) — ilçe seçin (ör. \(raw) Çankaya)"
                return
            }
            EtubuRouteBridge.resolve(text: raw) { place in
                guard let place else {
                    toResolved = false
                    return
                }
                suppressFieldChange = true
                toText = place.label
                toResolved = true
                destinationNeedsDistrict = false
                statusMessage = ""
                suggestions = []
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { suppressFieldChange = false }
            }
        }
    }

    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { refreshSuggestions(for: query) }
        }
    }

    private func refreshSuggestions(for query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            suggestions = []
            isSearching = false
            return
        }
        isSearching = true
        EtubuRouteBridge.search(query: query, forFrom: false) { places in
            suggestions = places
            isSearching = false
            if places.isEmpty {
                if !indexReady {
                    statusMessage = "İlçe listesi yükleniyor — birkaç saniye…"
                } else if statusMessage.isEmpty || statusMessage.contains("yükleniyor") {
                    statusMessage = "Sonuç yok — il / ilçe yazın (ör. Ankara Çankaya)"
                }
            } else if statusMessage.contains("Sonuç yok") || statusMessage.contains("yükleniyor") {
                statusMessage = ""
            }
        }
    }

    private func planRoute() {
        guard EtubuAppLanguage.current.criticalAlertsEnabled else {
            statusMessage = "Kritik nokta / rota uyarıları yalnızca Türkçe dilinde. Ayarlar → Dil → Türkçe."
            return
        }
        isPlanning = true
        statusMessage = "Yerler çözülüyor…"
        let toRaw = toText.trimmingCharacters(in: .whitespacesAndNewlines)

        func fail(_ msg: String) {
            isPlanning = false
            statusMessage = msg
        }

        EtubuRouteBridge.needsDistrictPick(text: toRaw) { toNeeds in
            if toNeeds {
                fail("\(toRaw.trimmingCharacters(in: .whitespaces)) — ilçe seçin (ör. \(toRaw.trimmingCharacters(in: .whitespaces)) Çankaya)")
                destinationNeedsDistrict = true
                toResolved = false
                return
            }
            EtubuRouteBridge.resolve(text: toRaw) { toPlace in
                guard let toPlace else {
                    fail("\(toRaw) bulunamadı — listeden seçin")
                    toResolved = false
                    return
                }
                toText = toPlace.label
                toResolved = true
                statusMessage = "Rotaya alınıyor: \(fromFixed) → \(toPlace.label)"
                EtubuRouteBridge.primeWarningAudio()
                EtubuRouteBridge.plan(from: fromFixed, to: toPlace.label) { ok, msg in
                    isPlanning = false
                    statusMessage = msg
                    EtubuRouteBridge.status { st in
                        routeStatus = st
                        telemetry.routeActive = st.active
                        telemetry.routeFrom = st.fromLabel.isEmpty ? fromFixed : st.fromLabel
                        telemetry.routeTo = st.toLabel
                        if !st.toLabel.isEmpty { toText = st.toLabel }
                        if ok || st.active {
                            showPlanSummary = true
                        }
                        if !st.hazardDetails.isEmpty {
                            EtubuDriveWarnings.shared.hazards = st.hazardDetails
                            EtubuDriveWarnings.shared.remainingHazards = st.hazardDetails
                            EtubuDriveWarnings.shared.brief = st.brief
                            EtubuDriveWarnings.shared.remainingBrief = st.brief
                        }
                    }
                    EtubuDriveWarnings.shared.startPolling()
                    if #available(iOS 16.2, *) {
                        Task { await EtubuLiveActivityController.publishCurrent() }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        EtubuDriveWarnings.shared.startPolling()
                    }
                }
            }
        }
    }
}
