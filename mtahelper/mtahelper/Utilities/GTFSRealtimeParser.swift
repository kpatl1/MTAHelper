//
//  GTFSRealtimeParser.swift
//  mtahelper
//
//  Created by Codex on 10/15/24.
//

import Foundation

struct GTFSRealtimeFeed {
    let tripUpdates: [GTFSRealtimeTripUpdate]
}

struct GTFSRealtimeTripUpdate {
    let tripID: String?
    let routeID: String?
    let stopTimeUpdates: [GTFSRealtimeStopTimeUpdate]
    let timestamp: Date?
}

struct GTFSRealtimeStopTimeUpdate {
    let stopID: String?
    let arrival: GTFSRealtimeEvent?
    let departure: GTFSRealtimeEvent?
}

struct GTFSRealtimeEvent {
    let time: Date?
    let delay: TimeInterval?
}

enum GTFSRealtimeParser {
    static func parse(data: Data) -> GTFSRealtimeFeed {
        var decoder = ProtoDecoder(data: data)
        var tripUpdates: [GTFSRealtimeTripUpdate] = []

        while let field = decoder.nextField() {
            switch field.number {
            case 2: // entity
                guard case .lengthDelimited(let payload) = field.value else { continue }
                if let update = parseFeedEntity(data: payload) {
                    tripUpdates.append(contentsOf: update)
                }
            default:
                break
            }
        }

        return GTFSRealtimeFeed(tripUpdates: tripUpdates)
    }

    private static func parseFeedEntity(data: Data) -> [GTFSRealtimeTripUpdate]? {
        var decoder = ProtoDecoder(data: data)
        var tripUpdates: [GTFSRealtimeTripUpdate] = []

        while let field = decoder.nextField() {
            switch field.number {
            case 3: // trip_update
                guard case .lengthDelimited(let payload) = field.value else { continue }
                if let tripUpdate = parseTripUpdate(data: payload) {
                    tripUpdates.append(tripUpdate)
                }
            default:
                continue
            }
        }

        return tripUpdates
    }

    private static func parseTripUpdate(data: Data) -> GTFSRealtimeTripUpdate? {
        var decoder = ProtoDecoder(data: data)
        var descriptor: TripDescriptor?
        var stopTimeUpdates: [GTFSRealtimeStopTimeUpdate] = []
        var timestamp: Date?

        while let field = decoder.nextField() {
            switch field.number {
            case 1:
                guard case .lengthDelimited(let payload) = field.value else { continue }
                descriptor = parseTripDescriptor(data: payload)
            case 2:
                guard case .lengthDelimited(let payload) = field.value else { continue }
                if let update = parseStopTimeUpdate(data: payload) {
                    stopTimeUpdates.append(update)
                }
            case 4:
                if let seconds = field.value.int64Value {
                    timestamp = Date(timeIntervalSince1970: TimeInterval(seconds))
                }
            default:
                continue
            }
        }

        if descriptor == nil && stopTimeUpdates.isEmpty {
            return nil
        }

        return GTFSRealtimeTripUpdate(
            tripID: descriptor?.tripID,
            routeID: descriptor?.routeID,
            stopTimeUpdates: stopTimeUpdates,
            timestamp: timestamp
        )
    }

    private static func parseTripDescriptor(data: Data) -> TripDescriptor {
        var decoder = ProtoDecoder(data: data)
        var tripID: String?
        var routeID: String?

        while let field = decoder.nextField() {
            switch field.number {
            case 1:
                if let string = field.value.stringValue {
                    tripID = string
                }
            case 5:
                if let string = field.value.stringValue {
                    routeID = string
                }
            default:
                continue
            }
        }

        return TripDescriptor(tripID: tripID, routeID: routeID)
    }

    private static func parseStopTimeUpdate(data: Data) -> GTFSRealtimeStopTimeUpdate? {
        var decoder = ProtoDecoder(data: data)
        var stopID: String?
        var arrival: GTFSRealtimeEvent?
        var departure: GTFSRealtimeEvent?

        while let field = decoder.nextField() {
            switch field.number {
            case 1:
                guard case .lengthDelimited(let payload) = field.value else { continue }
                arrival = parseEvent(data: payload)
            case 2:
                guard case .lengthDelimited(let payload) = field.value else { continue }
                departure = parseEvent(data: payload)
            case 3:
                // stop_sequence (ignored)
                continue
            case 4:
                if let string = field.value.stringValue {
                    stopID = string
                }
            default:
                continue
            }
        }

        if stopID == nil && arrival == nil && departure == nil {
            return nil
        }

        return GTFSRealtimeStopTimeUpdate(stopID: stopID, arrival: arrival, departure: departure)
    }

