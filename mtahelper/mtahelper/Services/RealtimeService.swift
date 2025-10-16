//
//  RealtimeService.swift
//  mtahelper
//
//  Created by Codex on 10/15/24.
//

import Foundation

enum RealtimeServiceError: LocalizedError {
    case invalidResponse
    case networkFailure(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "We couldn't parse the subway feed. Please try again shortly."
        case .networkFailure(let statusCode):
            return "MTA feed responded with status \(statusCode)."
        }
    }
}

final class RealtimeService {
    private struct LineDestinationKey: Hashable {
        let line: String
        let destination: String
    }

    private let session: URLSession
    private let stationRepository: StationRepository

    init(session: URLSession = .shared, stationRepository: StationRepository = .shared) {
        self.session = session
        self.stationRepository = stationRepository
    }

    func fetchRealtime(for stationDistances: [StationDistance]) async throws -> [StationRealtime] {
        guard !stationDistances.isEmpty else { return [] }

        let targetStationIDs = Set(stationDistances.map { $0.station.id })
        let linesOfInterest = Set(stationDistances.flatMap { $0.station.lines.map { $0.uppercased() } })
        let feeds = Set(linesOfInterest.flatMap { MTAFeed.feeds(for: $0) })

        if feeds.isEmpty {
            return stationDistances.map {
                StationRealtime(station: $0.station, distance: $0.distance, lineArrivals: [])
            }
        }

        var predictions: [String: [LineDestinationKey: Set<Date>]] = [:]

        try await withThrowingTaskGroup(of: (MTAFeed, GTFSRealtimeFeed).self) { group in
            for feed in feeds {
                group.addTask { [session] in
                    let data = try await self.fetchFeed(feed, session: session)
                    let parsed = GTFSRealtimeParser.parse(data: data)
                    return (feed, parsed)
                }
            }

            for try await (_, feed) in group {
                for trip in feed.tripUpdates {
                    guard let routeID = trip.routeID?.uppercased(), linesOfInterest.contains(routeID) else {
                        continue
                    }

                    let orderedStops = sortStopUpdates(trip.stopTimeUpdates)
                    let tripDestination = resolveDestinationName(from: orderedStops)

                    for stopUpdate in orderedStops {
                        guard let stopID = stopUpdate.stopID,
                              let parentID = stationRepository.parentStationID(for: stopID),
                              targetStationIDs.contains(parentID) else {
                            continue
                        }

                        guard let date = stopUpdate.arrival?.time ?? stopUpdate.departure?.time else {
                            continue
                        }

                        let destination = tripDestination ?? fallbackDirectionDescription(for: stopID, line: routeID)
                        let key = LineDestinationKey(line: routeID, destination: destination)
                        predictions[parentID, default: [:]][key, default: []].insert(date)
                    }
                }
            }
        }

        let now = Date()

        return stationDistances.map { stationDistance in
            let station = stationDistance.station
            let rawArrivals = predictions[station.id] ?? [:]
            let threshold = now.addingTimeInterval(-30)

            let arrivals: [LineArrival] = rawArrivals.compactMap { entry -> LineArrival? in
                let key = entry.key
                let times = entry.value.filter { $0 >= threshold }
                guard !times.isEmpty else { return nil }
                let upcoming = Array(times.sorted().prefix(2))
                return LineArrival(line: key.line, destination: key.destination, arrivals: upcoming, alerts: [])
            }
            .sorted { lhs, rhs in
                let lineComparison = lhs.line.localizedCaseInsensitiveCompare(rhs.line)
                if lineComparison != .orderedSame {
                    return lineComparison == .orderedAscending
                }
                return lhs.destination.localizedCaseInsensitiveCompare(rhs.destination) == .orderedAscending
            }

            return StationRealtime(station: station, distance: stationDistance.distance, lineArrivals: arrivals)
        }
    }

    private func fetchFeed(_ feed: MTAFeed, session: URLSession) async throws -> Data {
        var request = URLRequest(url: feed.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RealtimeServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RealtimeServiceError.networkFailure(statusCode: httpResponse.statusCode)
        }

        return data
    }

    private func sortStopUpdates(_ updates: [GTFSRealtimeStopTimeUpdate]) -> [GTFSRealtimeStopTimeUpdate] {
        updates.enumerated().sorted { lhs, rhs in
            switch (lhs.element.stopSequence, rhs.element.stopSequence) {
            case let (l?, r?):
                if l == r {
                    return lhs.offset < rhs.offset
                }
                return l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.offset < rhs.offset
            }
        }
        .map(\.element)
    }

    private func resolveDestinationName(from updates: [GTFSRealtimeStopTimeUpdate]) -> String? {
        guard let stopID = updates.last(where: { $0.stopID != nil })?.stopID else {
            return nil
        }

        guard let parentID = stationRepository.parentStationID(for: stopID),
              let station = stationRepository.station(for: parentID) else {
            return nil
        }

        return station.name
    }

    private func fallbackDirectionDescription(for stopID: String, line: String) -> String {
        guard let suffix = stopID.last else {
            return "\(line) service"
        }

        switch suffix {
        case "N":
            return "Northbound"
        case "S":
            return "Southbound"
        case "E":
            return "Eastbound"
        case "W":
            return "Westbound"
        default:
            return "\(line) service"
        }
    }
}
