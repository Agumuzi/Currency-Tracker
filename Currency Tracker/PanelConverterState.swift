import Foundation

/// Keeps the amount being edited separate from values calculated for display.
struct PanelConverterState {
    private(set) var activeCode: String?
    private(set) var inputText = ""
    private(set) var displayTexts: [String: String] = [:]
    private(set) var hasInvalidInput = false
    private(set) var unreachableCodes: [String] = []

    mutating func select(
        _ code: String,
        currencyCodes: [String],
        graph: CurrencyConversionGraph,
        displayBaseAmount: Int,
        fractionDigits: Int
    ) {
        guard currencyCodes.contains(code) else { return }
        if activeCode != code {
            activeCode = code
            inputText = ""
        }
        recalculate(currencyCodes: currencyCodes, graph: graph, displayBaseAmount: displayBaseAmount, fractionDigits: fractionDigits)
    }

    mutating func edit(
        _ text: String,
        currencyCodes: [String],
        graph: CurrencyConversionGraph,
        displayBaseAmount: Int,
        fractionDigits: Int
    ) {
        inputText = text
        recalculate(currencyCodes: currencyCodes, graph: graph, displayBaseAmount: displayBaseAmount, fractionDigits: fractionDigits)
    }

    mutating func recalculate(
        currencyCodes: [String],
        graph: CurrencyConversionGraph,
        displayBaseAmount: Int,
        fractionDigits: Int
    ) {
        guard let activeCode, currencyCodes.contains(activeCode) else {
            if let first = currencyCodes.first {
                self.activeCode = first
                inputText = ""
                recalculate(currencyCodes: currencyCodes, graph: graph, displayBaseAmount: displayBaseAmount, fractionDigits: fractionDigits)
            } else {
                self.activeCode = nil
                inputText = ""
                displayTexts = [:]
                unreachableCodes = []
                hasInvalidInput = false
            }
            return
        }

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceText = trimmed.isEmpty
            ? String(CurrencyDisplayFormatting.normalizedDisplayBaseAmount(displayBaseAmount))
            : trimmed
        guard let decimal = AmountInputParsing.parseDecimal(sourceText) else {
            displayTexts = [:]
            unreachableCodes = []
            hasInvalidInput = true
            return
        }

        let amount = NSDecimalNumber(decimal: decimal).doubleValue
        guard amount.isFinite else {
            displayTexts = [:]
            unreachableCodes = []
            hasInvalidInput = true
            return
        }

        hasInvalidInput = false
        let multipliers = graph.conversionMultipliers(from: activeCode)
        var values = [activeCode: sourceText]
        var missing: [String] = []
        for code in currencyCodes where code != activeCode {
            if let multiplier = multipliers[code], (amount * multiplier).isFinite {
                values[code] = CurrencyDisplayFormatting.localizedNumber(amount * multiplier, fractionDigits: fractionDigits)
            } else {
                missing.append(code)
            }
        }
        displayTexts = values
        unreachableCodes = missing
    }
}
