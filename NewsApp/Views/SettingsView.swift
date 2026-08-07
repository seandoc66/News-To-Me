import SwiftUI

/// Two things, in the order you're likely to want them.
///
/// At the top, how the app looks: light or dark, the face the stories are set
/// in, and how big. Those are Shane's, saved on the phone, and take effect as
/// they're touched.
///
/// Below that, how the edition is put together — the target story count for each
/// section and the sources behind it. That half is deliberately read-only. The
/// generator that researches and writes the feed owns those rules; the app
/// reports them so they're visible on the phone without having to open the repo.
/// Changing them means editing the generator's brief.
struct SettingsView: View {
    @Environment(ArticleStore.self) private var store
    @Environment(ThemeSettings.self) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                AppearanceSection(theme: theme)

                if let config = store.feedConfig, !config.orderedSections.isEmpty {
                    sourceSections(config)
                } else {
                    unavailable
                }

                Section {
                    EmptyView()
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let generated = store.feedGeneratedAt {
                            Text("Sections and sources come from the edition published \(generated.formatted(date: .abbreviated, time: .shortened)). They're set by the daily news job, not in the app.")
                        }
                        Text(buildDescription)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.page)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .themedSheet()
    }

    @ViewBuilder
    private func sourceSections(_ config: FeedConfig) -> some View {
        ForEach(config.orderedSections) { section in
            Section {
                ForEach(section.config.sources) { source in
                    sourceRow(source)
                        .listRowBackground(Palette.ink.opacity(0.04))
                }
                if section.config.sources.isEmpty {
                    Text("No sources listed")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Palette.ink.opacity(0.04))
                }
            } header: {
                header(section.category, config: section.config)
            }
        }
    }

    /// Which copy of the app this is. The build number changes on every install
    /// (see `scripts/install-to-phone.sh`), so it tells two installs apart even
    /// though the version stays 1.0.
    private var buildDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "News \(version) (build \(build))"
    }

    private func header(_ category: NewsCategory, config: SectionConfig) -> some View {
        HStack(spacing: 8) {
            Label(category.displayName, systemImage: category.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(category.tint)
            Spacer()
            if let count = config.countDescription {
                Text(count)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
    }

    private func sourceRow(_ source: ConfiguredSource) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(source.name)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
            if let host = source.displayHost {
                Text(host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// One row rather than the whole screen: appearance is above it and stays
    /// usable whether or not this phone has ever fetched a feed that lists its
    /// sources.
    private var unavailable: some View {
        Section {
            Text("The edition on this phone doesn't list its sources or story counts. They'll appear once a feed carrying them has been fetched.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Palette.ink.opacity(0.04))
        } header: {
            Text("Sections")
                .textCase(nil)
        }
    }
}

// MARK: - Appearance

/// The three choices, each with a label over it, and a specimen underneath
/// showing what they add up to.
///
/// `@Bindable` rather than the environment object directly: a `Picker` needs a
/// binding into the settings, and this is where one is made.
private struct AppearanceSection: View {
    @Bindable var theme: ThemeSettings

    var body: some View {
        Section {
            control("Theme") {
                Picker("Theme", selection: $theme.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            control("Reading font") {
                Picker("Reading font", selection: $theme.readingFont) {
                    ForEach(ReadingFont.allCases) { face in
                        Text(face.displayName).tag(face)
                    }
                }
            }

            control("Text size") {
                Picker("Text size", selection: $theme.textSize) {
                    ForEach(TextSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
            }

            specimen
        } header: {
            Text("Appearance")
                .textCase(nil)
        } footer: {
            Text("Text size steps up or down from whatever you've set in iOS Settings, so it stacks with the phone's own size rather than replacing it.")
        }
        .listRowBackground(Palette.ink.opacity(0.04))
    }

    private func control(
        _ label: String,
        @ViewBuilder picker: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            picker()
                .pickerStyle(.segmented)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    /// A headline over a line of body text, in the chosen face and at the chosen
    /// size — the pair the settings above actually govern, so the effect of a
    /// change is visible without leaving the sheet.
    private var specimen: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("A headline, set the way you like it")
                .font(.system(.title3, design: theme.readingFont.design, weight: .bold))
                .foregroundStyle(Palette.ink)
            Text("And the story underneath it, in the same face, at the size you've picked.")
                .font(.system(.body, design: theme.readingFont.design))
                .lineSpacing(4)
                .foregroundStyle(Palette.ink.opacity(0.88))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 6)
    }
}
