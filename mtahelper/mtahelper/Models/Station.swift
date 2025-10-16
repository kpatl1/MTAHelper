//
//  Station.swift
//  mtahelper
//
//  Created by Codex on 10/15/24.
//

import CoreLocation

struct Station: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let lines: [String]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct StationDistance: Identifiable, Hashable {
    let station: Station
    let distance: CLLocationDistance

    var id: String { station.id }
}

struct LineArrival: Identifiable, Hashable {
    let line: String
    let arrivals: [Date]
    let alerts: [ServiceAlert]

    var id: String { line }
}

struct StationRealtime: Identifiable, Hashable {
    let station: Station
    let distance: CLLocationDistance
    let lineArrivals: [LineArrival]

    var id: String { station.id }
}
