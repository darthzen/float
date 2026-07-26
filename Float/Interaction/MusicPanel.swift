import SwiftUI
import MusicKit

/// In-app music: browse your library, search Apple Music, play without leaving the scene.
///
/// This replaces the old "open the Music app" button, which was the wrong shape for Float:
/// launching another app tears down the full immersive space (visionOS makes it exclusive),
/// so choosing a song meant leaving deep space and coming back. `ApplicationMusicPlayer` plays
/// inside *this* process, so the scene never goes away.
///
/// SETUP THIS CODE CANNOT DO FOR ITSELF: the App ID needs the **MusicKit** capability enabled
/// at developer.apple.com (Certificates, Identifiers & Profiles → the Ash4d.Float identifier →
/// App Services → MusicKit). Without it authorization is granted but every request comes back
/// empty or unauthorized. `NSAppleMusicUsageDescription` in Info.plist is the other half and
/// IS handled here.
@MainActor
@Observable
final class MusicModel {
    var status: MusicAuthorization.Status = MusicAuthorization.currentStatus
    var playlists: MusicItemCollection<Playlist> = []
    var albums: MusicItemCollection<Album> = []
    var searchResults: MusicItemCollection<Song> = []
    var loading = false
    var errorText: String?

    var nowPlayingTitle: String? { Player.currentTitle }
    var nowPlayingSubtitle: String? { Player.currentSubtitle }

    func requestAuthorization() async {
        status = await MusicAuthorization.request()
        if status == .authorized { await loadLibrary() }
    }

    /// Pull the user's own library — playlists and albums.
    ///
    /// Library requests, not catalog ones: this is "play my music", and it works for a
    /// downloaded/purchased library even without an active Apple Music subscription. Catalog
    /// search (below) is the part that needs the subscription.
    func loadLibrary() async {
        guard status == .authorized else { return }
        loading = true
        defer { loading = false }
        do {
            var playlistRequest = MusicLibraryRequest<Playlist>()
            playlistRequest.limit = 100
            playlists = try await playlistRequest.response().items

            var albumRequest = MusicLibraryRequest<Album>()
            albumRequest.limit = 100
            albumRequest.sort(by: \.libraryAddedDate, ascending: false)
            albums = try await albumRequest.response().items
        } catch {
            errorText = "Couldn't read your library: \(error.localizedDescription)"
        }
    }

    func search(_ term: String) async {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == .authorized, !q.isEmpty else { searchResults = []; return }
        loading = true
        defer { loading = false }
        do {
            var request = MusicCatalogSearchRequest(term: q, types: [Song.self])
            request.limit = 25
            searchResults = try await request.response().songs
        } catch {
            errorText = "Search failed: \(error.localizedDescription)"
        }
    }

    func play<T: PlayableMusicItem>(_ item: T) async {
        do { try await Player.play(item) }
        catch { errorText = "Couldn't play that: \(error.localizedDescription)" }
    }

    func togglePlayPause() async {
        do { try await Player.togglePlayPause() }
        catch { errorText = "Playback failed: \(error.localizedDescription)" }
    }

    func skipForward() async { await Player.next() }
    func skipBackward() async { await Player.previous() }
}

/// Thin nonisolated wrapper around `ApplicationMusicPlayer.shared`.
///
/// The player is not `Sendable` and its playback methods are `nonisolated async`, so a
/// `@MainActor` caller awaiting `player.play()` is *sending* a non-Sendable value across an
/// isolation boundary — which Swift 6 rejects outright. Reaching for `.shared` INSIDE a
/// nonisolated async function keeps the player's entire use in one isolation context, so
/// nothing is ever sent. Same singleton either way; this is about where it is touched from.
///
/// It has to be the shared instance: that is the queue the system Now Playing controls and the
/// audio session are attached to, and a second player would fight this one for both.
private enum Player {
    static func play<T: PlayableMusicItem>(_ item: T) async throws {
        let player = ApplicationMusicPlayer.shared
        player.queue = [item]
        try await player.play()
    }

