import SwiftUI
import AppKit

/// One player window: its own view model and engine, so two windows play side by side without sharing
/// a clock, a track selection or a speed. Closing the window ends the session (AetherPlayer#11).
@Observable
@MainActor
final class PlayerSession {
    let model: PlayerViewModel
    @ObservationIgnored private(set) weak var window: NSWindow?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Files handed to this window that are still opening. `hasMedia` turns true only once a load
    /// lands, so without this a burst of Finder opens would read the same window as empty twice.
    @ObservationIgnored private var opening = 0
    var showOpenURLSheet = false
    var alwaysOnTop = false {
        didSet { window?.level = alwaysOnTop ? .floating : .normal }
    }

    init(model: PlayerViewModel) {
        self.model = model
    }

    /// Nothing playing and nothing on its way: a Finder open may take this window.
    var isEmpty: Bool { opening == 0 && !model.hasMedia }

    func open(_ url: URL) {
        opening += 1
        Task {
            await model.open(url: url)
            opening -= 1
        }
    }

    func open(_ request: XCallbackRequest) {
        opening += 1
        Task {
            await model.open(xCallback: request)
            opening -= 1
        }
    }

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        observers.forEach(NotificationCenter.default.removeObserver)
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.becameKey() }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            },
        ]
        // Only one window can hold the autosave name; the others cascade from it.
        window.setFrameAutosaveName("AetherPlayerMainWindow")
        window.level = alwaysOnTop ? .floating : .normal
        if window.isKeyWindow { becameKey() }
    }

    private func becameKey() {
        PlayerWindowRegistry.shared.activate(self)
        model.claimNowPlaying()
    }

    private func close() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        model.stop()
        PlayerWindowRegistry.shared.unregister(self)
    }
}

/// The open player windows and the one the menu bar and the Stats window act on: the player window
/// that was key last. Tracked by hand rather than through focused values so the
/// menus keep their target while the Stats or Settings window has focus.
@Observable
@MainActor
final class PlayerWindowRegistry {
    static let shared = PlayerWindowRegistry()

    private(set) var sessions: [PlayerSession] = []
    private(set) var active: PlayerSession?
    /// Set by the first player window; opens another one from places without a SwiftUI environment.
    @ObservationIgnored var openWindow: OpenWindowAction?
    /// Work for a window that has been asked for but not registered yet (Finder open with no window).
    @ObservationIgnored private var pending: [(PlayerSession) -> Void] = []

    func register(_ session: PlayerSession) {
        sessions.append(session)
        if active == nil { active = session }
        // One queued job per window: several Finder opens in a row each asked for a window of their own.
        if !pending.isEmpty { pending.removeFirst()(session) }
        FinderOpenEvents.shared.install()
    }

    func unregister(_ session: PlayerSession) {
        sessions.removeAll { $0 === session }
        if active === session { active = sessions.last }
    }

    func activate(_ session: PlayerSession) {
        guard sessions.contains(where: { $0 === session }) else { return }
        active = session
    }

    /// Runs `work` against the active window, or against a new one when every player window is closed.
    func withActiveSession(_ work: @escaping (PlayerSession) -> Void) {
        if let active {
            work(active)
            bringToFront(active)
        } else {
            pending.append(work)
            openPlayerWindow()
        }
    }

    /// A file opened from Finder (double click, Open With, a drop on the Dock icon). The front window
    /// takes it while it shows nothing; otherwise the file gets a window of its own, so opening several
    /// files one after another never replaces the one already playing.
    func openFromFinder(_ url: URL) {
        let target = active?.isEmpty == true ? active : sessions.first(where: \.isEmpty)
        if let target {
            target.open(url)
            bringToFront(target)
        } else {
            pending.append { [weak self] session in
                session.open(url)
                self?.bringToFront(session)
            }
            openPlayerWindow()
        }
    }

    /// Another app asked to play something (x-callback-url). Like a Finder open it never replaces what
    /// is already playing, and the window it lands in comes to the front.
    func openXCallback(_ request: XCallbackRequest) {
        let target = active?.isEmpty == true ? active : sessions.first(where: \.isEmpty)
        if let target {
            target.open(request)
            bringToFront(target)
        } else {
            pending.append { [weak self] session in
                session.open(request)
                self?.bringToFront(session)
            }
            openPlayerWindow()
        }
    }

    func openPlayerWindow() {
        openWindow?(id: PlayerWindowID.value)
        NSApp.activate(ignoringOtherApps: true)
    }

    func bringToFront(_ session: PlayerSession? = nil) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            (session ?? self.active)?.window?.makeKeyAndOrderFront(nil)
        }
    }
}

