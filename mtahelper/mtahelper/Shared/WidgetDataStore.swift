import Foundation

struct NearestStationSnapshot: Codable, Hashable {
    struct Line: Codable, Hashable {
        let id: String
        let arrivals: [Date]
    }

    let stationID: String
    let stationName: String
    let distance: Double?
    let lines: [Line]
    let lastUpdated: Date
}

enum WidgetDataStore {
    static let appGroupID = "group.kishan.mtahelper"

    private static let nearestStationKey = "NearestStationSnapshot"
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(_ snapshot: NearestStationSnapshot) {
        guard let defaults else { return }
        do {
            let data = try encoder.encode(snapshot)
            defaults.set(data, forKey: nearestStationKey)
        } catch {
#if DEBUG
            print("WidgetDataStore: failed to encode snapshot -", error)
#endif
        }
    }

    static func load() -> NearestStationSnapshot? {
        guard let defaults, let data = defaults.data(forKey: nearestStationKey) else {
            return nil
        }

        do {
            return try decoder.decode(NearestStationSnapshot.self, from: data)
        } catch {
#if DEBUG
            print("WidgetDataStore: failed to decode snapshot -", error)
#endif
            return nil
        }
    }

    static func clear() {
        defaults?.removeObject(forKey: nearestStationKey)
    }
}

extension NearestStationSnapshot {
    static let preview = NearestStationSnapshot(
        stationID: "635",
        stationName: "14 St - Union Sq",
        distance: 120,
        lines: [
            .init(id: "4", arrivals: [Date().addingTimeInterval(180), Date().addingTimeInterval(480)]),
            .init(id: "5", arrivals: [Date().addingTimeInterval(240)]),
            .init(id: "6", arrivals: [Date().addingTimeInterval(360)])
        ],
        lastUpdated: Date()
    )
}
