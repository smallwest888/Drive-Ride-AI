# Drive-Ride-AI · iOS App

A SwiftUI **Drive&Ride** commute assistant focused on **Park & Ride (P+R) + public transit**.
Users set up their travel profile (car model / energy, transit card), enter an origin and
destination, and add free-form needs in a chat box. An agent then resolves the trip,
infers urgency, decides the best mode (transit / car / P+R hybrid), computes total cost and
time, and returns several plans — proactively asking follow-up questions when information
is missing.

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

1. **Resolve the itinerary** — read the origin/destination fields, otherwise extract them
   from the description.
2. **Determine distance** — explicit distance in the text (e.g. "约 15 公里") takes priority,
   otherwise estimate from built-in city data.
3. **Analyze urgency** — classify the description as relaxed / normal / urgent.
4. **Decide modes** — public transit always; full driving and P+R hybrid only when the
   profile has a car (P+R requires a minimum distance to be worthwhile).
5. **Compute cost & time** — per-segment breakdown using the user's car energy cost and
   transit-card discount.
6. **Return several plans** — tagged "Cheapest / Fastest / Greenest" and sorted by urgency
   and preference.
7. **Ask follow-ups** — when origin/destination or distance is missing, the assistant asks
   with quick-reply chips.

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
├── DriveRideAIApp.swift          # App entry (injects ProfileStore)
├── Models/
│   ├── CarProfile.swift          # Car model, fuel type, consumption, energy cost
│   ├── TransitCard.swift         # Transit card types and fare discounts
│   ├── UserProfile.swift         # Car + transit card + default preference (Codable)
│   ├── TripLocation.swift        # Origin / destination
│   ├── CommutePlan.swift         # CommuteMode (transit/car/P+R), segments, urgency
│   └── ChatMessage.swift         # Chat message (plans + quick replies)
├── Services/
│   ├── RouteData.swift           # Built-in city coordinates + distance estimation
│   ├── ParkRideData.swift        # Park & Ride lots
│   └── CommutePlanner.swift      # The agent: resolve / urgency / cost+time / follow-ups
├── Stores/
│   └── ProfileStore.swift        # Persists UserProfile (UserDefaults)
├── ViewModels/
│   └── PlannerViewModel.swift    # Home state: fields, chat, planning
└── Views/
    ├── HomeView.swift            # Brand header + location fields + chat & plans
    ├── LocationFieldView.swift   # Origin / destination input field
    ├── ProfileView.swift         # Travel profile settings
    ├── PlanCardView.swift        # Plan card with per-segment cost/time breakdown
    ├── MessageBubbleView.swift   # Chat bubbles + quick-reply chips
    ├── InputBarView.swift        # Bottom needs input bar
    └── TypingIndicatorView.swift
```

## Notes

- City distances, P+R lots, parking fees, fares and per-mode time are **engineering
  estimates** for comparison demos. Integrate real map / fare / POI APIs and replace the
  logic in `RouteData`, `ParkRideData`, and `CommutePlanner` for production accuracy.
- For arbitrary street addresses (no offline geocoder), the agent asks for an approximate
  distance — or you can type it in the description.
