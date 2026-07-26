import SwiftUI
import AVKit
import PhotosUI

/// Entertainment sub-menu (reached from the launcher's "Entertainment" button). Collects the
/// non-scene activities: the web browser (which is where the Kindle lives, and every streaming
/// service that has a website), Apple Music played in-process, and local video.
///
/// Labels here name the SOURCE rather than the activity, because on visionOS what a button can
/// actually reach varies a lot by source and a vague "Video" sets the wrong expectation. See
/// `WatchSection` for the specific case.
struct EntertainmentMenuView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationStack {
            List {
                Section("Read & Browse") {
                    Button {
                        openWindow(id: "browser")
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Web Browser")
                                Text("Kindle, streaming sites, anything else")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "globe")
                        }
                    }
                }

                Section("Listen") {
                    Button {
                        openWindow(id: "music")
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Apple Music")
                                Text("Your library, played here in the scene")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "music.note")
                        }
                    }
                }

                WatchSection(openWindow: openWindow)
            }
            .navigationTitle("Entertainment")
        }
        .frame(minWidth: 380, minHeight: 460)
    }
}

/// The "Watch" options, split by where the video actually comes from.
///
/// There is no public API for the Apple TV app's library. Purchases, rentals and TV+ titles are
/// FairPlay-protected and decrypt only inside the TV app itself; no third-party app can list
/// them, let alone play them. So this section offers the two routes that DO work — local video,
/// and tv.apple.com in the browser — and says which is which rather than offering a "TV
/// Library" button that could only ever fail.
private struct WatchSection: View {
    let openWindow: OpenWindowAction

    var body: some View {
        Section("Watch") {
            Button {
                openWindow(id: "video")
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Video from Photos")
                        Text("Anything in your own photo library")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "film")
                }
            }

            Button {
                openWindow(id: "browser")
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple TV & streaming on the web")
                        Text("Opens the browser — TV app titles aren't reachable from here")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "play.tv")
                }
            }
        }
    }
}

/// Local video playback in its own window, so it can be placed and sized independently of the
/// menu that launched it.
struct VideoPanelView: View {
    @State private var pickedVideo: PhotosPickerItem?
    @State private var player: AVPlayer?
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            if let player {
                VideoPlayer(player: player)
            } else {
                ContentUnavailableView {
                    Label("Nothing playing", systemImage: "film")
                } description: {
                    Text("Pick a video from your photo library.")
                }
            }

            // User-selected media needs no photo-library entitlement — PhotosPicker runs out
            // of process and hands back only what was chosen.
            // Title read out here, not inside the picker's label closure: that closure is
            // @Sendable, so touching main-actor state from it is a concurrency warning.
            let title = loading ? "Loading…" : "Choose Video"
            PhotosPicker(selection: $pickedVideo, matching: .videos) {
                Label(title, systemImage: "photo.on.rectangle")
            }
            .padding(16)
        }
        .onChange(of: pickedVideo) { _, item in
            guard let item else { return }
            loading = true
            Task {
                if let url = try? await item.loadTransferable(type: PickedVideo.self)?.url {
                    player = AVPlayer(url: url)
                    player?.play()
                }
                loading = false
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
