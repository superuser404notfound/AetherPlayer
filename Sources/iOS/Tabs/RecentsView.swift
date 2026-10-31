import SwiftUI

struct RecentsView: View {
    let model: PlayerViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                RecentsGrid(model: model)
            }
            .navigationTitle("Recents")
        }
    }
}
