# Drive-Ride-AI · Drive&Ride AI Assistant

An AI-powered **Drive&Ride** commute assistant centered on **Park & Ride (P+R) + public
transit**. Users set up a travel profile (car model / energy, transit card), enter origin
and destination, and add free-form needs. An agent resolves the trip, infers urgency,
compares the **cost** and **time** of public transit / full driving / P+R hybrid, and
offers several plans — asking follow-up questions when information is missing.

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

1. **Travel profile**: car model / fuel type / consumption / energy price and transit card,
   used for accurate cost estimation (persisted on device).
2. **Agent flow**: resolve origin & destination → infer urgency from the description →
   decide mode (transit / car / P+R) → compute total cost & time → return several plans.
3. **Park & Ride first**: models driving to a city-edge P+R lot then taking transit, to
   avoid congestion and expensive downtown parking.
4. **Proactive follow-ups**: asks for missing origin/destination or distance via quick replies.
5. Plans tagged "Cheapest / Fastest / Greenest", each with a per-segment cost/time breakdown.