    private static func parseEvent(data: Data) -> GTFSRealtimeEvent {
        var decoder = ProtoDecoder(data: data)
        var time: Date?
        var delay: TimeInterval?

        while let field = decoder.nextField() {
            switch field.number {
            case 1:
                if let seconds = field.value.int64Value {
                    delay = TimeInterval(seconds)
                }
            case 2:
                if let seconds = field.value.int64Value {
                    time = Date(timeIntervalSince1970: TimeInterval(seconds))
                }
            default:
                continue
            }
        }

        return GTFSRealtimeEvent(time: time, delay: delay)
    }
}

private struct TripDescriptor {
    let tripID: String?
    let routeID: String?
}

private enum ProtoValue {
    case varint(UInt64)
    case fixed32(UInt32)
    case fixed64(UInt64)
    case lengthDelimited(Data)
}

private struct ProtoField {
    let number: Int
    let value: ProtoValue
}

private struct ProtoDecoder {
    private let data: Data
    private var index: Data.Index

    init(data: Data) {
        self.data = data
        self.index = data.startIndex
    }

    mutating func nextField() -> ProtoField? {
        while index < data.endIndex {
            guard let key = readVarint() else { return nil }
            let number = Int(key >> 3)
            let wireType = Int(key & 0x7)

            switch wireType {
            case 0:
                guard let value = readVarint() else { return nil }
                return ProtoField(number: number, value: .varint(value))
            case 1:
                guard let value = readFixed64() else { return nil }
                return ProtoField(number: number, value: .fixed64(value))
            case 2:
                guard let length = readLength() else { return nil }
                guard index + length <= data.endIndex else { return nil }
                let start = index
                index += length
                let subdata = data[start..<index]
                return ProtoField(number: number, value: .lengthDelimited(Data(subdata)))
            case 5:
                guard let value = readFixed32() else { return nil }
                return ProtoField(number: number, value: .fixed32(value))
            default:
                guard skip(wireType: wireType) else { return nil }
                continue
            }
        }

        return nil
    }

    private mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while index < data.endIndex && shift <= 63 {
            let byte = data[index]
            index = data.index(after: index)

            result |= UInt64(byte & 0x7F) << shift

            if (byte & 0x80) == 0 {
                return result
            }

            shift += 7
        }

        return nil
    }

    private mutating func readLength() -> Int? {
        guard let value = readVarint() else { return nil }
        return Int(value)
    }

    private mutating func readFixed32() -> UInt32? {
        guard index + 4 <= data.endIndex else { return nil }
        let sub = data[index..<index + 4]
        index += 4
        return sub.withUnsafeBytes { ptr in
            ptr.load(as: UInt32.self)
        }
    }

    private mutating func readFixed64() -> UInt64? {
        guard index + 8 <= data.endIndex else { return nil }
        let sub = data[index..<index + 8]
        index += 8
        return sub.withUnsafeBytes { ptr in
            ptr.load(as: UInt64.self)
        }
    }

    private mutating func skip(wireType: Int) -> Bool {
        switch wireType {
        case 0:
            return readVarint() != nil
        case 1:
            guard index + 8 <= data.endIndex else { return false }
            index += 8
            return true
        case 2:
            guard let length = readLength() else { return false }
            guard index + length <= data.endIndex else { return false }
            index += length
            return true
        case 3, 4:
            // Deprecated groups, skip gracefully by ignoring.
            return true
        case 5:
            guard index + 4 <= data.endIndex else { return false }
            index += 4
            return true
        default:
            return false
        }
    }
}

private extension ProtoValue {
    var int64Value: Int64? {
        switch self {
        case .varint(let value):
            return Int64(bitPattern: value)
        case .fixed32(let value):
            return Int64(Int32(bitPattern: value))
        case .fixed64(let value):
            return Int64(bitPattern: value)
        case .lengthDelimited:
            return nil
        }
    }

    var stringValue: String? {
        guard case .lengthDelimited(let data) = self else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
