import Foundation

/// One day's edition, as the day picker sees it: the stories that arrived that
/// morning, and how much of them has been read.
///
/// A day always gets an entry even when nothing arrived — the picker offers a
/// fixed run of days, and a gap in the middle of that run is information.
struct EditionDay: Identifiable, Hashable {
    /// Midnight, local time. Doubles as the day's navigation identity.
    let date: Date
    /// That day's stories, in the order the feed reads them.
    let articles: [Article]

    var id: Date { date }

    var isEmpty: Bool { articles.isEmpty }

    var readCount: Int { articles.filter(\.isRead).count }

    /// 0 when nothing has been opened, 1 when everything has.
    ///
    /// This is what drains the colour out of the day's button: a day you
    /// haven't touched is in full colour, a day you've finished is greyscale,
    /// and part-read lands proportionally between the two.
    var readFraction: Double {
        guard !articles.isEmpty else { return 0 }
        return Double(readCount) / Double(articles.count)
    }

    /// "Wednesday". Every button is named for its weekday, today's included.
    var weekday: String { Self.weekdayFormatter.string(from: date) }

    /// "Today", "Yesterday", or "3 August" — what the weekday name alone can't
    /// tell you once you are several days back.
    func relativeName(now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents(
            [.day], from: date, to: calendar.startOfDay(for: now)
        ).day ?? 0
        switch days {
        case ...0: return "Today"
        case 1: return "Yesterday"
        default: return Self.dayMonthFormatter.string(from: date)
        }
    }

    /// The stories whose photos make up the button's background collage.
    ///
    /// Sampled evenly across the day rather than taken off the front: the store
    /// is ordered by section, so the first four photos of any edition are always
    /// the same section and the collage would never show more than one colour of
    /// story. Stories with no photo are skipped — the button would otherwise
    /// carry a flat category gradient where a picture should be.
    func collageArticles(limit: Int = 4) -> [Article] {
        let withPhotos = articles.filter { $0.imageURLString != nil }
        guard withPhotos.count > limit else { return withPhotos }
        return (0..<limit).map { withPhotos[$0 * withPhotos.count / limit] }
    }

    // MARK: - Formatters

    // Held as statics: building a DateFormatter is expensive and the picker
    // rebuilds every label whenever the store changes.

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return f
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMMM")
        return f
    }()
}
