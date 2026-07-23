import SwiftUI
import AVKit
import PhotosUI

/// Entertainment sub-menu (reached from the launcher's "Entertainment" button). Collects the
/// non-scene activities: the Kindle reader (moved here from the launcher), music from the
/// Music app, and a video picked from the user's photo/media library.
struct EntertainmentMenuView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    @State private var pickedVideo: PhotosPickerItem?
    @State private var videoURL: URL?
    @State private var loadingVideo = false

    var body: some View {
        NavigationStack {
            List {
                Section("Read") {
                    Button {
                        openWindow(id: "reader")
                    } label: {
                        Label("Kindle", systemImage: "book")
                    }
                }

                Section("Listen") {
                    // Opens the Music app so the user can play their own library. Full in-app
                    // MusicKit playback would need the MusicKit capability + authorization;
                    // launching the app is the dependency-free option.
                    Button {
                        if let url = URL(string: "music://") { openURL(url) }
                    } label: {
                        Label("Music", systemImage: "music.note")
                    }
                }

                Section("Watch") {
                    // User-selected media needs no photo-library entitlement.
                    PhotosPicker(selection: $pickedVideo, matching: .videos) {
                        Label(loadingVideo ? "Loading…" : "Video from Library",
                              systemImage: "film")
                    }
                    if let videoURL {
                        VideoPlayer(player: AVPlayer(url: videoURL))
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .navigationTitle("Entertainment")
        }
        .frame(minWidth: 360, minHeight: 440)
        .onChange(of: pickedVideo) { _, item in
            guard let item else { return }
            loadingVideo = true
            Task {
                videoURL = try? await item.loadTransferable(type: PickedVideo.self)?.url
                loadingVideo = false
            }
        }
    }
}

/// Copies a picked video out of the Photos sandbox into a temp file AVPlayer can stream.
private struct PickedVideo: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let dst = URL.temporaryDirectory.appendingPathComponent(
                "float-video-" + received.file.lastPathComponent)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return Self(url: dst)
        }
    }
}
