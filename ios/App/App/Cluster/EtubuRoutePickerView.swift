import SwiftUI
import UIKit

/// Tek kutucuk — kalkış sabit “Konumum”, varış araması web RouteGuard ile aynı.
/// Yazım sırasında alan + öneriler klavye altında kalmaz.
struct EtubuRoutePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared
    @ObservedObject private var premium = EtubuPremiumManager.shared
    @ObservedObject private var warnings = EtubuDriveWarnings.shared

    private let fromFixed = "Konumum"
    private var theme: ClusterTheme { ClusterTheme.stored }

    @State private var toText = ""
    @State private var suggestions: [EtubuRoutePlace] = []
    @State private var isSearching = false
    @State private var indexReady = false
    @State private var indexLoading = true
    @State private var isPlanning = false
    @State private var statusMessage = ""
    @State private var routeStatus = EtubuRouteStatus(active: false, fromLabel: "", toLabel: "", statusText: "", briefText: "")
    @State private var searchTask: Task<Void, Never>?
    @State private var destinationNeedsDistrict = false
    @State private var toResolved = false
    @State private var selectedToPlace: EtubuRoutePlace? = nil
    @State private var suppressFieldChange = false
    @State private var sheetDetent: PresentationDetent = .large
    @State private var showPremiumPaywall = false
    @FocusState private var toFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                theme.canvas.ignoresSafeArea()
                LinearGradient(
                    colors: theme.canvasGradient,
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Üst: rota özeti / öneriler — TextField buraya taşınmaz
                    Group {
                        if toFocused {
                            if !statusMessage.isEmpty {
                                Text(statusMessage)
                                    .font(.caption2)
                                    .foregroundStyle(theme.mutedText)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 8)
                            }
                            if routeStatus.active || !toText.isEmpty {
                                clearRow
                                    .padding(.horizontal, 20)
                                    .padding(.top, 4)
                                    .padding(.bottom, 4)
                            }
                            if isSearching && suggestions.isEmpty && toText.count >= 2 {
                                HStack(spacing: 8) {
                                    ProgressView().tint(theme.accent).scaleEffect(0.65)
                                    Text(EtubuClusterL10n.t("searching"))
                                        .font(.caption2)
                                        .foregroundStyle(theme.accent.opacity(0.7))
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 20)
                            }
                            if !suggestions.isEmpty {
                                suggestionsList
                                    .padding(.horizontal, 16)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            } else {
                                Spacer(minLength: 0)
                            }
                        } else {
                            if !statusMessage.isEmpty {
                                Text(statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(theme.mutedText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 24)
                                    .padding(.top, 8)
                                    .padding(.bottom, 4)
                            }
                            if indexLoading {
                                HStack(spacing: 8) {
                                    ProgressView().tint(theme.accent).scaleEffect(0.8)
                                    Text(EtubuClusterL10n.t("trDirectoryPreparing"))
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
                                    if !suggestions.isEmpty {
                                        suggestionsList
                                            .frame(maxHeight: 260, alignment: .top)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 16)
                            }
                            .scrollDismissesKeyboard(.interactively)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    // Alt: TextField kimliği SABİT — odak/klavye layout’u yeniden yaratmaz
                    VStack(spacing: 8) {
                        destinationField(landscape: false, kbOpen: toFocused)
                        planAndDoneButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .background(theme.canvas.opacity(toFocused ? 0.98 : 0))
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
                    Button(EtubuClusterL10n.close) { toFocused = false }
                        .fontWeight(.semibold)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .environment(\.locale, Locale(identifier: "tr_TR"))
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("etubu.route.picker")
        .sheet(isPresented: $showPremiumPaywall) {
            EtubuPremiumPaywallView(accent: theme.accent, highlight: EtubuClusterL10n.t("premiumLockedRoute"))
                .presentationDetents([.large, .medium])
        }
        .onAppear {
            EtubuClusterPresenter.shared.hideCapacitorChrome()
            EtubuRouteBridge.primeWarningAudio()
            EtubuMapLocationHelper.shared.startIfNeeded()
            EtubuRouteBridge.pushNativeLocationToWeb()
            statusMessage = ""
            sheetDetent = .large
            EtubuRouteBridge.ensureIndex { ready in
                indexLoading = false
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    toFocused = true
                }
                if toText.count >= 2 {
                    refreshSuggestions(for: toText)
                }
            }
        }
    }

    /// Rota kur: özet aynı ekranda kalsın. Aktif rotada Tamam kapatır.
    private var planAndDoneButton: some View {
        Button {
            if canPlanRoute {
                planRoute(andDismiss: false)
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
        .accessibilityIdentifier("etubu.route.plan")
        .accessibilityLabel(planDoneLabel)
    }

    private var planDoneLabel: String {
        if isPlanning { return EtubuClusterL10n.planning }
        if canPlanRoute { return EtubuClusterL10n.planRoute }
        if routeStatus.active { return EtubuClusterL10n.done }
        return EtubuClusterL10n.planRoute
    }

    private var clearRow: some View {
        Button {
            EtubuRouteBridge.clear()
            toText = ""
            toResolved = false
            selectedToPlace = nil
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
                    prompt: Text(EtubuClusterL10n.t("cityDistrict")).foregroundStyle(theme.mutedText)
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
                .accessibilityLabel(EtubuClusterL10n.t("cityDistrict"))
                .accessibilityIdentifier("etubu.route.to")
                .onSubmit {
                    if canPlanRoute { planRoute(andDismiss: false) }
                    else { commitDestination() }
                }

                if !toText.isEmpty {
                    Button {
                        toText = ""
                        toResolved = false
                        selectedToPlace = nil
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
                selectedToPlace = nil
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
                    .accessibilityHidden(true)
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
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { idx, place in
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
                    .accessibilityIdentifier(idx == 0 ? "etubu.route.suggestion.first" : "etubu.route.suggestion.\(idx)")
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
                Text(routeStatus.navOnly ? EtubuClusterL10n.t("navRoute") : EtubuClusterL10n.t("activeRoute"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(routeStatus.navOnly ? theme.accent : Color.green)
                Spacer()
                if displayHazardCount > 0 {
                    Text(String(format: EtubuClusterL10n.t("hazardPointsFmt"), displayHazardCount))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.mutedText)
                }
            }
            Text("\(fromFixed) → \(routeStatus.toLabel.isEmpty ? toText : routeStatus.toLabel)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.primaryText)
                .accessibilityIdentifier("etubu.route.summary")
                .accessibilityAddTraits(.isStaticText)
            Button {
                if EtubuVehicleTelemetry.shared.needsChargeStop
                    || !EtubuEvRoutePlanner.shared.suggestedStops.isEmpty {
                    EtubuRouteBridge.openNearestChargeInMaps()
                } else {
                    EtubuRouteBridge.openInMaps(destinationName: routeStatus.toLabel.isEmpty ? toText : routeStatus.toLabel)
                }
            } label: {
                Label(
                    EtubuVehicleTelemetry.shared.needsChargeStop
                        || !EtubuEvRoutePlanner.shared.suggestedStops.isEmpty
                        ? EtubuClusterL10n.t("nearestChargeMaps")
                        : EtubuClusterL10n.t("openAppleMaps"),
                    systemImage: "map"
                )
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
            .accessibilityIdentifier("etubu.route.openMaps")
            if routeStatus.navOnly {
                Text(EtubuClusterL10n.t("overseasRouteNote"))
                    .font(.caption)
                    .foregroundStyle(theme.accent.opacity(0.75))
            } else {
                Text(EtubuClusterL10n.t("shortSummary"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.mutedText)
                EtubuRouteBriefChipsView(brief: displayBrief, compact: false)
                    .accessibilityIdentifier("etubu.route.brief")

                // Detaylı liste — şarj / radar / koridor / hava + konum
                if !displayHazards.isEmpty {
                    Text(EtubuClusterL10n.t("criticalPoints"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(displayHazards.enumerated()), id: \.element.id) { idx, h in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: EtubuHazardChrome.icon(h.kind))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(EtubuHazardChrome.tint(h.kind, urgent: false, theme: .aurora))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(h.kindTitle)
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
                            if idx < displayHazards.count - 1 {
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
            if !displayBrief.hasAny, !routeStatus.briefText.isEmpty, !routeStatus.navOnly {
                Text(routeStatus.briefText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(4)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etubu.route.active")
        .overlay(alignment: .top) {
            Rectangle()
                .fill((routeStatus.navOnly ? theme.accent : Color.green).opacity(0.35))
                .frame(height: 0.5)
        }
    }

    /// Cap status boşken native plan brief’ini kullan.
    private var displayBrief: EtubuRouteBriefSummary {
        if routeStatus.brief.hasAny { return routeStatus.brief }
        if warnings.brief.hasAny { return warnings.brief }
        return routeStatus.brief
    }

    private var displayHazards: [EtubuRouteHazard] {
        if !routeStatus.hazardDetails.isEmpty { return routeStatus.hazardDetails }
        return warnings.hazards
    }

    private var displayHazardCount: Int {
        max(routeStatus.hazardCount, displayHazards.count)
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
        // İlçe zorunluluğu kalktı — şehir / OSM noktası yeterli.
        return true
    }

    private func refreshDistrictRequirement(for text: String) {
        // Eski ilçe uyarısı kaldırıldı; arama OSM ile tamamlanır.
        destinationNeedsDistrict = false
        if statusMessage.contains("ilçe seçin") {
            statusMessage = ""
        }
    }

    private func select(_ place: EtubuRoutePlace) {
        suppressFieldChange = true
        searchTask?.cancel()
        toText = place.label
        selectedToPlace = place
        toResolved = true
        destinationNeedsDistrict = false
        statusMessage = ""
        suggestions = []
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            suppressFieldChange = false
        }
    }

    private func commitDestination() {
        let raw = toText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        // Seçili öneri varsa doğrudan kullan
        if let selected = selectedToPlace, selected.lat != nil {
            toResolved = true
            destinationNeedsDistrict = false
            return
        }
        EtubuRouteBridge.resolve(text: raw) { place in
            guard let place else {
                toResolved = false
                return
            }
            suppressFieldChange = true
            toText = place.label
            selectedToPlace = place
            toResolved = true
            destinationNeedsDistrict = false
            statusMessage = ""
            suggestions = []
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { suppressFieldChange = false }
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
                    statusMessage = "Liste yükleniyor — birkaç saniye…"
                } else if statusMessage.isEmpty || statusMessage.contains("yükleniyor") {
                    statusMessage = "Sonuç yok — şehir veya yer adı yazın"
                }
            } else if statusMessage.contains("Sonuç yok") || statusMessage.contains("yükleniyor") {
                statusMessage = ""
            }
        }
    }

    private func planRoute(andDismiss: Bool = false) {
        if !premium.isPremium {
            if !premium.entitlementReady {
                Task { @MainActor in
                    await premium.ensureEntitlementChecked()
                    planRoute(andDismiss: andDismiss)
                }
                return
            }
            showPremiumPaywall = true
            statusMessage = EtubuClusterL10n.t("premiumLockedRoute")
            return
        }
        isPlanning = true
        statusMessage = "Yerler çözülüyor…"
        let toRaw = toText.trimmingCharacters(in: .whitespacesAndNewlines)

        func fail(_ msg: String) {
            isPlanning = false
            statusMessage = msg
        }

        // İlçe şartı yok — seçili yer veya resolve (TR index → OSM).
        let planFromSelected: () -> Void = {
            if let sel = selectedToPlace, sel.lat != nil, sel.lng != nil {
                toText = sel.label
                toResolved = true
                statusMessage = "Rotaya alınıyor: \(fromFixed) → \(sel.label)"
                EtubuRouteBridge.primeWarningAudio()
                EtubuRouteBridge.plan(from: fromFixed, to: sel.label, toPlace: sel) { ok, msg in
                    isPlanning = false
                    statusMessage = msg
                    telemetry.routeDestLat = sel.lat
                    telemetry.routeDestLng = sel.lng
                    if ok {
                        telemetry.routeActive = true
                        telemetry.routeTo = sel.label
                        telemetry.navDestination = sel.label
                        if telemetry.routeFrom.isEmpty { telemetry.routeFrom = fromFixed }
                    }
                    EtubuRouteBridge.status { st in
                        routeStatus = st
                        if st.active || ok || telemetry.routeActive {
                            telemetry.routeActive = true
                            telemetry.routeFrom = st.fromLabel.isEmpty
                                ? (telemetry.routeFrom.isEmpty ? fromFixed : telemetry.routeFrom)
                                : st.fromLabel
                            telemetry.routeTo = st.toLabel.isEmpty ? sel.label : st.toLabel
                            telemetry.navDestination = telemetry.routeTo
                            routeStatus.active = true
                            if routeStatus.toLabel.isEmpty { routeStatus.toLabel = sel.label }
                            if routeStatus.fromLabel.isEmpty { routeStatus.fromLabel = fromFixed }
                            if !st.toLabel.isEmpty { toText = st.toLabel }
                            if !st.hazardDetails.isEmpty {
                                EtubuDriveWarnings.shared.hazards = st.hazardDetails
                                EtubuDriveWarnings.shared.remainingHazards = st.hazardDetails
                            }
                            Self.applyBriefFromStatus(st, warnings: warnings, routeStatus: &routeStatus)
                            toFocused = false
                            if andDismiss { dismiss() }
                        } else {
                            telemetry.routeActive = st.active
                            telemetry.routeFrom = st.fromLabel.isEmpty ? fromFixed : st.fromLabel
                            telemetry.routeTo = st.toLabel
                            telemetry.navDestination = st.toLabel
                        }
                        EtubuEvRoutePlanner.shared.refreshFromLiveState()
                    }
                    EtubuDriveWarnings.shared.startPolling()
                    EtubuMapLocationHelper.shared.enableBackgroundForRouteIfNeeded()
                    if #available(iOS 16.2, *) {
                        Task { await EtubuLiveActivityController.publishCurrent() }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        EtubuDriveWarnings.shared.startPolling()
                    }
                }
                return
            }
            EtubuRouteBridge.resolve(text: toRaw) { toPlace in
                guard let toPlace else {
                    fail(String(format: EtubuClusterL10n.t("routePlaceNotFoundOsmFmt"), toRaw))
                    toResolved = false
                    return
                }
                toText = toPlace.label
                toResolved = true
                selectedToPlace = toPlace
                statusMessage = String(format: EtubuClusterL10n.t("routePlanningFmt"), fromFixed, toPlace.label)
                EtubuRouteBridge.primeWarningAudio()
                EtubuRouteBridge.plan(from: fromFixed, to: toPlace.label, toPlace: toPlace) { ok, msg in
                    isPlanning = false
                    statusMessage = msg
                    telemetry.routeDestLat = toPlace.lat
                    telemetry.routeDestLng = toPlace.lng
                    if ok {
                        telemetry.routeActive = true
                        telemetry.routeTo = toPlace.label
                        telemetry.navDestination = toPlace.label
                        if telemetry.routeFrom.isEmpty { telemetry.routeFrom = fromFixed }
                    }
                    EtubuRouteBridge.status { st in
                        routeStatus = st
                        if st.active || ok || telemetry.routeActive {
                            telemetry.routeActive = true
                            telemetry.routeFrom = st.fromLabel.isEmpty
                                ? (telemetry.routeFrom.isEmpty ? fromFixed : telemetry.routeFrom)
                                : st.fromLabel
                            telemetry.routeTo = st.toLabel.isEmpty ? toPlace.label : st.toLabel
                            telemetry.navDestination = telemetry.routeTo
                            routeStatus.active = true
                            if routeStatus.toLabel.isEmpty { routeStatus.toLabel = toPlace.label }
                            if routeStatus.fromLabel.isEmpty { routeStatus.fromLabel = fromFixed }
                            if !st.toLabel.isEmpty { toText = st.toLabel }
                            if !st.hazardDetails.isEmpty {
                                EtubuDriveWarnings.shared.hazards = st.hazardDetails
                                EtubuDriveWarnings.shared.remainingHazards = st.hazardDetails
                            }
                            Self.applyBriefFromStatus(st, warnings: warnings, routeStatus: &routeStatus)
                            toFocused = false
                            if andDismiss { dismiss() }
                        } else {
                            telemetry.routeActive = st.active
                            telemetry.routeFrom = st.fromLabel.isEmpty ? fromFixed : st.fromLabel
                            telemetry.routeTo = st.toLabel
                            telemetry.navDestination = st.toLabel
                        }
                        EtubuEvRoutePlanner.shared.refreshFromLiveState()
                    }
                    EtubuDriveWarnings.shared.startPolling()
                    EtubuMapLocationHelper.shared.enableBackgroundForRouteIfNeeded()
                    if #available(iOS 16.2, *) {
                        Task { await EtubuLiveActivityController.publishCurrent() }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        EtubuDriveWarnings.shared.startPolling()
                    }
                }
            }
        }
        planFromSelected()
    }

    private static func applyBriefFromStatus(
        _ st: EtubuRouteStatus,
        warnings: EtubuDriveWarnings,
        routeStatus: inout EtubuRouteStatus
    ) {
        if st.brief.hasAny {
            EtubuDriveWarnings.shared.brief = st.brief
            EtubuDriveWarnings.shared.remainingBrief = st.brief
            routeStatus.brief = st.brief
        } else if warnings.brief.hasAny {
            routeStatus.brief = warnings.brief
        } else if !st.hazardDetails.isEmpty {
            var s = EtubuRouteBriefSummary()
            for h in st.hazardDetails {
                switch h.kind {
                case "corridor": s.corridorCount += 1
                case "charge":
                    s.chargeCount += 1
                    if !h.label.isEmpty, s.chargeNames.count < 4 { s.chargeNames.append(h.label) }
                case "weather":
                    s.weatherCount += 1
                    if !h.label.isEmpty, s.weatherLabels.count < 4 { s.weatherLabels.append(h.label) }
                case "control": s.controlCount += 1
                default: s.radarCount += 1
                }
            }
            if s.hasAny {
                routeStatus.brief = s
                EtubuDriveWarnings.shared.brief = s
                EtubuDriveWarnings.shared.remainingBrief = s
            }
        }
    }
}
