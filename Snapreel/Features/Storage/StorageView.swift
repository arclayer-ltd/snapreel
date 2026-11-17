import SwiftUI

/// Session E owns this file. Settings > Storage: space used, largest videos, delete all data.
struct StorageView: View {
    @EnvironmentObject private var library: Library

    var body: some View {
        List {
            HStack {
                Text("Videos")
                Spacer()
                Text(Format.bytes(library.totalVideoBytes)).foregroundStyle(Color.srTextSecondary)
            }
        }
        .navigationTitle("Storage")
    }
}
