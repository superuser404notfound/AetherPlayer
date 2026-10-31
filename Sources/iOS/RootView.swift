import SwiftUI

struct RootView: View {
    private enum Tab: String {
        case recents, library, open, settings
    }

    @Bindable var model: PlayerViewModel
    @SceneStorage("root.tab") private var tab = Tab.recents

    var body: some View {
        TabView(selection: $tab) {
            SwiftUI.Tab("Recents", systemImage: "clock", value: Tab.recents) {
                RecentsView(model: model).openingIndicator(model)
            }
            SwiftUI.Tab("Library", systemImage: "books.vertical", value: Tab.library) {
                LibraryView(model: model).openingIndicator(model)
            }
            SwiftUI.Tab("Open", systemImage: "plus.circle", value: Tab.open) {
                OpenView(model: model).openingIndicator(model)
            }
            SwiftUI.Tab("Settings", systemImage: "gearshape", value: Tab.settings) {
                SettingsView()
            }
        }
        .alert(
            "Playback Error",
            isPresented: Binding(
                get: { model.loadError != nil },
                set: { if !$0 { model.clearLoadError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.loadError ?? "")
        }
        .fullScreenCover(isPresented: Binding(
            get: { model.hasMedia },
            set: { if !$0 { model.stop() } })) {
            ZStack {
                PlayerPresenter(model: model).ignoresSafeArea()
                PlayerChrome(model: model)
            }
        }
    }
}

private extension View {
    /// Remote opens can take 10-20 s (tuner tune-in + stream probe); without feedback the app reads as
    /// hung. The player cover only opens once loaded. Per tab rather than over the TabView, where the
    /// capsule would sit on the tab bar.
    func openingIndicator(_ model: PlayerViewModel) -> some View {
        overlay(alignment: .bottom) {
            if model.state == .loading && !model.hasMedia {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Opening stream…")
                    Button("Cancel") { model.cancelLoading() }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.state == .loading)
    }
}
