import SwiftUI

/// Shows how the edition is put together: the target story count for each
/// section and the sources behind it.
///
/// Deliberately read-only. The generator that researches and writes the feed
/// owns these rules; the app reports them so they're visible on the phone
/// without having to open the repo. Changing them means editing the generator's
/// brief.
struct SettingsView: View {
    @Environment(ArticleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let config = store.feedConfig, !config.orderedSections.isEmpty {
                    list(config)
                } else {
                    unavailable
                }
            }
            .background(.black)
            .navigationTitle("Sections")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func list(_ config: FeedConfig) -> some View {
        List {
            ForEach(config.orderedSections) { section in
                Section {
                    ForEach(section.config.sources) { source in
                        sourceRow(source)
                            .listRowBackground(Color.white.opacity(0.04))
                    }
                    if section.config.sources.isEmpty {
                        Text("No sources listed")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.white.opacity(0.04))
                    }
                } header: {
                    header(section.category, config: section.config)
                }
            }

            Section {
                EmptyView()
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let generated = store.feedGeneratedAt {
                        Text("From the edition published \(generated.formatted(date: .abbreviated, time: .shortened)). These are set by the daily news job, not in the app.")
                    }
                    Text(buildDescription)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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
                .foregroundStyle(.white)
            if let host = source.displayHost {
                Text(host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("No section details yet")
                .font(.title3.weight(.semibold))
            Text("The edition on this phone doesn't list its sources or story counts. They'll appear once a feed carrying them has been fetched.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(buildDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxHeight: .infinity)
    }
}
