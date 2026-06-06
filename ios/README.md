# Drive-Ride-AI · iOS App

A SwiftUI **Drive&Ride** commute assistant focused on **Park & Ride (P+R) + public transit**,
powered by **MapKit** for real addresses and real routes.
Users set up their travel profile (car model / energy, transit card), search a **real origin
and destination** (address autocomplete, or one-tap current location), and add free-form
needs in a chat box. An agent then computes **live driving routes and transit ETAs**, finds a
**real Park & Ride lot**, infers urgency, computes total cost and time, and returns several
plans — each with **one-tap Apple Maps navigation** and an in-app route map preview.

## Requirements

- Xcode 16 or later
- iOS 18.0+ (deployment target, adjustable in project settings)
- No third-party dependencies — pure SwiftUI / Foundation

## How to Run

1. Open `DriveRideAI/DriveRideAI.xcodeproj` in Xcode
2. Pick an iOS 18 simulator (e.g. iPhone 16)
3. Press `Cmd + R`

> The project uses Xcode 16's File System Synchronized Group format, so every `.swift`
> file under `DriveRideAI/` is automatically included in the build.

## How It Works (Agent Flow)

1. **Resolve real places** — origin/destination come from MapKit address autocomplete
   (`MKLocalSearchCompleter` + `MKLocalSearch`) or the device's current location
   (`CLLocationManager` + reverse geocoding).
2. **Compute real routes** — `MKDirections.calculate` for the driving route (distance, live
   travel time, and route geometry) and `MKDirections.calculateETA` for transit ETA.
3. **Find a real P+R lot** — `MKLocalSearch` looks for a park-and-ride / parking lot near the
   destination side of the trip, then routes drive → lot and transit → destination.
4. **Analyze urgency** — classify the description as relaxed / normal / urgent.
5. **Compute cost & time** — based on the **real distances/times**, using the user's car
   energy cost and transit-card discount (fares/parking remain estimates).
6. **Return several plans** — tagged "Cheapest / Fastest / Greenest", each with an in-app
   route map and one-tap Apple Maps navigation per leg.

## Travel Profile (Settings)

Tap the gear in the top-right to configure:

- **Car**: whether you have a car, preset models or custom, fuel type (gasoline / diesel /
  electric / hybrid), consumption per 100 km, and energy unit price → drives fuel/electricity cost.
- **Transit card**: none / stored-value / discount / monthly pass → drives transit fare.
- **Default preference**: balanced / cheapest / fastest / greenest.

Profile is persisted via `UserDefaults`.

## Architecture (MVVM)

```
DriveRideAI/
├── DriveRideAIApp.swift          # App entry (injects ProfileStore + AppLocale)
├── Localization/
│   └── AppLocale.swift           # Language state + tr(zh, en) helper (in-app switching)
├── Models/
│   ├── CarProfile.swift          # Car model, fuel type, consumption, energy cost
│   ├── TransitCard.swift         # Transit card types and fare discounts
│   ├── UserProfile.swift         # Car + transit card + default preference (Codable)
│   ├── ResolvedPlace.swift       # A real place: name + coordinate + MKMapItem
│   ├── CommutePlan.swift         # CommuteMode (transit/car/P+R), segments, NavLeg
│   └── ChatMessage.swift         # Chat message (plans + quick replies)
├── Services/
│   ├── LocationSearchService.swift # MapKit address autocomplete + resolve to coordinate
│   ├── LocationManager.swift     # Current location + reverse geocoding
│   ├── RouteService.swift        # MKDirections routes/ETA + P+R lot search
│   └── CommutePlanner.swift      # The async agent: real routes / urgency / cost+time
├── Stores/
│   └── ProfileStore.swift        # Persists UserProfile (UserDefaults)
├── ViewModels/
│   └── PlannerViewModel.swift    # Home state: places, search, async planning
└── Views/
    ├── HomeView.swift            # Header + address search/locate + chat & plans
    ├── LocationFieldView.swift   # Address input field (autocomplete + locate button)
    ├── RoutePreviewView.swift    # Map preview of the real route + navigate buttons
    ├── ProfileView.swift         # Travel profile settings
    ├── PlanCardView.swift        # Plan card with breakdown + Route/Navigate actions
    ├── MessageBubbleView.swift   # Chat bubbles + quick-reply chips
    ├── InputBarView.swift        # Bottom needs input bar
    └── TypingIndicatorView.swift
```

## Localization (Multi-language UI)

- Supported: **Follow System / 简体中文 / English**. Switch in Settings (gear) → Language;
  the UI updates instantly.
- The whole UI is localized — brand header, fields, settings, plan cards, and the agent's
  generated narrative, follow-up questions, and quick replies.
- Implementation: a lightweight `AppLocale` (ObservableObject, persisted) plus a
  `tr(zh, en)` helper. Views subscribe via `@EnvironmentObject`; non-view code reads
  `AppLocale.shared`. Adding another language means extending `Lang` / `AppLanguage` and
  the `tr` helper.
- Urgency keywords cover both Chinese and English inputs.

## Notes

- **Addresses, distances, travel times, route geometry, and the P+R lot are real**, from
  Apple Maps (MapKit). Requires network; coverage of transit data depends on the region
  (when transit ETA is unavailable, the planner falls back to a distance-based estimate).
- **Fares and parking fees remain estimates** — MapKit does not expose fare/parking data.
  Costs are computed from the real distance using the user's car energy cost and
  transit-card discount.
- Location permission (`NSLocationWhenInUseUsageDescription`) is used only for the
  "current location" button; address search works without it.
