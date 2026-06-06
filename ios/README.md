# Drive-Ride-AI · iOS App

A SwiftUI AI travel assistant with a ChatBot-style interface. Users describe their trip in
natural language; the app parses the origin/destination/preferences, compares the **cost**
and **time** of multiple travel modes, and returns several plan cards.

## Requirements

- Xcode 16 or later
- iOS 18.0+ (deployment target, adjustable in project settings)
- No third-party dependencies — pure SwiftUI / Foundation

## How to Run

1. Open `DriveRideAI/DriveRideAI.xcodeproj` in Xcode
2. Pick an iOS 18 simulator (e.g. iPhone 16)
3. Press `Cmd + R`

> The project uses Xcode 16's File System Synchronized Group format, so every `.swift`
> file under `DriveRideAI/` is automatically included in the build — no manual reference
> management needed.

## Try It

Type your request in the input field, or tap a suggestion chip, for example:

- "I want to go from Beijing to Shanghai, on a tight budget, leaving Friday"
- "Chengdu to Chongqing, two people, want to get there fast"
- "Hangzhou to Nanjing, the greenest option"

(The built-in city data and parser are tuned for major Chinese cities and Chinese input.)

## Architecture (MVVM)

```
DriveRideAI/
├── DriveRideAIApp.swift        # App entry point
├── Models/                     # Data models
│   ├── TravelMode.swift        # Travel modes + estimation params (speed / price / carbon…)
│   ├── TripRequest.swift       # Parsed trip request and preferences
│   ├── TravelPlan.swift        # A single plan (cost / time / comfort / carbon)
│   └── ChatMessage.swift       # Chat message (may carry plan cards)
├── Services/
│   ├── RouteData.swift         # Built-in city coordinates + distance estimation (Haversine)
│   ├── TripPlanning.swift      # Planning service protocol
│   ├── LocalTripPlanner.swift  # Offline heuristic engine + natural-language parsing
│   └── AITripPlanner.swift     # Optional LLM augmentation (OpenAI-compatible API)
├── ViewModels/
│   └── ChatViewModel.swift     # Chat state management
└── Views/
    ├── ChatView.swift          # Main screen
    ├── MessageBubbleView.swift # Chat bubbles
    ├── PlanCardView.swift      # Plan card
    ├── InputBarView.swift      # Bottom input bar
    └── TypingIndicatorView.swift
```

## Planning Engine

- **Offline by default**: `LocalTripPlanner` parses the request, estimates distance, and
  computes the cost and time for each travel mode locally. It tags plans as "Fastest /
  Cheapest / Most comfortable / Greenest" and sorts them by the user's preference. No
  network or API key required.
- **Optional LLM augmentation**: `AITripPlanner` uses an LLM to write a more natural
  recommendation on top of the structured plans. The structured data is always computed
  locally, so results stay reliable and never fabricated.

### Connecting an LLM (optional)

Set any of the following to enable it (falls back to the local narrative if unset):

- Environment variables: `OPENAI_API_KEY`, `OPENAI_BASE_URL` (defaults to OpenAI),
  `OPENAI_MODEL` (defaults to `gpt-4o-mini`)
- Or add the corresponding keys to the app's Info configuration

> Note: Never commit a real API key. `.gitignore` already excludes `Secrets.plist` and `.env`.

## Notes

- City distances and per-mode cost/time are **engineering estimates** used for comparison
  demos. After integrating real fare / map APIs, replace the estimation logic in
  `RouteData` and `LocalTripPlanner` for more accurate results.
