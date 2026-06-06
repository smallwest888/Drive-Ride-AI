import { Type } from "@sinclair/typebox";
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";

const toolParameters = Type.Object({
  message: Type.String({ minLength: 1 }),
  language: Type.Optional(Type.Union([Type.Literal("zh"), Type.Literal("en")])),
  currentLocation: Type.Optional(
    Type.Object({
      label: Type.String(),
      latitude: Type.Number(),
      longitude: Type.Number()
    })
  )
});

export default definePluginEntry({
  id: "drive-ride-agent",
  name: "Drive Ride Agent",
  description: "Travel planning tools for Drive&Ride.",
  register(api) {
    api.registerTool({
      name: "drive_ride_plan_trip",
      label: "Drive Ride Plan Trip",
      description:
        "Compute a structured Drive&Ride trip plan using parking inventory, route analysis, costs, comfort, carbon, and bilingual output.",
      parameters: toolParameters,
      async execute(_callId, params) {
        const response = await fetch("http://127.0.0.1:3000/internal/plan-trip", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-drive-ride-internal": "true"
          },
          body: JSON.stringify(params as object)
        });

        if (!response.ok) {
          const text = await response.text();
          throw new Error(`drive_ride_plan_trip failed: ${response.status} ${text}`);
        }

        const result = await response.json();
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(result)
            }
          ],
          details: result
        };
      }
    });
  }
});
