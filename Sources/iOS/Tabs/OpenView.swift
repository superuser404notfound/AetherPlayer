import SwiftUI
import UniformTypeIdentifiers

struct OpenView: View {
    /// What the importer is currently asking for. Two `.fileImporter` modifiers on
    /// one view do not both work, the later one wins and the earlier never presents,
    /// so file and folder share a single importer and swap its content types.
    private enum ImportKind {
        case media, folder

        var contentTypes: [UTType] {
            switch self {
            case .media: [.movie, .video, .audio]
            case .folder: [.folder]
            }
        }
    }

    let model: PlayerViewModel
    @State private var importKind: ImportKind = .media
    @State private var showImporter = false
    @State private var showURLSheet = false

    var body: some View {
        NavigationStack {
            List {
                Button { present(.media) } label: {
                    Label("Open File", systemImage: "folder")
                }
                Button { present(.folder) } label: {
                    Label("Open Folder", systemImage: "folder.badge.plus")
                }
                Button { showURLSheet = true } label: {
                    Label("Open URL", systemImage: "link")
                }
            }
            .navigationTitle("Open")
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importKind.contentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch importKind {
            case .media: DocumentOpen.handlePicked(result, model: model)
            case .folder: DocumentOpen.openFolder(result, model: model)
            }
        }
        .sheet(isPresented: $showURLSheet) { OpenURLSheet(model: model) }
    }

    private func present(_ kind: ImportKind) {
        importKind = kind
        showImporter = true
    }
}
