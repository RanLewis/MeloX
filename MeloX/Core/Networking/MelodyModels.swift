import Foundation

// MARK: - 后端 VO
//
// 形状来自 lewis-dash `src/server/modules/melody/**.vo.ts`。注意这些结构**不是**
// 网易云的原始 JSON：歌曲用 `artist`/`album`/`duration`，歌单的 `creator` 是一段
// 字符串，`trackIds` 是纯数字数组。所以都不能直接喂给 iOS 的 `Song`/`Playlist`
// 解码器（它们读 `ar`/`al`/`dt` 和对象数组），必须经过 `MelodyMapper`。

struct MelodyArtistVO: Decodable {
    let id: Int?
    let name: String?
    /// 歌曲内嵌歌手用 `alia`，歌手详情用 `alias`。
    let alia: [String]?
    let alias: [String]?
    let picUrl: String?
    let img1v1Url: String?
    let followed: Bool?
    let briefDesc: String?
    let musicSize: Int?
    let albumSize: Int?
}

struct MelodyAlbumBriefVO: Decodable {
    let id: Int?
    let name: String?
    let pic: Int64?
    let pic_str: String?
    let picUrl: String?
}

struct MelodyAlbumVO: Decodable {
    let id: Int?
    let name: String?
    let alias: [String]?
    let type: String?
    let size: Int?
    let pic: Int64?
    let picUrl: String?
    let blurPicUrl: String?
    let briefDesc: String?
    let description: String?
    let publishTime: Double?
    let artists: [MelodyArtistVO]?
    let artist: MelodyArtistVO?
}

struct MelodySongVO: Decodable {
    let id: Int?
    let name: String?
    let artist: [MelodyArtistVO]?
    let album: MelodyAlbumBriefVO?
    let no: Int?
    let cd: String?
    /// 毫秒
    let duration: Int?
    let alia: [String]?
}

struct MelodyPlaylistVO: Decodable {
    let id: Int?
    let name: String?
    let coverImgId: Int64?
    let coverImgUrl: String?
    let creator: String?
    let subscribed: Bool?
    let description: String?
    let trackCount: Int?
}

struct MelodyPlaylistDetailVO: Decodable {
    let id: Int?
    let name: String?
    let coverImgId: Int64?
    let coverImgUrl: String?
    let creator: String?
    let subscribed: Bool?
    let description: String?
    let tracks: [MelodySongVO]?
    let trackIds: [Int]?
}

struct MelodyProfileVO: Decodable {
    let userId: Int?
    let nickname: String?
    let avatarUrl: String?
    let backgroundUrl: String?
    let signature: String?
}

struct MelodyAccountVO: Decodable {
    let profile: MelodyProfileVO?
}

typealias AccountEnvelope = MelodyAccountVO

struct MelodySearchVO: Decodable {
    let total: Int?
    let songs: [MelodySongVO]?
    let artists: [MelodyArtistVO]?
    let albums: [MelodyAlbumVO]?
    let playlists: [MelodyPlaylistVO]?
}

struct MelodyLyricTextVO: Decodable {
    let lyric: String?
    let version: Int?
}

struct MelodyLyricVO: Decodable {
    let lrc: MelodyLyricTextVO?
    let yrc: MelodyLyricTextVO?
    let tlyric: MelodyLyricTextVO?
    let klyric: MelodyLyricTextVO?
    let romalrc: MelodyLyricTextVO?
    let pureMusic: Bool?
}

struct MelodySongURLVO: Decodable {
    let id: Int?
    let url: String?
    let md5: String?
    let type: String?
    let size: Int64?
    let br: Int?
    let level: String?
}

struct MelodyArtistSongsVO: Decodable {
    let total: Int?
    let more: Bool?
    let songs: [MelodySongVO]?
}

struct MelodyArtistDetailVO: Decodable {
    let artist: MelodyArtistVO?
    let hotSongs: [MelodySongVO]?
    let more: Bool?
}

struct MelodyAlbumDetailVO: Decodable {
    let album: MelodyAlbumVO?
    let songs: [MelodySongVO]?
}

struct MelodyArtistAlbumsVO: Decodable {
    let artist: MelodyArtistVO?
    let hotAlbums: [MelodyAlbumVO]?
    let more: Bool?
}

// MARK: - VO → 领域模型

enum MelodyMapper {
    static func artist(_ vo: MelodyArtistVO) -> Artist {
        Artist(
            id: vo.id ?? 0,
            name: vo.name?.nonempty ?? L10n.string("ui.metadata.unknown_artist"),
            picURL: vo.picUrl?.nonempty,
            avatarURL: vo.img1v1Url?.nonempty,
            aliases: vo.alias ?? vo.alia ?? [],
            isFollowed: vo.followed ?? false
        )
    }

