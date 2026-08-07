import SwiftUI

/// The app's home: the masthead, and one button per day for the last five
/// editions. Tapping a day slides that day's stories in from the right.
///
/// This exists because the feed used to be one undifferentiated run of every
/// story the app held — five mornings of news with nothing to say where one
/// edition ended and the next began. Days are the unit the news actually
/// arrives in, so they are the unit you choose between.
struct DayPickerView: View {
    /// Shown inline here rather than floated over the feed. The day picker is
    /// where you find out the morning didn't arrive, and it's the screen with
    /// room to say so.
    let notice: FeedNotice?
    @Binding var showingSaved: Bool
    @Binding var showingSettings: Bool

    @Environment(ArticleStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                masthead
                    .padding(.bottom, 6)

                if let notice {
                    FeedNoticeBanner(notice: notice)
                        .padding(.bottom, 2)
                }

                ForEach(store.recentDays()) { day in
                    DayButton(day: day)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Palette.page)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Masthead

    /// A serif wordmark under the app's logo mark — the yellow "N" medallion
    /// on the rose gradient, matching the app icon.
    private var masthead: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Spacer()
                iconButton("slider.horizontal.3", label: "Sections and sources") {
                    showingSettings = true
                }
                iconButton("heart.text.square", label: "Saved stories") {
                    showingSaved = true
                }
            }

            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            // The wordmark stays serif whatever the reading font is set to: it's
            // the masthead, not something you read.
            Text("News To Me")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            HStack(spacing: 10) {
                rule
                Text(Self.todayLine.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(Palette.ink.opacity(0.45))
                    .fixedSize()
                rule
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var rule: some View {
        Rectangle()
            .fill(Palette.ink.opacity(0.22))
            .frame(height: 0.5)
    }

    private static var todayLine: String {
        Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func iconButton(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .glassButtonStyle()
        .accessibilityLabel(label)
    }
}

// MARK: - One day

/// A day's button: a collage of that day's photos, with the day's name over it.
///
/// The collage is desaturated in proportion to how much of the day you've read —
/// full colour for a day you haven't opened, greyscale once you've read it all,
/// and part-way between when you're part-way through. Colour is doing the work
/// of a progress bar without the furniture of one, which suits a screen that is
/// otherwise five photographs.
private struct DayButton: View {
    let day: EditionDay

    private static let height: CGFloat = 92
    private static let corner: CGFloat = 18

    /// Worked out once and passed around: whether this button has photographs
    /// behind it decides its scrim, its lettering and its shadow, and
    /// `collageArticles()` can come back empty even for a day that has stories.
    private var photos: [Article] { day.collageArticles() }

    var body: some View {
        let photos = self.photos

        return NavigationLink(value: Route.day(day.date)) {
            ZStack {
                background(photos)
                if !photos.isEmpty { scrim }
                labels(overPhotos: !photos.isEmpty)
            }
            .frame(height: Self.height)
            .clipShape(.rect(cornerRadius: Self.corner))
            .overlay {
                RoundedRectangle(cornerRadius: Self.corner)
                    .strokeBorder(Palette.ink.opacity(day.isEmpty ? 0.08 : 0.14), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        // Nothing to slide in — a day the generator missed has no stories, and a
        // button that pushes an empty screen is worse than one that says so.
        .disabled(day.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.weekday)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(day.isEmpty ? [] : .isButton)
    }

    @ViewBuilder
    private func background(_ photos: [Article]) -> some View {
        if photos.isEmpty {
            Palette.ink.opacity(0.05)
        } else {
            HStack(spacing: 1) {
                ForEach(photos) { article in
                    CachedImage(
                        url: article.imageURL(base: FeedEndpoint.base),
                        category: article.category,
                        // A tile is a quarter of the card's width. Decoding the
                        // full card-sized photo for each of five days would cost
                        // more than the rest of this screen put together.
                        maxPointSize: 200
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .saturation(1 - day.readFraction)
            // Worth animating: coming back from a story, the colour visibly
            // drains a little further out of the day you just read from.
            .animation(.easeInOut(duration: 0.45), value: day.readFraction)
        }
    }

    /// Dark on the left where the type sits, clearing to the right so the
    /// photographs are still photographs. Only drawn where there are photographs
    /// to darken — a day with none is a plain tile, and in light mode a black
    /// gradient across it would be the one dark slab on a paper page.
    private var scrim: some View {
        LinearGradient(
            colors: [.black.opacity(0.82), .black.opacity(0.28)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// White over a scrimmed photograph, ink over a bare tile.
    private func labels(overPhotos: Bool) -> some View {
        let letters: Color = overPhotos ? .white : Palette.ink

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(day.weekday)
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .foregroundStyle(letters.opacity(day.isEmpty ? 0.45 : 1))
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(letters.opacity(0.6))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            // The badge is the one thing here on glass rather than straight on
            // the photograph, and glass follows the mode — so it takes ink even
            // where the lettering beside it is white.
            if !day.isEmpty { readBadge(letters: Palette.ink) }
        }
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(overPhotos ? 0.5 : 0), radius: 6, y: 1)
    }

    private var subtitle: String {
        guard !day.isEmpty else { return "\(day.relativeName()) · no edition" }
        let count = day.articles.count
        return "\(day.relativeName()) · \(count) \(count == 1 ? "story" : "stories")"
    }

    /// The same fact the colour is carrying, said in words.
    ///
    /// Saturation alone would be the only signal, and a signal carried purely by
    /// colour is no signal at all to a colour-blind reader or to VoiceOver.
    private func readBadge(letters: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: badgeSymbol)
                .font(.system(size: 10, weight: .bold))
            Text(badgeText)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(letters.opacity(day.readFraction == 1 ? 0.6 : 0.95))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassCapsule()
        .fixedSize()
    }

    private var badgeSymbol: String {
        switch day.readCount {
        case 0: "circle"
        case day.articles.count: "checkmark"
        default: "circle.lefthalf.filled"
        }
    }

    private var badgeText: String {
        switch day.readCount {
        case 0: "\(day.articles.count) new"
        case day.articles.count: "Read"
        default: "\(day.readCount)/\(day.articles.count)"
        }
    }

    private var accessibilityValue: String {
        guard !day.isEmpty else { return "\(day.relativeName()), no edition published" }
        let count = day.articles.count
        let read: String = switch day.readCount {
        case 0: "none read"
        case count: "all read"
        default: "\(day.readCount) of \(count) read"
        }
        return "\(day.relativeName()), \(count) stories, \(read)"
    }
}
