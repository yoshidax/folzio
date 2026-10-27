import Foundation

/// Determines the locale used to format dates, counts, and percentages (FR-151, research.md R7).
/// Keeps the display language and region separate: ordering, separators, and 12/24-hour display follow the region,
/// while words follow the display language.
public enum FormattingLocale {
    /// Uses the region defaults for numeric symbols and percent placement rather than the display language.
    public static func numeric(current: Locale) -> Locale {
        guard let region = current.region?.identifier else { return current }
        let regionalLanguage = Locale.Language(identifier: "und_\(region)").maximalIdentifier
        guard let languageCode = Locale.Language(identifier: regionalLanguage).languageCode else { return current }
        var components = Locale.Components(locale: current)
        components.languageComponents.languageCode = languageCode
        if components.numberingSystem == nil {
            components.numberingSystem = current.numberingSystem
        }
        return Locale(components: components)
    }

    public static func resolve(current: Locale, displayLanguage: String) -> Locale {
        let currentLanguage = current.language.languageCode?.identifier
        if currentLanguage == displayLanguage {
            return current
        }

        var components = Locale.Components(locale: current)
        components.languageComponents.languageCode = Locale.LanguageCode(displayLanguage)
        components.hourCycle = current.hourCycle
        components.firstDayOfWeek = current.firstDayOfWeek
        if components.calendar == nil {
            components.calendar = current.calendar.identifier
        }
        if components.numberingSystem == nil {
            components.numberingSystem = current.numberingSystem
        }
        return Locale(components: components)
    }

    /// Grouping separators follow the region.
    public static func count(_ value: Int, locale: Locale) -> String {
        value.formatted(.number.locale(locale))
    }

    /// Percent sign placement and spacing follow the region.
    public static func percent(_ percentage: Int, locale: Locale) -> String {
        (Double(percentage) / 100).formatted(.percent.locale(locale))
    }
}
