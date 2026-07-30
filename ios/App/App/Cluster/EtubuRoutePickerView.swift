import SwiftUI
import UIKit

/// Tek kutucuk — kalkış sabit “Konumum”, varış araması web RouteGuard ile aynı.
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
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            destinationCard
                            if !suggestions.isEmpty {
                                suggestionsCard
                            }
                            actionsRow
                            if routeStatus.active || !routeStatus.briefText.isEmpty {
                                activeRouteCard
                            }
                            if !statusMessage.isEmpty {
                                Text(statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.55))
                                    .padding(.horizontal, 4)
                            }
                            if !indexReady {
                                HStack(spacing: 8) {
                                    ProgressView().tint(.cyan).scaleEffect(0.8)
                                    Text("TR yer dizini hazırlanıyor…")
                                        .font(.caption)
                                        .foregroundStyle(.cyan.opacity(0.8))
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        .padding(20)
                        .padding(.bottom, (showPlanSummary && keyboardInset <= 0 ? 120 : 0) + max(0, keyboardInset - 8))
                    }

                    if showPlanSummary && keyboardInset <= 0 {
                        routeSummaryBar
                    }
                }
            }
            .navigationTitle(EtubuClusterL10n.route)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(EtubuClusterL10n.close) { dismiss() }
                        .foregroundStyle(.cyan)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            EtubuClusterPresenter.shared.hideCapacitorChrome()
            EtubuRouteBridge.primeWarningAudio()
            EtubuMapLocationHelper.shared.startIfNeeded()
            statusMessage = ""
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
                toFocused = true
                if toText.count >= 2 {
                    refreshSuggestions(for: toText)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screenH = UIScreen.main.bounds.height
            let overlap = max(0, screenH - frame.minY)
            withAnimation(.easeOut(duration: 0.2)) {
                keyboardInset = overlap
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) {
                keyboardInset = 0
            }
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
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ScrollView {
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
            .frame(maxHeight: suggestions.count > 8 ? 320 : .infinity)
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
                EtubuDriveWarnings.shared.hazards = []
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
                EtubuRouteBriefChipsView(brief: routeStatus.brief, compact: false)
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
                    }
                    EtubuDriveWarnings.shared.startPolling()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        EtubuDriveWarnings.shared.startPolling()
                    }
                }
            }
        }
    }
}