/// Takes Finder opens (double click, Open With, a drop on the Dock icon) off SwiftUI once the first
/// player window exists, because SwiftUI passes on only the first file of each open. Until then SwiftUI
/// keeps the event: it is what opens the launch window for a file that started the app.
@MainActor
final class FinderOpenEvents: NSObject {
    static let shared = FinderOpenEvents()
    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(openDocuments(_:withReply:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEOpenDocuments))
    }

    @objc private func openDocuments(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        Self.files(of: event).forEach(PlayerWindowRegistry.shared.openFromFinder)
    }

    /// The files of the launch event behind `url`, read from the event SwiftUI is handling, since it
    /// passes on only the first of them.
    func launchFiles(for url: URL) -> [URL] {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenDocuments) else { return [url] }
        let files = Self.files(of: event)
        return files.contains { $0.standardizedFileURL == url.standardizedFileURL } ? files : [url]
    }

    private static func files(of event: NSAppleEventDescriptor) -> [URL] {
        guard let list = event.paramDescriptor(forKeyword: keyDirectObject) else { return [] }
        guard list.numberOfItems > 0 else { return [list.fileURLValue].compactMap { $0 } }
        return (1...list.numberOfItems).compactMap { list.atIndex($0)?.fileURLValue }
    }
}

enum PlayerWindowID {
    static let value = "player"
}

/// Weak handle to the hosting window, so view state never keeps a closed window alive.
struct WindowRef: Equatable {
    weak var window: NSWindow?
    static func == (lhs: WindowRef, rhs: WindowRef) -> Bool { lhs.window === rhs.window }
}

extension EnvironmentValues {
    /// The player window a view lives in. Window actions (full screen, title, cursor) go to this one,
    /// not to `NSApp.keyWindow`, which is another window whenever a player in the background updates.
    @Entry var playerWindow: NSWindow? = nil
}

/// Reports the NSWindow hosting it.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> _View {
        let v = _View(); v.onWindow = onWindow; return v
    }
    func updateNSView(_ nsView: _View, context: Context) { nsView.onWindow = onWindow }

    final class _View: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}

/// Root of one player window. The session is built on appear rather than in an initializer, because
/// SwiftUI may construct this struct more than once, and each construction would start an engine.
struct PlayerWindowView: View {
    @State private var session: PlayerSession?
    @State private var engineFailed = false
    @State private var windowRef = WindowRef()
    /// Finder opens that started the app and reached this window before its session existed.
    @State private var launchURLs: [URL] = []
    /// x-callback-url requests that started the app, queued the same way.
    @State private var launchRequests: [XCallbackRequest] = []
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let session {
                ContentView(model: session.model) {
                    session.showOpenURLSheet = true
                }
                .sheet(isPresented: Bindable(session).showOpenURLSheet) {
                    OpenURLSheet(model: session.model)
                }
                .environment(\.playerWindow, windowRef.window)
            } else if engineFailed {
                Text("AetherEngine failed to initialize.")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else {
                Color.black
            }
        }
        .background(WindowAccessor { window in windowRef = WindowRef(window: window) })
        // Only the launch is still SwiftUI's (see FinderOpenEvents). Without this the WindowGroup
        // answers the file with an empty window beside the one that plays it.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL { url in
            switch XCallbackURL.parse(url) {
            case .play(let request):
                if session != nil { PlayerWindowRegistry.shared.openXCallback(request) } else { launchRequests.append(request) }
                return
            case let .rejected(targets, code, message):
                XCallbackURL.send(targets.errorURL(code: code, message: message))
                return
            case nil:
                break
            }
            let urls = FinderOpenEvents.shared.launchFiles(for: url)
            if session != nil {
                urls.forEach(PlayerWindowRegistry.shared.openFromFinder)
            } else {
                launchURLs += urls
            }
        }
        .onAppear {
            PlayerWindowRegistry.shared.openWindow = openWindow
            guard session == nil, !engineFailed else { return }
            do {
                let session = PlayerSession(model: try PlayerViewModel())
                self.session = session
                if let window = windowRef.window { session.attach(window) }
                PlayerWindowRegistry.shared.register(session)
                let urls = launchURLs
                launchURLs = []
                if let first = urls.first { session.open(first) }
                urls.dropFirst().forEach(PlayerWindowRegistry.shared.openFromFinder)
                let requests = launchRequests
                launchRequests = []
                var rest = requests[...]
                if urls.isEmpty, let first = rest.popFirst() { session.open(first) }
                rest.forEach(PlayerWindowRegistry.shared.openXCallback)
            } catch {
                engineFailed = true
            }
        }
        .onChange(of: windowRef) { _, ref in
            if let window = ref.window { session?.attach(window) }
        }
        .frame(minWidth: 640, minHeight: 360)
    }
}