    static func album(_ vo: MelodyAlbumBriefVO) -> Album {
        Album(
            id: vo.id ?? 0,
            name: vo.name?.nonempty ?? L10n.string("ui.metadata.unknown_album"),
            picURL: vo.picUrl?.nonempty,
            picID: vo.pic
        )
    }

    static func album(_ vo: MelodyAlbumVO) -> Album {
        let artists = (vo.artists ?? []).map(artist)
        return Album(
            id: vo.id ?? 0,
            name: vo.name?.nonempty ?? L10n.string("ui.metadata.unknown_album"),
            picURL: vo.picUrl?.nonempty ?? vo.blurPicUrl?.nonempty,
            picID: vo.pic,
            artists: artists.isEmpty ? (vo.artist.map { [artist($0)] } ?? []) : artists,
            publishTime: vo.publishTime,
            size: vo.size,
            type: vo.type,
            albumDescription: vo.description?.nonempty ?? vo.briefDesc?.nonempty
        )
    }

    static func song(_ vo: MelodySongVO) -> Song? {
        guard let id = vo.id, id > 0 else { return nil }
        let artists = (vo.artist ?? []).map(artist)
        return Song(
            id: id,
            name: vo.name?.nonempty ?? L10n.string("ui.metadata.unknown_song"),
            artists: artists,
            album: vo.album.map(album),
            durationMS: vo.duration ?? 0,
            trackNumber: vo.no,
            disc: vo.cd,
            aliases: vo.alia ?? []
        )
    }

    static func songs(_ values: [MelodySongVO]?) -> [Song] {
        (values ?? []).compactMap(song)
    }

    static func playlist(_ vo: MelodyPlaylistVO) -> Playlist? {
        guard let id = vo.id, id > 0 else { return nil }
        return Playlist(
            id: id,
            name: vo.name?.nonempty ?? L10n.string("ui.metadata.unknown_playlist"),
            coverURLString: vo.coverImgUrl?.nonempty,
            playlistDescription: vo.description?.nonempty,
            trackCount: vo.trackCount ?? 0,
            creator: vo.creator?.nonempty.map { UserSummary(userID: 0, nickname: $0) },
            subscribed: vo.subscribed ?? false
        )
    }

    static func playlists(_ values: [MelodyPlaylistVO]?) -> [Playlist] {
        (values ?? []).compactMap(playlist)
    }

    /// 详情同样返回全量曲目：后端 `/playlist/detail` 一次给完，和网易的分页语义
    /// 不同，所以 `trackIDs` 由 `tracks` 反推，`trackCount` 用实际条数。
    static func playlistDetail(_ vo: MelodyPlaylistDetailVO) -> Playlist? {
        guard let id = vo.id, id > 0 else { return nil }
        let tracks = songs(vo.tracks)
        let trackIDs: [TrackReference] = vo.trackIds?.map { TrackReference(id: $0) }
            ?? tracks.map { TrackReference(id: $0.id) }
        return Playlist(
            id: id,
            name: vo.name?.nonempty ?? L10n.string("ui.metadata.unknown_playlist"),
            coverURLString: vo.coverImgUrl?.nonempty,
            playlistDescription: vo.description?.nonempty,
            trackCount: tracks.isEmpty ? trackIDs.count : tracks.count,
            creator: vo.creator?.nonempty.map { UserSummary(userID: 0, nickname: $0) },
            tracks: tracks,
            trackIDs: trackIDs,
            subscribed: vo.subscribed ?? false
        )
    }

    static func profile(_ vo: MelodyProfileVO) -> AccountProfile {
        AccountProfile(
            id: vo.userId ?? 0,
            nickname: vo.nickname?.nonempty ?? "Melody",
            avatarURLString: vo.avatarUrl?.nonempty,
            backgroundURLString: vo.backgroundUrl?.nonempty,
            signature: vo.signature?.nonempty,
            follows: nil,
            followeds: nil,
            eventCount: nil,
            playlistCount: nil,
            playlistBeSubscribedCount: nil
        )
    }

    /// 播放地址：后端给的是网易 CDN 的 http 链接，App 的网络策略只放行 https。
    static func playbackSource(
        _ vo: MelodySongURLVO,
        requested quality: MusicQuality?
    ) -> PlaybackSource? {
        guard let raw = vo.url?.nonempty,
              let url = secureURL(raw) else { return nil }
        return PlaybackSource(
            url: url,
            bitrate: vo.br,
            format: vo.type,
            quality: (vo.level.flatMap(MusicQuality.init(apiLevel:)) ?? quality)
        )
    }

    static func secureURL(_ raw: String) -> URL? {
        guard var components = URLComponents(string: raw) else { return nil }
        if components.scheme?.lowercased() == "http" {
            components.scheme = "https"
        }
        return components.url
    }
}

private extension String {
    var nonempty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
