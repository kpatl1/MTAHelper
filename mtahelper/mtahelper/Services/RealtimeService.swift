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

        var predictions: [String: [String: Set<Date>]] = [:]

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

                    for stopUpdate in trip.stopTimeUpdates {
                        guard let stopID = stopUpdate.stopID,
                              let parentID = stationRepository.parentStationID(for: stopID),
                              targetStationIDs.contains(parentID) else {
                            continue
                        }

                        guard let date = stopUpdate.arrival?.time ?? stopUpdate.departure?.time else {
                            continue
                        }

                        predictions[parentID, default: [:]][routeID, default: []].insert(date)
                    }
                }
            }
        }

        let now = Date()

        return stationDistances.map { stationDistance in
            let station = stationDistance.station
            let rawArrivals = predictions[station.id] ?? [:]

            let arrivals: [LineArrival] = station.lines.map { line in
                let key = line.uppercased()
                let times = rawArrivals[key] ?? []
                let upcoming = Array(times.filter { $0 > now }).sorted().prefix(3)
                return LineArrival(line: line, arrivals: Array(upcoming), alerts: [])
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
}
