import SwiftUI
import UIKit

/// Tek kutucuk — kalkış sabit “Konumum”, varış araması web RouteGuard ile aynı.
/// Yazım sırasında alan + öneriler klavye altında kalmaz.
struct EtubuRoutePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared

    private let fromFixed = "Konumum"
    private var theme: ClusterTheme { ClusterTheme.stored }

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
    @State private var sheetDetent: PresentationDetent = .large
    @FocusState private var toFocused: Bool

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let landscape = geo.size.width > geo.size.height
                let kbOpen = toFocused
                let suggestMax: CGFloat = landscape
                    ? (kbOpen ? 72 : 140)
                    : (kbOpen ? 140 : 260)

                ZStack {
                    theme.canvas.ignoresSafeArea()
                    LinearGradient(
                        colors: theme.canvasGradient,
                        startPoint: .topLeading,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()

                    VStack(spacing: 0) {
                        if !kbOpen {
                            if !statusMessage.isEmpty {
                                Text(statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(theme.mutedText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 24)
                                    .padding(.top, 8)
                                    .padding(.bottom, 4)
                            }
                            if !indexReady {
                                HStack(spacing: 8) {
                                    ProgressView().tint(theme.accent).scaleEffect(0.8)
                                    Text("TR yer dizini hazırlanıyor…")
                                        .font(.caption)
                                        .foregroundStyle(theme.accent.opacity(0.85))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 6)
                            }
                            ScrollView {
                                VStack(alignment: .leading, spacing: 16) {
                                    if routeStatus.active || !routeStatus.briefText.isEmpty {
                                        activeRouteCard
                                    }
                                    clearRow
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 16)
                            }
                            .scrollDismissesKeyboard(.interactively)
                        } else {
                            Spacer(minLength: 0)
                            if !statusMessage.isEmpty {
                                Text(statusMessage)
                                    .font(.caption2)
                                    .foregroundStyle(theme.mutedText)
                                    .lineLimit(2)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 4)
                            }
                        }

                        VStack(spacing: landscape && kbOpen ? 6 : 8) {
                            destinationField(landscape: landscape, kbOpen: kbOpen)

                            if isSearching && suggestions.isEmpty && toText.count >= 2 {
                                HStack(spacing: 8) {
                                    ProgressView().tint(theme.accent).scaleEffect(0.65)
                                    Text("Aranıyor…")
                                        .font(.caption2)
                                        .foregroundStyle(theme.accent.opacity(0.7))
                                    Spacer(minLength: 0)
                                }
                            }

                            if !suggestions.isEmpty {
                                suggestionsList
                                    .frame(maxHeight: suggestMax, alignment: .top)
                                    .clipped()
                            }

                            planAndDoneButton
                        }
                        .padding(.horizontal, landscape ? 14 : 20)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                        .background(theme.canvas.opacity(kbOpen ? 0.98 : 0))
                    }
                }
            }
            .navigationTitle(EtubuClusterL10n.route)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(EtubuClusterL10n.close) {
                        toFocused = false
                        dismiss()
                    }
                    .foregroundStyle(theme.accent)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Kapat") { toFocused = false }
                        .fontWeight(.semibold)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .environment(\.locale, Locale(identifier: "tr_TR"))
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            EtubuClusterPresenter.shared.hideCapacitorChrome()
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
                    if st.active, !st.toLabel.isEmpty {
                        toText = st.toLabel
                        toResolved = true
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    toFocused = true
                }
                if toText.count >= 2 {
                    refreshSuggestions(for: toText)
                }
            }
        }
    }

    /// Rotayı kur + Tamam birleşik: kurunca ana ekrana döner.
    private var planAndDoneButton: some View {
        Button {
            if canPlanRoute {
                planRoute(andDismiss: true)
            } else if routeStatus.active {
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                if isPlanning {
                    ProgressView().tint(.black).scaleEffect(0.85)
                } else {
                    Image(systemName: routeStatus.active && !canPlanRoute
                          ? "checkmark"
                          : "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.body.weight(.semibold))
                }
                Text(planDoneLabel)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.black)
            .background(
                (canPlanRoute || routeStatus.active ? theme.accent : theme.accent.opacity(0.35)),
                in: Capsule()
            )
        }
        .disabled((!canPlanRoute && !routeStatus.active) || isPlanning)
    }

    private var planDoneLabel: String {
        if isPlanning { return EtubuClusterL10n.planning }
        if canPlanRoute { return "\(EtubuClusterL10n.planRoute) · \(EtubuClusterL10n.done)" }
        if routeStatus.active { return EtubuClusterL10n.done }
        return EtubuClusterL10n.planRoute
    }

    private var clearRow: some View {
        Button {
            EtubuRouteBridge.clear()
            toText = ""
            toResolved = false
            destinationNeedsDistrict = false
            suggestions = []
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
                .padding(.vertical, 12)
                .foregroundStyle(theme.secondaryText)
                .background(Color.white.opacity(0.06), in: Capsule())
        }
    }

    /// Çerçevesiz alan — yatayda yazılan metin her zaman okunaklı.
    private func destinationField(landscape: Bool, kbOpen: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(fromFixed.uppercased(with: Locale(identifier: "tr_TR")))
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(theme.mutedText)
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.accent.opacity(0.55))
                Text(EtubuClusterL10n.to.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(theme.secondaryText)
                Spacer(minLength: 0)
                if toResolved {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.accent.opacity(0.8))
                }
            }

            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 5, height: 5)
                    .shadow(color: theme.glow, radius: toFocused ? 4 : 0)

                TextField(
                    "",
                    text: $toText,
                    prompt: Text("sadece il ilçe yazınız").foregroundStyle(theme.mutedText)
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
                .keyboardType(.default)
                .textContentType(.none)
                .submitLabel(.go)
                .font(.system(size: (kbOpen && landscape) ? 22 : (kbOpen ? 20 : 17), weight: .semibold))
                .foregroundStyle(Color.white)
                .tint(theme.accent)
                .focused($toFocused)
                .onSubmit {
                    if canPlanRoute { planRoute(andDismiss: true) }
                    else { commitDestination() }
                }

                if !toText.isEmpty {
                    Button {
                        toText = ""
                        toResolved = false
                        suggestions = []
                        destinationNeedsDistrict = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(theme.mutedText)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, kbOpen ? 12 : 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(kbOpen ? 0.14 : 0.08))
            )
            .onChange(of: toText) { _, newValue in
                if suppressFieldChange { return }
                let nfc = newValue.precomposedStringWithCanonicalMapping
                if nfc != newValue {
                    suppressFieldChange = true
                    toText = nfc
                    DispatchQueue.main.async { suppressFieldChange = false }
                }
                toResolved = false
                scheduleSearch(nfc)
                refreshDistrictRequirement(for: nfc)
            }

            if kbOpen, !toText.isEmpty {
                Text(toText)
                    .font(.system(size: landscape ? 18 : 15, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            Rectangle()
                .fill(toFocused ? theme.accent.opacity(0.75) : theme.stroke)
                .frame(height: toFocused ? 1.2 : 0.6)
                .animation(.easeOut(duration: 0.18), value: toFocused)
        }
        .environment(\.locale, Locale(identifier: "tr_TR"))
    }

    private var suggestionsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions) { place in
                    Button {
                        select(place)
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Circle()
                                .fill(theme.accent.opacity(0.85))
                                .frame(width: 4, height: 4)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(place.label)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(theme.primaryText)
                                    .multilineTextAlignment(.leading)
                                if !place.cityName.isEmpty || !place.districtName.isEmpty {
                                    Text([
                                        place.cityName.isEmpty ? nil : place.cityName.uppercased(with: Locale(identifier: "tr_TR")),
                                        place.districtName.isEmpty ? nil : place.districtName
                                    ]
                                    .compactMap { $0 }
                                    .joined(separator: " · "))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(theme.mutedText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if place.id != suggestions.last?.id {
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 0.5)
                            .padding(.leading, 14)
                    }
                }
            }
        }
    }


    private var activeRouteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(routeStatus.navOnly ? theme.accent : Color.green).frame(width: 6, height: 6)
                Text(routeStatus.navOnly ? "Navigasyon rotası" : "Aktif rota")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(routeStatus.navOnly ? theme.accent : Color.green)
                Spacer()
                if routeStatus.hazardCount > 0 {
                    Text("\(routeStatus.hazardCount) nokta")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.mutedText)
                }
            }
            Text("\(fromFixed) → \(routeStatus.toLabel.isEmpty ? toText : routeStatus.toLabel)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.primaryText)
            if routeStatus.navOnly {
                Text("Yurt dışı veya OSRM yedek — radar / koridor / EGM noktaları yok; harita çizimi aktif.")
                    .font(.caption)
                    .foregroundStyle(theme.accent.opacity(0.75))
            } else {
                Text("Kısa özet")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.mutedText)
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
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill((routeStatus.navOnly ? theme.accent : Color.green).opacity(0.35))
                .frame(height: 0.5)
        }
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
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            suggestions = []
            isSearching = false
            return
        }
        // Anında “aranıyor” göster — kullanıcı yazarken boş ekran görmesin
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
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
        // Sheet klavye açıkken büyük kalsın; öneriler üstte sabit
        if sheetDetent != .large {
            sheetDetent = .large
        }
        let requestQuery = query
        EtubuRouteBridge.search(query: requestQuery, forFrom: false) { places in
            // Eski sonuçları geç yazılan sorguya uygulama
            guard requestQuery == toText || requestQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    == toText.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }
            withAnimation(.easeOut(duration: 0.15)) {
                suggestions = places
                isSearching = false
            }
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

    private func planRoute(andDismiss: Bool = false) {
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
                            if andDismiss {
                                toFocused = false
                                dismiss()
                            }
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
