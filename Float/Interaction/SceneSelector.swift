import SwiftUI
import UIKit

/// Scene picker — the one selection surface now that every scene is a stereo sky. Grounded
/// skies (real horizon, vertigo mitigation) are grouped apart from deep space. Each entry
/// shows a thumbnail (Backdrop/Thumbnails/<name>.jpg). Its own window so it can float open
/// inside the immersive space.
struct SceneSelectorView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 16)]

    private func scenes(grounded: Bool) -> [(index: Int, scene: SpatialImageEnvironment.Scene)] {
        SpatialImageEnvironment.catalog.enumerated()
            .filter { $0.element.grounded == grounded }
            .filter { query.isEmpty || $0.element.title.localizedCaseInsensitiveContains(query) }
            .map { (index: $0.offset, scene: $0.element) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    section("Grounded", subtitle: "Real horizon — a fixed reference frame if floating brings on vertigo.",
                            items: scenes(grounded: true))
                    section("Deep Space", subtitle: nil, items: scenes(grounded: false))
                }
                .padding(20)
            }
            .navigationTitle("Scenes")
            .searchable(text: $query, prompt: "Find a scene")
        }
        .frame(minWidth: 460, minHeight: 520)
    }

    @ViewBuilder
    private func section(_ title: String, subtitle: String?,
                         items: [(index: Int, scene: SpatialImageEnvironment.Scene)]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items, id: \.scene.id) { item in
                    SceneTile(scene: item.scene,
                              isCurrent: model.currentScene == item.index) {
                        model.selectScene(item.index)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
        }
    }
}

/// A single thumbnail tile. Loads Backdrop/Thumbnails/<name>.jpg from the bundle; shows a
/// placeholder if it isn't there yet (e.g. before the batch conversion has produced it).
private struct SceneTile: View {
    let scene: SpatialImageEnvironment.Scene
    let isCurrent: Bool
    let action: () -> Void

    private var thumbnail: UIImage? {
        guard let url = Bundle.main.url(forResource: scene.name, withExtension: "jpg",
                                        subdirectory: "Thumbnails")
            ?? Bundle.main.url(forResource: scene.name, withExtension: "jpg")
        else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    if let img = thumbnail {
                        Image(uiImage: img).resizable().aspectRatio(2, contentMode: .fit)
                    } else {
                        Rectangle().fill(.quaternary).aspectRatio(2, contentMode: .fit)
                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint).padding(6)
                            .background(.thinMaterial, in: Circle()).padding(6)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 3))

                Text(scene.title).font(.callout).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}
