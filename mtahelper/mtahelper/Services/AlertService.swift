//
//  AlertService.swift
//  mtahelper
//
//  Created by Codex on 10/15/24.
//

import Foundation

enum AlertServiceError: LocalizedError {
    case invalidResponse
    case networkFailure(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Service alerts are temporarily unavailable."
        case .networkFailure(let statusCode):
            return "Service alerts request failed with status \(statusCode)."
        }
    }
}

final class AlertService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchAlerts() async throws -> [ServiceAlert] {
        var request = URLRequest(url: URL(string: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/camsys%2Fsubway-alerts.json")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AlertServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AlertServiceError.networkFailure(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let payload = try decoder.decode(AlertFeed.self, from: data)
        return payload.entity.compactMap { $0.toServiceAlert() }
    }
}

private struct AlertFeed: Decodable {
    let entity: [AlertEntity]
}

private struct AlertEntity: Decodable {
    let id: String
    let alert: AlertDetail

    func toServiceAlert() -> ServiceAlert? {
        let routes = Set(alert.informedEntity.compactMap { $0.routeID?.uppercased() })
        let stops = Set(alert.informedEntity.compactMap { $0.stopID })

        let periods = alert.activePeriod.map { period in
            ServiceAlert.ActivePeriod(start: period.start, end: period.end)
        }

        let title = alert.headerText?.stringValue ?? "Service Alert"
        let description = alert.descriptionText?.stringValue
        let alertType = alert.mercuryAlert?.alertType

        return ServiceAlert(
            id: id,
            title: title,
            description: description,
            lines: routes,
            stops: stops,
            alertType: alertType,
            activePeriods: periods
        )
    }
}

private struct AlertDetail: Decodable {
    let activePeriod: [AlertPeriod]
    let informedEntity: [InformedEntity]
    let headerText: TranslationContainer?
    let descriptionText: TranslationContainer?
    let mercuryAlert: MercuryAlert?

    private enum CodingKeys: String, CodingKey {
        case activePeriod
        case informedEntity
        case headerText
        case descriptionText
        case mercuryAlert = "transit_realtime.mercury_alert"
    }
}

private struct AlertPeriod: Decodable {
    let start: Date
    let end: Date?
}

private struct InformedEntity: Decodable {
    let routeID: String?
    let stopID: String?

    private enum CodingKeys: String, CodingKey {
        case routeID = "route_id"
        case stopID = "stop_id"
    }
}

private struct TranslationContainer: Decodable {
    let translation: [TranslationEntry]

    var stringValue: String? {
        translation.first(where: { $0.language == "en" })?.text ?? translation.first?.text
    }
}

private struct TranslationEntry: Decodable {
    let text: String
    let language: String?
}

private struct MercuryAlert: Decodable {
    let alertType: String?

    private enum CodingKeys: String, CodingKey {
        case alertType = "alert_type"
    }
}
