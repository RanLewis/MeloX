import Foundation

extension NeteaseAPI {
    func subscribedArtists(limit: Int = 2_000) async throws -> [Artist] {
        // 后端没有"关注歌手"，从红心歌曲里聚合歌手并去重。
        let songs = try await melodyLikedSongs(limit: 300)
        var seen = Set<Int>()
        var artists: [Artist] = []
        for song in songs {
            for artist in song.artists where artist.id > 0 {
                guard seen.insert(artist.id).inserted else { continue }
                artists.append(artist)
                if artists.count >= max(limit, 1) { return artists }
            }
        }
        return artists
    }

    func setArtistFollowed(id: Int, isFollowed: Bool) async throws {
        // 没有后端存储，操作不落盘，但也不该让 UI 报错。
    }

}

private struct SubscribedArtistsResponse: Decodable {
    let code: Int
    let artists: [Artist]
    let hasMore: Bool?
    let count: Int?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case code
        case artists = "data"
        case hasMore, count, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(Int.self, forKey: .code) ?? 200
        artists = try container.decodeIfPresent(
            [Artist].self,
            forKey: .artists
        ) ?? []
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

