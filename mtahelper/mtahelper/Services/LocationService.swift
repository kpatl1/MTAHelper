//
//  LocationService.swift
//  mtahelper
//
//  Created by Codex on 10/15/24.
//

import CoreLocation
import Foundation
internal import Combine

enum LocationServiceError: LocalizedError {
    case permissionDenied
    case restricted
    case unableToDetermine

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location access is required to show nearby subway lines. Enable it in Settings."
        case .restricted:
            return "Location services are restricted on this device."
        case .unableToDetermine:
            return "We couldn't determine your location."
        }
    }
}

@MainActor
final class LocationService: NSObject, ObservableObject {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    func requestLocation() async throws -> CLLocation {
        let status = manager.authorizationStatus

        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted:
            throw LocationServiceError.restricted
        case .denied:
            throw LocationServiceError.permissionDenied
        default:
            break
        }

        if let location = manager.location {
            return location
        }

        manager.requestLocation()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            if self.continuation != nil {
                continuation.resume(throwing: LocationServiceError.unableToDetermine)
            } else {
                self.continuation = continuation
            }
        }
    }

    func startContinuousUpdates() {
        manager.startUpdatingLocation()
    }

    func stopContinuousUpdates() {
        manager.stopUpdatingLocation()
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied:
            continuation?.resume(throwing: LocationServiceError.permissionDenied)
            continuation = nil
        case .restricted:
            continuation?.resume(throwing: LocationServiceError.restricted)
            continuation = nil
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
