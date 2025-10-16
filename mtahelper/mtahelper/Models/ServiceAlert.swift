//
//  ServiceAlert.swift
//  mtahelper
//
//  Created by Codex on 10/15/24.
//

import Foundation

struct ServiceAlert: Identifiable, Hashable, Codable {
    struct ActivePeriod: Hashable, Codable {
        let start: Date
        let end: Date?

        var isCurrentlyActive: Bool {
            let now = Date()
            if let end {
                return now >= start && now <= end
            }
            return now >= start
        }
    }

    let id: String
    let title: String
    let description: String?
    let lines: Set<String>
    let stops: Set<String>
    let alertType: String?
    let activePeriods: [ActivePeriod]

    var isActiveNow: Bool {
        activePeriods.contains(where: { $0.isCurrentlyActive })
    }
}
