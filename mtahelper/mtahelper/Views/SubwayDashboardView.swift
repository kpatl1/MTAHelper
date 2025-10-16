//
//  SubwayDashboardView.swift
//  mtahelper
//
//  Created by Codex on 10/15/24.
//

import CoreLocation
import SwiftUI

struct SubwayDashboardView: View {
    @StateObject private var viewModel = SubwayDashboardViewModel()
    @State private var isRefreshing = false

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    content
                }
                .padding(.horizontal)
                .padding(.top, 32)
                .padding(.bottom, 80)
            }
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 0) }
            .refreshable {
                await triggerRefresh()
            }
        }
        .task {
            await triggerRefreshIfNeeded()
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.6),
                Color.indigo.opacity(0.6),
                Color.black.opacity(0.85)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MTA Helper")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            switch viewModel.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                Text("Using your current location to surface the closest lines.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            case .denied:
                Text("Location access is off. Enable it in Settings to see nearby lines.")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
            case .restricted:
                Text("Location services are restricted on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
            default:
                Text("Requesting your location…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }

            if !viewModel.lastUpdatedRelative.isEmpty {
                Text("Updated \(viewModel.lastUpdatedRelative)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle, .loading:
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                Text("Fetching live arrivals…")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 120)

        case .ready:
            if viewModel.stations.isEmpty {
                emptyStateView(message: "We couldn't find upcoming trains within a mile. Try refreshing.")
            } else {
                VStack(spacing: 24) {
                    ForEach(viewModel.stations) { station in
                        StationCardView(stationRealtime: station)
                    }

                    if !viewModel.activeAlerts.isEmpty {
                        ServiceAlertsSummaryView(alerts: viewModel.activeAlerts)
                    }
                }
            }

        case .error(let message):
            emptyStateView(message: message)
        }
    }

    private func emptyStateView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "tram.fill.tunnel")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
            Button {
                Task {
                    await triggerRefresh()
                }
            } label: {
                Text("Try Again")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.2), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private func triggerRefreshIfNeeded() async {
        guard viewModel.phase == .idle else { return }
        await triggerRefresh()
    }

    private func triggerRefresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        viewModel.refresh()
        try? await Task.sleep(for: .seconds(1)) // allow animation
        isRefreshing = false
    }
}

private struct StationCardView: View {
    let stationRealtime: StationRealtime

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            ForEach(stationRealtime.lineArrivals.filter { !$0.arrivals.isEmpty }) { arrival in
                LineArrivalRow(arrival: arrival)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(stationRealtime.station.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text(distanceString(distance: stationRealtime.distance))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            if let earliest = stationRealtime.lineArrivals.compactMap({ $0.arrivals.first }).min() {
                Text(upcomingString(for: earliest))
                    .font(.headline)
                    .foregroundStyle(.white)
            } else {
                Text("Live data unavailable")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

private struct LineArrivalRow: View {
    let arrival: LineArrival

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                LineBadge(line: arrival.line)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(arrival.destination)")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(departureTimesText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if !arrival.alerts.isEmpty {
                ForEach(Array(arrival.alerts.prefix(1))) { alert in
                    Label(alert.title, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.yellow)
                        .padding(.leading, 58)
                }
            }
        }
    }

    private var departureTimesText: String {
        guard !arrival.arrivals.isEmpty else {
            return "No upcoming departures"
        }
        return arrival.arrivals
            .map { upcomingString(for: $0) }
            .joined(separator: ", ")
    }
}

private struct LineBadge: View {
    let line: String

    var body: some View {
        Text(line)
            .font(.headline.weight(.bold))
            .frame(width: 42, height: 42)
            .background(LineAppearance.color(for: line))
            .foregroundStyle(LineAppearance.textColor(for: line))
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4)
    }
}

private struct ServiceAlertsSummaryView: View {
    let alerts: [ServiceAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Line Alerts")
                .font(.headline)
                .foregroundStyle(.white)

            ScrollView(.vertical, showsIndicators: alerts.count > 2) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(alerts) { alert in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .font(.headline)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alert.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                if let description = alert.description {
                                    Text(description)
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.75))
                                        .lineLimit(3)
                                }
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }
}

private func distanceString(distance: CLLocationDistance) -> String {
    if distance < 160 {
        return "Less than 500 ft away"
    } else if distance < 1000 {
        return "\(Int(distance)) meters away"
    } else {
        let measurement = Measurement(value: distance / 1609.34, unit: UnitLength.miles)
        return measurementFormatter.string(from: measurement) + " away"
    }
}

private func upcomingString(for date: Date) -> String {
    let now = Date()
    let interval = date.timeIntervalSince(now)

    if interval <= 30 {
        return "Now"
    }

    let minutes = Int(interval / 60)
    if minutes <= 1 {
        return "1 min"
    }
    return "\(minutes) min"
}

private let measurementFormatter: MeasurementFormatter = {
    let formatter = MeasurementFormatter()
    formatter.unitStyle = .short
    formatter.unitOptions = .naturalScale
    return formatter
}()

#Preview("Dashboard") {
    SubwayDashboardView()
        .preferredColorScheme(.dark)
}
