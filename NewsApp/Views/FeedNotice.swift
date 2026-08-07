import SwiftUI

/// Something worth telling Shane about the state of the feed.
///
/// There are two ways the morning news fails to arrive, and only one of them
/// used to be visible. A fetch that errors is obvious. A fetch that *succeeds*
/// and returns yesterday's edition looks perfectly healthy — the app shows a
/// full feed of real stories and says nothing. That is exactly what happened on
/// 3 August: the generator refused to publish a batch, the previous day's file
/// stayed live, and the staleness went unnoticed for days.
enum FeedNotice: Equatable {
    /// The feed couldn't be reached or decoded.
    case unreachable(String)
    /// The feed loaded fine, but it isn't today's.
    case stale(editionDate: Date, now: Date)

    /// How old an edition has to be before it counts as a missed day.
    ///
    /// The generator runs each morning, so a feed is normally a few hours old
    /// and briefly approaches 24 hours just before the next run. 26 hours clears
    /// that daily peak without masking a genuinely missed edition for long.
    static let staleAfter: TimeInterval = 26 * 60 * 60

    /// Builds a staleness notice if the edition is old enough to warrant one.
    static func staleness(of editionDate: Date?, now: Date = .now) -> FeedNotice? {
        guard let editionDate else { return nil }
        guard now.timeIntervalSince(editionDate) > staleAfter else { return nil }
        return .stale(editionDate: editionDate, now: now)
    }

    var symbol: String {
        switch self {
        case .unreachable: "wifi.exclamationmark"
        case .stale: "clock.badge.exclamationmark"
        }
    }

    var message: String {
        switch self {
        case .unreachable(let detail):
            detail
        case .stale(let editionDate, let now):
            "No new edition today — showing \(Self.ageDescription(of: editionDate, now: now))"
        }
    }

    /// "yesterday's news", "news from 3 days ago" — phrased for the banner.
    private static func ageDescription(of editionDate: Date, now: Date) -> String {
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: editionDate),
            to: Calendar.current.startOfDay(for: now)
        ).day ?? 0

        switch days {
        case ..<1: return "an earlier edition"
        case 1: return "yesterday's news"
        default: return "news from \(days) days ago"
        }
    }
}

/// The banner itself — a glass capsule floating over the top of the card.
struct FeedNoticeBanner: View {
    let notice: FeedNotice

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: notice.symbol)
                .font(.system(size: 12, weight: .semibold))
            Text(notice.message)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassCapsule()
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        .padding(.horizontal, 20)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}
