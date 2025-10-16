//
//  StationRepository.swift
//  mtahelper
//
//  Created by Codex on 10/15/24.
//

import CoreLocation
import Foundation

enum StationRepositoryError: LocalizedError {
    case resourceMissing(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name):
            return "Missing bundled resource: \(name)"
        case .decodingError(let details):
            return "Failed to decode station data. \(details)"
        }
    }
}

final class StationRepository {
    static let shared = StationRepository()

    private(set) var stations: [Station] = []
    private var stationIndex: [String: Station] = [:]
    private var stopToStationIndex: [String: String] = [:]

    init(bundle: Bundle = .main) {
        do {
            try loadStations(from: bundle)
        } catch {
            assertionFailure("StationRepository failed to load bundled data: \(error.localizedDescription)")
        }
    }

    func nearestStations(
        to coordinate: CLLocationCoordinate2D,
        limit: Int = 5,
        maximumDistance: CLLocationDistance = 1200,
        allowFallback: Bool = true
    ) -> [StationDistance] {
        guard !stations.isEmpty else { return [] }

        let referenceLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var scored: [StationDistance] = stations.map { station in
            let location = CLLocation(latitude: station.latitude, longitude: station.longitude)
            let distance = referenceLocation.distance(from: location)
            return StationDistance(station: station, distance: distance)
        }

        scored.sort { $0.distance < $1.distance }

        var selected = Array(
            scored
                .prefix(limit * 2) // widen initial window before filtering by radius
                .filter { $0.distance <= maximumDistance }
                .prefix(limit)
        )

        if selected.isEmpty {
            guard allowFallback else { return [] }
            selected = Array(scored.prefix(limit))
        }

        let selectedNames = Set(selected.map { $0.station.name })
        var seenIDs = Set(selected.map { $0.station.id })
        let inclusionRadius = max(maximumDistance, 250)

        for station in stations where selectedNames.contains(station.name) {
            if seenIDs.contains(station.id) { continue }
            let location = CLLocation(latitude: station.latitude, longitude: station.longitude)
            let distance = referenceLocation.distance(from: location)
            guard distance <= inclusionRadius else { continue }
            selected.append(StationDistance(station: station, distance: distance))
            seenIDs.insert(station.id)
        }

        selected.sort { $0.distance < $1.distance }
        return selected
    }

    func station(for stationID: String) -> Station? {
        stationIndex[stationID]
    }

    func parentStationID(for stopID: String) -> String? {
        if let parent = stopToStationIndex[stopID] {
            return parent
        }

        var candidate = stopID
        while candidate.count > 1 {
            candidate.removeLast()
            if let parent = stopToStationIndex[candidate] {
                return parent
            }
        }

        return stopToStationIndex.first { key, _ in
            key.caseInsensitiveCompare(stopID) == .orderedSame
        }?.value
    }

    func parentStationIDs(for stopIDs: Set<String>) -> Set<String> {
        var result: Set<String> = []
        for stopID in stopIDs {
            if let parent = parentStationID(for: stopID) {
                result.insert(parent)
            }
        }
        return result
    }

    private func loadStations(from bundle: Bundle) throws {
        guard let stationURL = bundle.url(forResource: "subway_stations", withExtension: "json") else {
            throw StationRepositoryError.resourceMissing("subway_stations.json")
        }
        guard let stopMapURL = bundle.url(forResource: "stop_parent", withExtension: "json") else {
            throw StationRepositoryError.resourceMissing("stop_parent.json")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let stationData = try Data(contentsOf: stationURL)
        let stopsData = try Data(contentsOf: stopMapURL)

        self.stations = try decoder.decode([Station].self, from: stationData)
        self.stationIndex = Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0) })
        self.stopToStationIndex = try JSONDecoder().decode([String: String].self, from: stopsData)
    }
}
