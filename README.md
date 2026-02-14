# MTA Helper

MTA Helper is a SwiftUI application that surfaces nearby New York City subway stations, real-time train arrivals, and active MTA service alerts. The app combines the rider's current location with GTFS real-time feeds published by the MTA to present a dashboard of the closest stations, per-line countdowns, and alerts that impact each stop.【F:mtahelper/mtahelper/Views/SubwayDashboardView.swift†L14-L93】【F:mtahelper/mtahelper/ViewModels/SubwayDashboardViewModel.swift†L26-L124】

## Features

- **Location-aware station discovery** – The app requests the rider's current location, handles the various Core Location authorization flows, and continuously updates as permission changes.【F:mtahelper/mtahelper/Services/LocationService.swift†L24-L102】 Nearby stations are identified with a configurable radius and fallbacks when no stops are in range.
- **Real-time arrivals** – The `RealtimeService` downloads the appropriate GTFS feeds for the lines that serve the nearby stations, parses the protobuf payload, and returns the next arrivals per line.【F:mtahelper/mtahelper/Services/RealtimeService.swift†L23-L104】【F:mtahelper/mtahelper/Utilities/GTFSRealtimeParser.swift†L9-L123】
- **Service alert integration** – Current subway alerts are fetched, decoded, and merged into the station and line presentation so riders can see relevant advisories alongside countdowns.【F:mtahelper/mtahelper/Services/AlertService.swift†L23-L83】【F:mtahelper/mtahelper/ViewModels/SubwayDashboardViewModel.swift†L70-L123】
- **Polished SwiftUI dashboard** – The main view renders station cards, line rows, refresh affordances, and empty states tailored to the data phase, with auto-refresh and relative timestamp updates managed by the view model.
## Project structure

```
MTAHelper/
└── mtahelper/
    ├── Models/           // Station and alert domain types
    ├── Resources/        // Bundled station metadata JSON files
    ├── Services/         // Networking, location, and repository layers
    ├── Utilities/        // GTFS protobuf decoder & appearance helpers
    ├── ViewModels/       // Presentation logic for the dashboard
    └── Views/            // SwiftUI screens and components
```

Key components include:

- `StationRepository` for loading bundled station metadata and resolving stop IDs to parent stations.【F:mtahelper/mtahelper/Services/StationRepository.swift†L30-L125】
- `RealtimeService` for selecting the required MTA GTFS feeds per line and gathering the next arrivals.【F:mtahelper/mtahelper/Services/RealtimeService.swift†L27-L104】
- `AlertService` for retrieving the subway alerts feed and normalizing it into `ServiceAlert` models.【F:mtahelper/mtahelper/Services/AlertService.swift†L23-L83】
- `SubwayDashboardViewModel` for orchestrating location lookup, data fetches, periodic refreshes, and error handling.【F:mtahelper/mtahelper/ViewModels/SubwayDashboardViewModel.swift†L26-L189】
- `SubwayDashboardView` for the SwiftUI presentation of cards, line rows, and alert summaries.【F:mtahelper/mtahelper/Views/SubwayDashboardView.swift†L14-L196】

## Data sources

The app relies on two categories of data:

1. **Bundled reference data** – Static JSON files (`subway_stations.json` and `stop_parent.json`) are packaged with the app to describe station metadata and stop-to-parent-station relationships.【F:mtahelper/mtahelper/Services/StationRepository.swift†L101-L123】
2. **Live MTA feeds** – Real-time subway arrivals are loaded from the MTA GTFS endpoints selected per line, and service alerts are fetched from the MTA alerts feed.【F:mtahelper/mtahelper/Utilities/MTAFeed.swift†L12-L45】【F:mtahelper/mtahelper/Services/AlertService.swift†L27-L43】

> **Note:** The MTA GTFS endpoints require a developer API key supplied via the `x-api-key` header. You can set this globally by configuring `URLSessionConfiguration.default.httpAdditionalHeaders` early in the app lifecycle or by injecting a custom `URLSession` into `RealtimeService` and `AlertService` that adds the header to each request.【F:mtahelper/mtahelper/Services/RealtimeService.swift†L66-L84】【F:mtahelper/mtahelper/Services/AlertService.swift†L27-L40】

## Getting started

1. **Prerequisites**
   - Xcode 15 or later with the latest iOS SDK.
   - An MTA developer API key (https://api.mta.info/).

2. **Configure API access**
   - Add the `x-api-key` header with your key before the first network request. One option is to customize `URLSessionConfiguration.default` in `mtahelperApp` or to provide your own `URLSession` instance when constructing the services.【F:mtahelper/mtahelper/Services/RealtimeService.swift†L66-L84】【F:mtahelper/mtahelper/Services/AlertService.swift†L27-L40】

3. **Run the app**
   - Open `mtahelper.xcodeproj` in Xcode.
   - Select the `mtahelper` target and configure your signing team if building for a device.
   - Build and run on an iOS simulator or a location-capable device. Grant “While Using” location access when prompted so nearby stations can be discovered.【F:mtahelper/mtahelper/Services/LocationService.swift†L27-L74】

## Development tips

- `SubwayDashboardViewModel` exposes a `maximumDistance` property that can be tweaked to expand or restrict the search radius during debugging.【F:mtahelper/mtahelper/ViewModels/SubwayDashboardViewModel.swift†L33-L45】
- The view model schedules an automatic refresh every 60 seconds. You can adjust this cadence inside `startAutoRefresh()` if you need more or less frequent updates.【F:mtahelper/mtahelper/ViewModels/SubwayDashboardViewModel.swift†L146-L173】
- The GTFS parser is self-contained in `GTFSRealtimeParser.swift` if you need to extend support for other feed entities or additional fields.【F:mtahelper/mtahelper/Utilities/GTFSRealtimeParser.swift†L9-L189】

## Privacy considerations

The app only requests precise location while in use to calculate nearby stations. If the user denies permission, an explanatory message is displayed and the dashboard remains accessible, though without localized arrivals.【F:mtahelper/mtahelper/Views/SubwayDashboardView.swift†L39-L76】【F:mtahelper/mtahelper/Services/LocationService.swift†L24-L102】
