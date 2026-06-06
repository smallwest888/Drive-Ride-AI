# Drive-Ride-AI · AI Travel Assistant

An AI-powered travel assistant. Users describe their trip in natural language, and the
assistant analyzes the origin and destination, compares the **cost** and **time** of
multiple travel modes (flight, high-speed rail, driving, coach, etc.), and offers
several alternative plans.

## Project Structure

```
Drive-Ride-AI/
├── ios/    # iOS App (SwiftUI, targets the latest iOS, ChatBot-style UI) — primary focus
└── web/    # Web client (planned, placeholder)
```

## Platforms

- **iOS App**: A SwiftUI chatbot-style app. Describe your needs and get a comparison of
  travel plans. See [`ios/README.md`](ios/README.md).
- **Web**: Planned for later; currently a placeholder directory. See [`web/README.md`](web/README.md).

## Core Capabilities

1. Natural-language understanding of travel needs (origin, destination, budget, departure time, preferences).
2. Multi-mode modeling: compares cost, duration, comfort, and carbon emissions.
3. Generates multiple plans (e.g. "Cheapest", "Fastest", "Most comfortable") shown as cards.
4. The planning engine runs offline (built-in heuristic estimation) and can optionally be
   augmented with a large language model / real-time fare APIs.
