# Web Client (Planned)

This directory will host the web version of Drive-Ride-AI. The iOS app is the current
primary focus; this is a placeholder to be filled in later.

## Direction

- Reuse the same travel-planning logic as the iOS app (ideally extracted into a backend
  service / shared API).
- The frontend can use React / Next.js to deliver the same ChatBot interaction and plan cards.

> Tip: Keep the same data model as the `ios/` app (trip request → travel modes → multiple
> plans) so logic can be shared across frontend and backend.
