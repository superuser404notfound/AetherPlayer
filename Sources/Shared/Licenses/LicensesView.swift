import SwiftUI

/// "Open Source Licenses" browser. On macOS its own window, component list on the left, notice +
/// license text on the right; on iOS a list pushed from the Settings tab, each component its own page.
struct LicensesView: View {
    #if os(macOS)
    @State private var selection: OpenSourceComponent.ID?
    #endif

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(OpenSourceLicenses.components, selection: $selection) { component in
                componentLabel(component)
                    .tag(component.id)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let component = OpenSourceLicenses.components.first(where: { $0.id == selection }) {
                LicenseDetail(component: component)
            } else {
                Text("AetherPlayer is open source under the LGPL-3.0. This app uses FFmpeg and the components in the list; select one to read its license.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding()
            }
        }
        .navigationTitle("Open Source Licenses")
        .frame(minWidth: 720, minHeight: 460)
        .onAppear {
            if selection == nil { selection = OpenSourceLicenses.components.first?.id }
        }
        #else
        List {
            Section {
                ForEach(OpenSourceLicenses.components) { component in
                    NavigationLink {
                        LicenseDetail(component: component)
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        componentLabel(component)
                    }
                }
            } footer: {
                Text("AetherPlayer is open source under the LGPL-3.0. This app uses FFmpeg and the components in the list; select one to read its license.")
            }
        }
        .navigationTitle("Open Source Licenses")
        #endif
    }

    private func componentLabel(_ component: OpenSourceComponent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: component.name)
                .font(.body)
            Text(verbatim: component.licenseName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LicenseDetail: View {
    let component: OpenSourceComponent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: component.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(verbatim: component.licenseName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let url = URL(string: component.url) {
                        Link(component.url, destination: url)
                            .font(.caption)
                    }
                }

                if let notice = component.notice {
                    Text(verbatim: notice)
                        .font(.callout)
                        .textSelection(.enabled)
                }

                if let text = OpenSourceLicenses.text(for: component) {
                    Text(verbatim: text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}
