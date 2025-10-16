//
//  SubwayDashboardViewModel.swift
//  mtahelper
//
//  Created by Codex on 10/15/24.
//

import CoreLocation
import Foundation
internal import Combine

@MainActor
final class SubwayDashboardViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case error(String)
    }

    private static let defaultMaximumDistance: CLLocationDistance = 1600

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var stations: [StationRealtime] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var activeAlerts: [ServiceAlert] = []
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published var maximumDistance: CLLocationDistance = defaultMaximumDistance {
        didSet {
            guard oldValue != maximumDistance else { return }
            if maximumDistance < 0 { maximumDistance = 0 }
            refresh()
        }
    }
    @Published private(set) var lastUpdatedRelative: String = ""

    private let locationService: LocationService
    private let stationRepository: StationRepository
    private let realtimeService: RealtimeService
    private let alertService: AlertService

    private var refreshTask: Task<Void, Never>?
    private var relativeUpdateTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    init(
        locationService: LocationService? = nil,
        stationRepository: StationRepository = .shared,
        realtimeService: RealtimeService = RealtimeService(),
        alertService: AlertService = AlertService()
    ) {
        let locationService = locationService ?? LocationService()
        self.locationService = locationService
        self.stationRepository = stationRepository
        self.realtimeService = realtimeService
        self.alertService = alertService
        self.authorizationStatus = locationService.authorizationStatus
    }

    deinit {
        relativeUpdateTask?.cancel()
        autoRefreshTask?.cancel()
    }

    func onAppear() {
        guard phase == .idle else { return }
        refresh()
    }

    func refresh(silently: Bool = false) {
        refreshTask?.cancel()
        if !silently {
            phase = .loading
        }
        refreshTask = Task { [weak self] in
            guard let self else { return }

            do {
                let location = try await locationService.requestLocation()
                authorizationStatus = locationService.authorizationStatus

                let nearbyStations = stationRepository.nearestStations(
                    to: location.coordinate,
                    limit: 5,
                    maximumDistance: maximumDistance,
                    allowFallback: maximumDistance >= Self.defaultMaximumDistance
                )

                async let realtimeTask = realtimeService.fetchRealtime(for: nearbyStations)
                async let alertsTask = alertService.fetchAlerts()

                let realtime = try await realtimeTask
                let alerts = try await alertsTask

                let activeAlerts = alerts.filter { $0.isActiveNow }
                var relevantAlertSet: Set<ServiceAlert> = []

                let decorated = realtime.map { stationRealtime -> StationRealtime in
                    let stationParentAlerts = activeAlerts.filter { alert in
                        let parentIDs = stationRepository.parentStationIDs(for: alert.stops)
                        return parentIDs.contains(stationRealtime.station.id)
                    }
                    relevantAlertSet.formUnion(stationParentAlerts)

                    let lineArrivals = stationRealtime.lineArrivals.map { arrival -> LineArrival in
                        let lineAlerts = activeAlerts.filter { $0.lines.contains(arrival.line.uppercased()) }
                        let combined = Array(Set(lineAlerts + stationParentAlerts)).sorted { $0.title < $1.title }
                        relevantAlertSet.formUnion(lineAlerts)
                        return LineArrival(line: arrival.line, arrivals: arrival.arrivals, alerts: combined)
                    }

                    return StationRealtime(
                        station: stationRealtime.station,
                        distance: stationRealtime.distance,
                        lineArrivals: lineArrivals
                    )
                }

                let mergedStations = Self.mergeStations(decorated)

                self.stations = mergedStations.sorted { $0.distance < $1.distance }
                let now = Date()
                self.lastUpdated = now
                self.updateRelativeTimestamp()
                self.startRelativeTimer()
                self.startAutoRefresh()
                self.activeAlerts = Array(relevantAlertSet).sorted { $0.title < $1.title }
                self.phase = mergedStations.isEmpty ? .error("No arrivals found within a mile. Try refreshing.") : .ready
            } catch {
                if Task.isCancelled { return }
                self.phase = .error(error.localizedDescription)
            }
        }
    }
}

private extension SubwayDashboardViewModel {
    func updateRelativeTimestamp() {
        guard let lastUpdated else {
            lastUpdatedRelative = ""
            return
        }
        let delta = Date().timeIntervalSince(lastUpdated)

        switch delta {
        case ..<30:
            lastUpdatedRelative = "just now"
        case ..<90:
            lastUpdatedRelative = "1 min ago"
        case ..<3600:
            let minutes = Int(delta / 60)
            lastUpdatedRelative = "\(minutes) min ago"
        case ..<86400:
            let hours = Int(delta / 3600)
            lastUpdatedRelative = hours == 1 ? "1 hr ago" : "\(hours) hrs ago"
        default:
            let days = Int(delta / 86400)
            lastUpdatedRelative = days == 1 ? "1 day ago" : "\(days) days ago"
        }
    }

    func startRelativeTimer() {
        relativeUpdateTask?.cancel()
        guard lastUpdated != nil else { return }

        relativeUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { break }
                await self.updateRelativeTimestamp()
            }
        }
    }

    func startAutoRefresh() {
        autoRefreshTask?.cancel()

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { break }
                await self.refresh(silently: true)
            }
        }
    }

    struct LineAggregate {
        var arrivals: Set<Date> = []
        var alerts: Set<ServiceAlert> = []
    }

    static func mergeStations(_ stations: [StationRealtime]) -> [StationRealtime] {
        let grouped = Dictionary(grouping: stations) { $0.station.name }

        return grouped.values.compactMap { group in
            guard let nearest = group.min(by: { $0.distance < $1.distance }) else { return nil }

            var allLines: Set<String> = []
            var aggregates: [String: LineAggregate] = [:]

            for entry in group {
                allLines.formUnion(entry.station.lines)

                for arrival in entry.lineArrivals {
                    var aggregate = aggregates[arrival.line] ?? LineAggregate()
                    aggregate.arrivals.formUnion(arrival.arrivals)
                    aggregate.alerts.formUnion(arrival.alerts)
                    aggregates[arrival.line] = aggregate
                }
            }

            for line in allLines where aggregates[line] == nil {
                aggregates[line] = LineAggregate()
            }

            let combinedArrivals: [LineArrival] = aggregates.map { line, aggregate in
                let sortedArrivals = Array(aggregate.arrivals).sorted()
                let limitedArrivals = Array(sortedArrivals.prefix(3))
                let alerts = Array(aggregate.alerts).sorted { $0.title < $1.title }
                return LineArrival(line: line, arrivals: limitedArrivals, alerts: alerts)
            }
            .sorted { lhs, rhs in
                lhs.line.localizedCaseInsensitiveCompare(rhs.line) == .orderedAscending
            }

            let combinedStation = Station(
                id: nearest.station.id,
                name: nearest.station.name,
                latitude: nearest.station.latitude,
                longitude: nearest.station.longitude,
                lines: Array(allLines).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            )

            return StationRealtime(
                station: combinedStation,
                distance: nearest.distance,
                lineArrivals: combinedArrivals
            )
        }
    }
}
