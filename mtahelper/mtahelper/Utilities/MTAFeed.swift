//
//  MTAFeed.swift
//  mtahelper
//
//  Created by Codex on 10/15/24.
//

import Foundation

enum MTAFeed: String, CaseIterable {
    case ace
    case bdfm
    case g
    case jz
    case nqrw
    case l
    case numbered
    case sir

    var url: URL {
        switch self {
        case .ace:
            return URL(string: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-ace")!
        case .bdfm:
            return URL(string: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-bdfm")!
        case .g:
            return URL(string: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-g")!
        case .jz:
            return URL(string: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-jz")!
        case .nqrw:
            return URL(string: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw")!
        case .l:
            return URL(string: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-l")!
        case .numbered:
            return URL(string: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs")!
        case .sir:
            return URL(string: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-si")!
        }
    }

    static func feeds(for line: String) -> Set<MTAFeed> {
        switch line.uppercased() {
        case "A", "C", "E", "H", "SR":
            return [.ace]
        case "B", "D", "F", "FX", "M", "SF":
            return [.bdfm]
        case "G":
            return [.g]
        case "J", "Z":
            return [.jz]
        case "N", "Q", "R", "W":
            return [.nqrw]
        case "L":
            return [.l]
        case "1", "2", "3", "4", "5", "6", "6X", "7", "7X":
            return [.numbered]
        case "S":
            return [.numbered, .bdfm]
        case "SIR":
            return [.sir]
        default:
            return []
        }
    }
}
