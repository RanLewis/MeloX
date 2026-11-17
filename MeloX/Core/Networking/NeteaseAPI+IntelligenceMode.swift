import Foundation

extension NeteaseAPI {
    func intelligenceModeSongs(
        seedSongID: Int,
        playlistID: Int
    ) async throws -> [Song] {
        // 心动模式的本质是"按种子歌续播相似曲目"。后端没有推荐算法，
        // 用最近红心顶替，并排除种子本身。
        let songs = try await melodyLikedSongs(limit: 30)
            .filter { $0.id != seedSongID }
        guard !songs.isEmpty else {
            throw IntelligenceModeError.emptyRecommendations
        }
        return songs
    }
}

private enum IntelligenceModeError: LocalizedError {
    case emptyRecommendations

    var errorDescription: String? {
        L10n.string("ui.error.heart_mode.no_playable_song")
    }
}
