import Foundation

extension NeteaseAPI {
    func subscribedAlbums(limit: Int = 2_000) async throws -> [Album] {
        // 后端没有"收藏专辑"，用红心歌曲的专辑去重顶上，和首页 newAlbums 一致。
        let songs = try await melodyLikedSongs(limit: 200)
        var seen = Set<Int>()
        var albums: [Album] = []
        for song in songs {
            guard let album = song.album,
                  album.id > 0,
                  seen.insert(album.id).inserted else { continue }
            albums.append(album)
            if albums.count >= max(limit, 1) { break }
        }
        return albums
    }
}

private struct SubscribedAlbumsResponse: Decodable {
    let code: Int
    let albums: [Album]?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case code
        case albums = "data"
        case message
    }
}