    static func togglePlayPause() async throws {
        let player = ApplicationMusicPlayer.shared
        if player.state.playbackStatus == .playing { player.pause() }
        else { try await player.play() }
    }

    static func next() async { try? await ApplicationMusicPlayer.shared.skipToNextEntry() }
    static func previous() async { try? await ApplicationMusicPlayer.shared.skipToPreviousEntry() }

    static var currentTitle: String? { ApplicationMusicPlayer.shared.queue.currentEntry?.title }
    static var currentSubtitle: String? { ApplicationMusicPlayer.shared.queue.currentEntry?.subtitle }
}

struct MusicPanelView: View {
    @State private var model = MusicModel()
    @State private var query = ""

    /// The player's own ObservableObject, watched directly. Playback state changes for reasons
    /// this app never sees — the system Now Playing controls, a Siri request, the track simply
    /// ending — so a mirrored copy in `MusicModel` would drift and leave the play/pause button
    /// lying about what is happening.
    @ObservedObject private var playerState = ApplicationMusicPlayer.shared.state

    var body: some View {
        NavigationStack {
            Group {
                switch model.status {
                case .authorized:  library
                case .notDetermined: permissionPrompt
                default:           denied
                }
            }
            .navigationTitle("Music")
        }
        .safeAreaInset(edge: .bottom) {
            if model.nowPlayingTitle != nil { nowPlaying }
        }
        .task {
            if model.status == .authorized { await model.loadLibrary() }
        }
        .alert("Music", isPresented: .init(get: { model.errorText != nil },
                                           set: { if !$0 { model.errorText = nil } })) {
            Button("OK", role: .cancel) { model.errorText = nil }
        } message: {
            Text(model.errorText ?? "")
        }
    }

    private var permissionPrompt: some View {
        ContentUnavailableView {
            Label("Play your music here", systemImage: "music.note")
        } description: {
            Text("Float can play your Apple Music library without leaving the scene.")
        } actions: {
            Button("Allow Access") {
                Task { await model.requestAuthorization() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var denied: some View {
        ContentUnavailableView {
            Label("No access to Music", systemImage: "music.note")
        } description: {
            Text("Enable Media & Apple Music for Float in Settings → Privacy.")
        }
    }

    private var library: some View {
        List {
            if !model.searchResults.isEmpty {
                Section("Apple Music") {
                    ForEach(model.searchResults) { song in
                        Button {
                            Task { await model.play(song) }
                        } label: {
                            row(title: song.title, subtitle: song.artistName, art: song.artwork)
                        }
                    }
                }
            }
            Section("Playlists") {
                if model.playlists.isEmpty { Text("None").foregroundStyle(.secondary) }
                ForEach(model.playlists) { playlist in
                    Button {
                        Task { await model.play(playlist) }
                    } label: {
                        row(title: playlist.name,
                            subtitle: playlist.curatorName ?? "Playlist",
                            art: playlist.artwork)
                    }
                }
            }
            Section("Recently Added") {
                if model.albums.isEmpty { Text("None").foregroundStyle(.secondary) }
                ForEach(model.albums) { album in
                    Button {
                        Task { await model.play(album) }
                    } label: {
                        row(title: album.title, subtitle: album.artistName, art: album.artwork)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search Apple Music")
        .onSubmit(of: .search) {
            Task { await model.search(query) }
        }
        .overlay { if model.loading { ProgressView() } }
    }

    private func row(title: String, subtitle: String, art: Artwork?) -> some View {
        HStack(spacing: 12) {
            if let art {
                ArtworkImage(art, width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var nowPlaying: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.nowPlayingTitle ?? "").font(.callout).lineLimit(1)
                if let sub = model.nowPlayingSubtitle {
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button { Task { await model.skipBackward() } } label: {
                Image(systemName: "backward.fill")
            }
            Button { Task { await model.togglePlayPause() } } label: {
                Image(systemName: playerState.playbackStatus == .playing ? "pause.fill" : "play.fill")
            }
            Button { Task { await model.skipForward() } } label: {
                Image(systemName: "forward.fill")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }
}
