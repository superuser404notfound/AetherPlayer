import SwiftUI
import UniformTypeIdentifiers

/// The Library tab: the app's Documents folder, the same files the Files app shows under
/// "On My iPhone > AetherPlayer" and Finder shows in the device's Files pane.
struct LibraryView: View {
    let model: PlayerViewModel

    var body: some View {
        NavigationStack {
            LibraryFolderView(model: model, folder: LibraryFiles.root)
                .navigationDestination(for: URL.self) { folder in
                    LibraryFolderView(model: model, folder: folder)
                }
        }
    }
}

private struct LibraryFolderView: View {
    let model: PlayerViewModel
    let folder: URL

    @Environment(\.scenePhase) private var scenePhase
    @State private var entries: [LibraryFiles.Entry] = []
    @State private var showImporter = false
    @State private var importsRunning = 0
    @State private var showNewFolder = false
    @State private var nameText = ""
    @State private var renaming: LibraryFiles.Entry?
    @State private var moving: LibraryFiles.Entry?
    @State private var deleting: LibraryFiles.Entry?
    @State private var errorMessage: String?

    private var isRoot: Bool { folder == LibraryFiles.root }

    var body: some View {
        content
            .navigationTitle(isRoot ? Text("Library") : Text(verbatim: folder.lastPathComponent))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if importsRunning > 0 {
                        ProgressView()
                    } else {
                        Menu {
                            Button { showImporter = true } label: {
                                Label("Import Files", systemImage: "square.and.arrow.down")
                            }
                            Button {
                                nameText = ""
                                showNewFolder = true
                            } label: {
                                Label("New Folder", systemImage: "folder.badge.plus")
                            }
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                    }
                }
            }
            .onAppear(perform: reload)
            .refreshable { reload() }
            // Files arrive from outside while the app is in the background: the Files app, Finder,
            // a share sheet.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reload() }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item],
                          allowsMultipleSelection: true) { result in
                if case let .success(urls) = result { importFiles(urls) }
            }
            .alert("New Folder", isPresented: $showNewFolder) {
                TextField("Name", text: $nameText)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    perform { try LibraryFiles.createFolder(named: nameText, in: folder) }
                }
            }
            .alert("Rename", isPresented: isPresent($renaming), presenting: renaming) { entry in
                TextField("Name", text: $nameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    perform {
                        let renamed = try LibraryFiles.rename(entry.url, to: nameText)
                        model.recents.relocate(from: entry.url, to: renamed)
                    }
                }
            }
            .confirmationDialog(
                Text("Delete “\(deleting?.name ?? "")”?"),
                isPresented: isPresent($deleting), titleVisibility: .visible, presenting: deleting
            ) { entry in
                Button("Delete", role: .destructive) {
                    perform {
                        try FileManager.default.removeItem(at: entry.url)
                        model.recents.removeEntries(at: entry.url)
                    }
                }
            } message: { _ in
                Text("This removes it from this device.")
            }
            .sheet(item: $moving) { entry in
                LibraryMoveSheet(entry: entry) { destination in
                    perform {
                        let moved = try LibraryFiles.move(entry.url, into: destination)
                        model.recents.relocate(from: entry.url, to: moved)
                    }
                }
            }
            .alert("Library", isPresented: isPresent($errorMessage)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            ContentUnavailableView {
                Label("No files yet", systemImage: "tray")
            } description: {
                Text("Import files here, or copy them into AetherPlayer in the Files app or with Finder.")
            }
        } else {
            List(entries) { entry in
                row(entry)
                    .contextMenu { actions(for: entry) }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = entry }
                    }
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: LibraryFiles.Entry) -> some View {
        if entry.isFolder {
            NavigationLink(value: entry.url) {
                Label(entry.name, systemImage: "folder")
            }
        } else {
            Button { play(entry) } label: {
                HStack {
                    Label(entry.name, systemImage: symbol(for: entry))
                        .foregroundStyle(entry.isPlayable ? .primary : .secondary)
                    Spacer()
                    if let size = entry.size {
                        Text(size.formatted(.byteCount(style: .file)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.primary)
        }
    }

    @ViewBuilder
    private func actions(for entry: LibraryFiles.Entry) -> some View {
        if entry.isFolder {
            Button { Task { await model.openFolder(entry.url) } } label: {
                Label("Play All", systemImage: "play")
            }
        }
        Button {
            nameText = entry.name
            renaming = entry
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button { moving = entry } label: {
            Label("Move", systemImage: "folder")
        }
        Button(role: .destructive) { deleting = entry } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func symbol(for entry: LibraryFiles.Entry) -> String {
        let ext = entry.url.pathExtension.lowercased()
        if audioExtensions.contains(ext) { return "music.note" }
        if entry.isPlayable { return "film" }
        return "doc"
    }

    /// Plays the file with the rest of its folder queued behind it, the way a folder opened from the
    /// Open tab plays. A subtitle or other file that is not media is not opened.
    private func play(_ entry: LibraryFiles.Entry) {
        guard entry.isPlayable else { return }
        Task {
            await model.open(url: entry.url)
            if model.hasMedia {
                model.adoptFolderPlaylist(folderURL: folder, around: entry.url, bookmarkData: nil)
            }
        }
    }

    private func reload() {
        entries = LibraryFiles.entries(in: folder)
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
        reload()
    }

    /// Copies off the main thread: a film is gigabytes, and the copy takes seconds even on flash.
    private func importFiles(_ urls: [URL]) {
        importsRunning += 1
        let destination = folder
        Task {
            var failures: [String] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                do {
                    _ = try await Task.detached { try LibraryFiles.importCopy(of: url, into: destination) }.value
                } catch {
                    failures.append(error.localizedDescription)
                }
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            importsRunning -= 1
            reload()
            if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
        }
    }

    private func isPresent<T>(_ binding: Binding<T?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
    }
}

/// Picks the folder an entry moves into: the whole Library tree, minus the entry itself when it is a
/// folder, with the folder it already sits in shown but not selectable.
private struct LibraryMoveSheet: View {
    let entry: LibraryFiles.Entry
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let parent = entry.url.deletingLastPathComponent()
        NavigationStack {
            List(LibraryFiles.folderTree(excluding: entry.isFolder ? entry.url : nil)) { node in
                Button {
                    onPick(node.url)
                    dismiss()
                } label: {
                    Label {
                        if node.depth == 0 { Text("Library") } else { Text(verbatim: node.url.lastPathComponent) }
                    } icon: {
                        Image(systemName: "folder")
                    }
                    .padding(.leading, CGFloat(node.depth) * 16)
                }
                .disabled(LibraryFiles.canonicalPath(node.url) == LibraryFiles.canonicalPath(parent))
            }
            .navigationTitle("Move “\(entry.name)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
