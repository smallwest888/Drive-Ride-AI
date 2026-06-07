import Foundation

extension UserProfile {
    /// 给 Agent 使用的用户信息记忆。保持 Markdown，避免把偏好/车型/票种散落在 prompt 中。
    var markdownMemory: String {
        var lines: [String] = []
        lines.append("# User Mobility Memory")
        lines.append("")
        lines.append("## Vehicle")
        lines.append("- Has available car: \(hasCar ? "yes" : "no")")
        if hasCar {
            let carName = car.name.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("- Model: \(carName.isEmpty ? "not configured" : carName)")
            lines.append("- Fuel type: \(car.fuelType.displayName)")
            lines.append("- Consumption: \(car.consumptionText)")
            if let unitPrice = car.unitPrice, unitPrice > 0 {
                lines.append("- Energy unit price: \(String(format: "%.2f", unitPrice)) \(car.fuelType.priceUnit)")
            } else {
                lines.append("- Energy unit price: default for fuel type")
            }
            if let co2 = car.co2GramsPerKm, co2 > 0 {
                lines.append("- CO2: \(Int(co2.rounded())) g/km")
            } else {
                lines.append("- CO2: not entered; use local fallback")
            }
            if car.fuelType == .electric || car.fuelType == .hybrid {
                lines.append("- EV charging option: show Electroverse")
            }
        } else {
            lines.append("- Car plans: disabled")
            lines.append("- Rideshare fallback: show BlaBlaCar pooling")
        }
        lines.append("")
        lines.append("## Public Transit")
        lines.append("- German transit pass: \(transitCard.displayName)")
        lines.append("- Pass note: \(transitCard.subtitle)")
        lines.append("- Transit price fields: never ask user on input page")
        lines.append("- Public transit plan cards: do not show cost")
        lines.append("")
        lines.append("## Planning Preferences")
        lines.append("- Default preference: \(preference.displayName)")
        lines.append("- Parking fees: search online during planning unless local P+R database has a price")
        return lines.joined(separator: "\n")
    }
}
