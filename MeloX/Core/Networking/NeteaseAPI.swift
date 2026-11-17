import Foundation
import Network
import Observation

enum SearchKind: Int, CaseIterable, Identifiable, Hashable {
    case songs = 1
    case albums = 10
    case artists = 100
    case playlists = 1_000
    case podcasts = 1_009

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .songs: L10n.string("ui.search.kind.songs")
        case .albums: L10n.string("ui.search.kind.albums")
        case .artists: L10n.string("ui.search.kind.artists")
        case .playlists: L10n.string("ui.search.kind.playlists")
        case .podcasts: L10n.string("ui.search.kind.podcasts")
        }
    }
}

enum APIError: LocalizedError {
    case requestEncoding
    case invalidResponse
    case emptyResponse(statusCode: Int)
    case server(statusCode: Int, message: String)
    case noPlayableSource
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .requestEncoding:
            L10n.string("ui.error.api.request_encoding")
        case .invalidResponse:
            L10n.string("ui.error.api.invalid_response")
        case .emptyResponse(let statusCode):
            L10n.format("ui.error.api.empty_response", statusCode)
        case .server(let statusCode, _):
            L10n.format("ui.error.api.server_code", statusCode)
        case .noPlayableSource:
            L10n.string("ui.error.api.no_playable_source")
        case .notLoggedIn:
            L10n.string("ui.error.api.login_required")
        }
    }
}

@MainActor
@Observable
final class NeteaseAPI {
    @ObservationIgnored
    private let settings: AppSettings

    @ObservationIgnored
    private let pathMonitor = NWPathMonitor()

    private(set) var isCellularData = false

    @ObservationIgnored
    let client: NeteaseDirectClient

    /// 本 fork 的音源后端。对外方法都改走这里；`client` 只留给尚未迁移的
    /// 播客 / 社交 / 听歌一起听扩展，避免一次性改动太大。
    @ObservationIgnored
    let melody: MelodyClient

    @ObservationIgnored
    let pageContentCache: PageContentCache

    private var playbackQuality: MusicQuality {
        isCellularData ? settings.cellularQuality : settings.quality
    }

    init(settings: AppSettings, session: URLSession = .shared) {
        self.settings = settings
        pageContentCache = PageContentCache(settings: settings)
        client = NeteaseDirectClient(settings: settings, session: session)
        melody = MelodyClient(settings: settings, session: session)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let isCellular = path.usesInterfaceType(.cellular)
            Task { @MainActor [weak self] in
                self?.isCellularData = isCellular
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "MeloX.NetworkMonitor"))
    }

    deinit {
        pathMonitor.cancel()
    }

    func recommendedPlaylists(limit: Int = 10) async throws -> [Playlist] {
        // 后端没有"推荐"出口，用它真正拥有的东西顶上：登录用户自己的歌单。
        let values: [MelodyPlaylistVO] = try await melody.get("/api/melody/playlist/user")
        return Array(MelodyMapper.playlists(values).prefix(max(limit, 1)))
    }

    func newAlbums(limit: Int = 10, area: String? = nil) async throws -> [Album] {
        // 没有"新碟上架"数据源；从收藏歌曲里按专辑去重，给出的是真实存在的封面墙。
        let songs = try await melodyLikedSongs(limit: 300)
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

    func toplists() async throws -> [Playlist] {
        // 没有榜单接口；我的歌单是唯一"有顺序、会变"的列表，用它占位。
        try await recommendedPlaylists(limit: 12)
    }

    func topArtists() async throws -> [Artist] {
        // 从收藏歌曲里聚合歌手，按出现次数排序。后端没有歌手榜单。
        let songs = try await melodyLikedSongs(limit: 300)
        var counts: [Int: (artist: Artist, hits: Int)] = [:]
        for song in songs {
            for artist in song.artists where artist.id > 0 {
                let current = counts[artist.id]
                counts[artist.id] = (current?.artist ?? artist, (current?.hits ?? 0) + 1)
            }
        }
        return counts.values
            .sorted { $0.hits > $1.hits }
            .map(\.artist)
    }

    func playlists(category: String, offset: Int = 0, limit: Int = 50) async throws -> [Playlist] {
        // 分类广场依赖网易的歌单库，后端只有"我自己的歌单"，所以任何分类都返回同一份。
        let all = try await recommendedPlaylists(limit: 2_000)
        let start = min(max(offset, 0), all.count)
        let end = min(start + max(limit, 1), all.count)
        return Array(all[start..<end])
    }

    func playlist(
        id: Int,
        trackLimit: Int? = 100
    ) async throws -> Playlist {
        // 后端一次返回全量曲目（和网易的分页语义不同），客户端自己截断。
        let response: MelodyPlaylistDetailVO = try await melody.get(
            "/api/melody/playlist/detail",
            query: [URLQueryItem(name: "playlistId", value: String(id))]
        )
        guard var playlist = MelodyMapper.playlistDetail(response) else {
            throw APIError.invalidResponse
        }
        if let trackLimit, playlist.tracks.count > trackLimit {
            let kept = Array(playlist.tracks.prefix(max(trackLimit, 0)))
            let ids = Set(kept.map(\.id))
            playlist.tracks = kept
            playlist.trackIDs = playlist.trackIDs.filter { ids.contains($0.id) }
        }
        return playlist
    }

    func album(id: Int) async throws -> (Album, [Song]) {
        let response: MelodyAlbumDetailVO = try await melody.get("/api/melody/album/\(id)")
        guard let albumVO = response.album else { throw APIError.invalidResponse }
        return (MelodyMapper.album(albumVO), MelodyMapper.songs(response.songs))
    }

    func albumSubscriptionStatus(id: Int) async throws -> Bool {
        // 后端没有"收藏专辑"这一层，UI 只是拿它决定按钮状态。
        false
    }

    func setAlbumSubscribed(id: Int, isSubscribed: Bool) async throws {
        // 同上：没有后端存储，操作不落盘，但也不该让 UI 报错。
    }

    func artist(id: Int) async throws -> (Artist, [Song], [Album]) {
        let detail: MelodyArtistDetailVO = try await melody.get("/api/melody/artist/v1/\(id)")
        let artist = detail.artist.map(MelodyMapper.artist)
            ?? Artist(id: id, name: L10n.string("ui.metadata.unknown_artist"))
        let albums: MelodyArtistAlbumsVO = try await melody.get(
            "/api/melody/album/artist/\(id)"
        )
        return (
            artist,
            MelodyMapper.songs(detail.hotSongs),
            (albums.hotAlbums ?? []).map(MelodyMapper.album)
        )
    }

    func songDetails(ids: [Int]) async throws -> [Song] {
        guard !ids.isEmpty else { return [] }
        var collected: [Song] = []
        // 后端单次上限 2000，这里按 500 一批，避免 URLSession 请求体过大。
        for start in stride(from: 0, to: ids.count, by: 500) {
            try Task.checkCancellation()
            let end = min(start + 500, ids.count)
            let values: [MelodySongVO] = try await melody.post(
                "/api/melody/song/batch/detail",
                body: ["songIds": Array(ids[start..<end])]
            )
            collected.append(contentsOf: MelodyMapper.songs(values))
        }
        let byID = Dictionary(
            collected.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return ids.compactMap { byID[$0] }
    }

    func songDetailsCollection(
        ids: [Int],
        prefetched: [Song] = []
    ) async throws -> [Song] {
        guard !ids.isEmpty else { return [] }

        var detailsByID = Dictionary(
            prefetched.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let missingIDs = ids.filter { detailsByID[$0] == nil }

        for start in stride(from: 0, to: missingIDs.count, by: 100) {
            try Task.checkCancellation()
            let end = min(start + 100, missingIDs.count)
            for song in try await songDetails(
                ids: Array(missingIDs[start..<end])
            ) {
                detailsByID[song.id] = song
            }
        }

        return ids.compactMap { detailsByID[$0] }
    }

    func audioMatches(
        fingerprint: String,
        duration: Int
    ) async throws -> [AudioMatchCandidate] {
        guard !fingerprint.isEmpty,
              (1...15).contains(duration),
              let encodedFingerprint = fingerprint.addingPercentEncoding(
                withAllowedCharacters: Self.audioMatchQueryValueAllowed
              ) else {
            throw APIError.requestEncoding
        }

        // Mirrors @neteaseapireborn/api/module/audio_match.js exactly:
        // this is NetEase's original public matcher, not a proxy route.
        var components = URLComponents(
            string: "https://interface.music.163.com/api/music/audio/match"
        )
        components?.percentEncodedQuery = [
            "sessionId=0123456789abcdef",
            "algorithmCode=shazam_v2",
            "duration=\(duration)",
            "rawdata=\(encodedFingerprint)",
            "times=1",
            "decrypt=1",
        ].joined(separator: "&")
        guard let url = components?.url else {
            throw APIError.requestEncoding
        }

        let response: AudioMatchResponse = try await client.get(url)
        try validate(responseCode: response.code)
        return response.data?.result ?? []
    }

    func songDetailsPage(
        ids: [Int],
        offset: Int,
        limit: Int = 100
    ) async throws -> SongCollectionPage {
        let start = min(max(offset, 0), ids.count)
        let end = min(start + min(max(limit, 1), 100), ids.count)
        let pageIDs = Array(ids[start..<end])
        guard !pageIDs.isEmpty else {
            return SongCollectionPage(
                songs: [],
                nextOffset: end,
                totalCount: ids.count
            )
        }

        let details = try await songDetails(ids: pageIDs)
        var detailsByID: [Int: Song] = [:]
        for song in details {
            detailsByID[song.id] = song
        }
        return SongCollectionPage(
            songs: pageIDs.compactMap { detailsByID[$0] },
            nextOffset: end,
            totalCount: ids.count
        )
    }

    func songComments(
        id: Int,
        offset: Int = 0,
        limit: Int = 20,
        beforeTime: Int64 = 0
    ) async throws -> SongCommentsResponse {
        let path = "/api/v1/resource/comments/R_SO_4_\(id)"
        let data: [String: Any] = [
            "rid": id,
            "limit": limit,
            "offset": offset,
            "beforeTime": beforeTime,
        ]
        let response: SongCommentsResponse
        do {
            // @neteaseapireborn/api 对该路由使用 weapi。
            response = try await client.weapi(path, data: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch APIError.emptyResponse {
            // CFNetwork 请求部分网易云 weapi 路由时会得到 HTTP 200 空包；
            // 保留完全相同的原始路由和参数，仅切换到其支持的 eapi 传输。
            response = try await client.eapi(path, data: data)
        }
        try validate(responseCode: response.code)
        return response
    }

    func songCommentReplies(
        songID: Int,
        parentCommentID: Int64,
        time: Int64 = -1,
        limit: Int = 20
    ) async throws -> SongCommentFloorResponse {
        let path = "/api/resource/comment/floor/get"
        let data: [String: Any] = [
            "parentCommentId": parentCommentID,
            "threadId": "R_SO_4_\(songID)",
            "time": time,
            "limit": limit,
        ]
        let response: SongCommentFloorResponse
        do {
            // @neteaseapireborn/api/module/comment_floor.js 使用同一路由和 weapi 参数。
            response = try await client.weapi(path, data: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch APIError.emptyResponse {
            response = try await client.eapi(path, data: data)
        }
        try validate(responseCode: response.code)
        return response
    }

    func playbackSource(id: Int) async throws -> PlaybackSource {
        try await playbackSource(
            id: id,
            quality: playbackQuality,
            availability: .unknown
        )
    }

    func playbackSource(for song: Song) async throws -> PlaybackSource {
        try await playbackSource(
            id: song.id,
            quality: playbackQuality,
            availability: song.audioAvailability
        )
    }

    private func playbackSource(
        id: Int,
        quality: MusicQuality,
        availability: SongAudioAvailability
    ) async throws -> PlaybackSource {
        // 逐档降级：后端拿不到该档位时返回空 url，换低一档再试。
        for candidate in quality.playbackCandidates(for: availability) {
            do {
                return try await requestPlaybackSource(id: id, quality: candidate)
            } catch is CancellationError {
                throw CancellationError()
            } catch APIError.noPlayableSource {
                continue
            }
        }
        throw APIError.noPlayableSource
    }

    private func requestPlaybackSource(
        id: Int,
        quality: MusicQuality
    ) async throws -> PlaybackSource {
        let values: [MelodySongURLVO] = try await melody.post(
            "/api/melody/song/batch/player/url/v1",
            body: [
                "ids": [id],
                "level": quality.apiLevel,
                "encodeType": "flac",
            ]
        )
        guard let vo = values.first(where: { $0.id == id }) ?? values.first,
              let source = MelodyMapper.playbackSource(vo, requested: quality) else {
            throw APIError.noPlayableSource
        }
        return source
    }

    func downloadSource(
        for song: Song,
        quality: MusicQuality
    ) async throws -> PlaybackSource {
        do {
            for candidate in quality.playbackCandidates(
                for: song.audioAvailability
            ) {
                do {
                    return try await requestDownloadSource(
                        id: song.id,
                        quality: candidate
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch APIError.noPlayableSource {
                    continue
                }
            }
            throw APIError.noPlayableSource
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The dedicated download route can require account privileges.
            // The reference player caches the original player URL as its
            // compatibility path, so preserve that behavior here as well.
            return try await playbackSource(
                id: song.id,
                quality: quality,
                availability: song.audioAvailability
            )
        }
    }

    private func requestDownloadSource(
        id: Int,
        quality: MusicQuality
    ) async throws -> PlaybackSource {
        // 后端没有单独的下载出口，缓存文件直接用播放地址取全量音源。
        try await requestPlaybackSource(id: id, quality: quality)
    }

    func songURL(id: Int) async throws -> URL {
        try await playbackSource(id: id).url
    }

    func search(_ keywords: String, kind: SearchKind, limit: Int = 30) async throws -> SearchPayload {
        guard kind != .podcasts else {
            // 后端没有播客库，搜索播客直接给空，省掉一次必然失败的往返。
            return SearchPayload(
                songs: nil,
                albums: nil,
                artists: nil,
                playlists: nil,
                podcasts: nil
            )
        }
        let payload: MelodySearchVO = try await melody.get(
            "/api/melody/search",
            query: [
                URLQueryItem(name: "keyword", value: keywords),
                URLQueryItem(name: "type", value: String(kind.rawValue)),
                URLQueryItem(name: "limit", value: String(min(max(limit, 1), 100))),
                URLQueryItem(name: "offset", value: "0"),
            ]
        )
        return SearchPayload(
            songs: payload.songs.map(MelodyMapper.songs),
            albums: payload.albums.map { $0.map(MelodyMapper.album) },
            artists: payload.artists.map { $0.map(MelodyMapper.artist) },
            playlists: payload.playlists.map(MelodyMapper.playlists),
            podcasts: nil
        )
    }

    func dailySongs(afresh: Bool = false) async throws -> [Song] {
        // 后端没有"每日推荐"；最近红心是语义上最接近的替代。
        try await melodyLikedSongs(limit: 30)
    }

    func similarSongs(id: Int, limit: Int = 50) async throws -> [Song] {
        // 没有"相似歌曲"算法；退化成"同一位歌手的热门歌"，而且要先知道歌手是谁。
        guard let song = try await songDetails(ids: [id]).first,
              let artistID = song.artists.first?.id, artistID > 0 else {
            return []
        }
        let response: MelodyArtistSongsVO = try await melody.post(
            "/api/melody/song/v1/artist",
            body: [
                "artistId": artistID,
                "limit": min(max(limit, 1), 100),
                "offset": 0,
            ]
        )
        return MelodyMapper.songs(response.songs).filter { $0.id != id }
    }

    func lyrics(id: Int) async throws -> [LyricLine] {
        let payload = try await neteaseLyrics(id: id)
        return LyricParser.parse(
            yrc: payload.yrc ?? "",
            lrc: payload.lrc ?? "",
            translatedYRC: payload.translatedYRC ?? "",
            translatedLRC: payload.translatedLRC ?? "",
            romanizedYRC: payload.romanizedYRC ?? "",
            romanizedLRC: payload.romanizedLRC ?? ""
        )
    }

    func neteaseLyrics(id: Int) async throws -> NeteaseLyricPayload {
        let response: MelodyLyricVO = try await melody.get(
            "/api/melody/lyric",
            query: [URLQueryItem(name: "id", value: String(id))]
        )
        return NeteaseLyricPayload(
            yrc: response.yrc?.lyric,
            lrc: response.lrc?.lyric,
            // 后端只有整轨的 ytlrc/yromalrc 缺失，翻译与罗马音都拿 lrc 版本。
            translatedYRC: nil,
            translatedLRC: response.tlyric?.lyric,
            romanizedYRC: nil,
            romanizedLRC: response.romalrc?.lyric,
            isPureMusic: response.pureMusic == true
        )
    }

    func accountProfile() async throws -> AccountProfile {
        let response: MelodyAccountVO = try await melody.get(
            "/api/melody/auth/nuser/account/get"
        )
        guard let profile = response.profile else {
            throw APIError.notLoggedIn
        }
        return MelodyMapper.profile(profile)
    }

    func userDetail(userID: Int) async throws -> AccountDetail {
        // 后端只有一份账号资料，没有等级/听歌数这类统计。
        AccountDetail(
            profile: try await accountProfile(),
            level: 0,
            listenSongs: 0,
            createDays: nil
        )
    }

    func likedSongIDs(
        userID: Int,
        likedPlaylistID: Int? = nil
    ) async throws -> [Int] {
        // `/song/like` 直接返回全部红心歌曲 ID（后端按加入时间倒序）。
        let ids: [Int] = try await melody.post("/api/melody/song/like", body: [:])
        return ids
    }

    func userPlaylists(userID: Int, limit: Int = 2_000) async throws -> [Playlist] {
        let values: [MelodyPlaylistVO] = try await melody.get("/api/melody/playlist/user")
        return Array(MelodyMapper.playlists(values).prefix(max(limit, 1)))
    }

    func recentSongs(limit: Int = 100) async throws -> [Song] {
        let path = "/api/play-record/song/list"
        let data: [String: Any] = ["limit": limit]
        let response: RecentSongsResponse
        do {
            // Mirrors @neteaseapireborn/api/module/record_recent_song.js.
            response = try await client.weapi(path, data: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch APIError.emptyResponse {
            // CFNetwork may receive an HTTP 200 empty body from this weapi
            // route. Keep its original route and parameters, changing only
            // to the authenticated eapi transport for compatibility.
            response = try await client.eapi(path, data: data, authenticated: true)
        }
        try validate(responseCode: response.code, message: response.message)
        return response.data?.list.compactMap(\.data) ?? []
    }

    func cloudSongs(limit: Int = 200, offset: Int = 0) async throws -> CloudMusicPage {
        let path = "/api/v1/cloud/get"
        let data: [String: Any] = ["limit": limit, "offset": offset]
        let response: CloudMusicPage
        do {
            response = try await client.weapi(path, data: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch APIError.emptyResponse {
            // This authenticated weapi route can return HTTP 200 with an empty
            // body to CFNetwork. Keep the original route and parameters and
            // use its supported eapi transport, matching the other library
            // compatibility fallbacks in this client.
            response = try await client.eapi(path, data: data, authenticated: true)
        }
        try validate(responseCode: response.code)
        return response
    }

    func deleteCloudSong(id: Int) async throws {
        let path = "/api/cloud/del"
        let data: [String: Any] = ["songIds": [id]]
        let response: APIStatusResponse
        do {
            response = try await client.weapi(path, data: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch APIError.emptyResponse {
            response = try await client.eapi(path, data: data, authenticated: true)
        }
        try validate(responseCode: response.code, message: response.message)
    }

    func uploadCloudSong(fileAt url: URL) async throws {
        let file = try await CloudUploadFile.prepare(from: url)
        let bitrate = 999_000

        // Mirrors @neteaseapireborn/api/module/cloud.js: the upload check and
        // metadata registration use the default eapi transport.
        let check: CloudUploadCheckResponse = try await client.eapi(
            "/api/cloud/upload/check",
            data: [
                "bitrate": String(bitrate),
                "ext": "",
                "length": file.size,
                "md5": file.md5,
                "songId": "0",
                "version": 1,
            ],
            authenticated: true
        )
        try validate(responseCode: check.code, message: check.message)

        let metadataToken: CloudNOSTokenResponse = try await client.eapi(
            "/api/nos/token/alloc",
            data: [
                "bucket": "",
                "ext": file.fileExtension,
                "filename": file.normalizedStem,
                "local": false,
                "nos_product": 3,
                "type": "audio",
                "md5": file.md5,
            ],
            authenticated: true
        )
        try validate(responseCode: metadataToken.code, message: metadataToken.message)

        if check.needUpload {
            let bucket = "jd-musicrep-privatecloud-audio-public"
            // songUpload.js deliberately obtains a separate weapi token for
            // the NOS transfer while retaining the eapi resourceId above.
            let tokenPath = "/api/nos/token/alloc"
            let tokenData: [String: Any] = [
                "bucket": bucket,
                "ext": file.fileExtension,
                "filename": file.normalizedStem,
                "local": false,
                "nos_product": 3,
                "type": "audio",
                "md5": file.md5,
            ]
            let uploadToken: CloudNOSTokenResponse
            do {
                uploadToken = try await client.weapi(tokenPath, data: tokenData)
            } catch is CancellationError {
                throw CancellationError()
            } catch APIError.emptyResponse {
                uploadToken = try await client.eapi(
                    tokenPath,
                    data: tokenData,
                    authenticated: true
                )
            }
            try validate(responseCode: uploadToken.code, message: uploadToken.message)
            try await client.uploadToNOS(
                fileURL: file.url,
                bucket: bucket,
                objectKey: uploadToken.result.objectKey,
                token: uploadToken.result.token,
                md5: file.md5,
                fileSize: file.size
            )
        }

        let uploadInfo: CloudUploadInfoResponse = try await client.eapi(
            "/api/upload/cloud/info/v2",
            data: [
                "md5": file.md5,
                "songid": check.songID,
                "filename": file.filename,
                "song": file.songName,
                "album": file.album,
                "artist": file.artist,
                "bitrate": String(bitrate),
                "resourceId": metadataToken.result.resourceID,
            ],
            authenticated: true
        )
        try validate(responseCode: uploadInfo.code, message: uploadInfo.message)

        let publish: APIStatusResponse = try await client.eapi(
            "/api/cloud/pub/v2",
            data: ["songid": uploadInfo.songID],
            authenticated: true
        )
        try validate(responseCode: publish.code, message: publish.message)
    }

    func recordRecentPlayback(songID: Int, sourceID: Int) async throws {
        try await submitPlaybackLog(
            action: "startplay",
            fields: [
                "id": String(songID),
                "type": "song",
                "mainsite": "1",
                "mainsiteWeb": "1",
                "content": "id=\(sourceID)",
            ]
        )
    }

    func recordPlaybackDuration(songID: Int, sourceID: Int, time: Int) async throws {
        try await submitPlaybackLog(
            action: "play",
            fields: [
                "download": 0,
                "end": "playend",
                "id": String(songID),
                "sourceId": String(sourceID),
                "time": String(max(time, 0)),
                "type": "song",
                "wifi": 0,
                "source": "list",
                "mainsite": "1",
                "mainsiteWeb": "1",
                "content": "id=\(sourceID)",
            ]
        )
    }

    private func submitPlaybackLog(
        action: String,
        fields: [String: Any]
    ) async throws {
        let logs: [[String: Any]] = [["action": action, "json": fields]]
        let logsData = try JSONSerialization.data(withJSONObject: logs)
        guard let logsJSON = String(data: logsData, encoding: .utf8) else {
            throw APIError.requestEncoding
        }
        // The current upstream implementation posts both `startplay` and
        // `play` events to the original client-log endpoint using eapi and an
        // OSX client cookie. `startplay` feeds /api/play-record/song/list;
        // `play` carries the elapsed listening time.
        let response: APIStatusResponse = try await client.eapi(
            "/api/feedback/weblog",
            data: ["logs": logsJSON],
            authenticated: true,
            domain: "https://clientlog.music.163.com",
            cookieOS: "osx"
        )
        try validate(responseCode: response.code, message: response.message)
    }

    func setSongLiked(id: Int, isLiked: Bool) async throws {
        try await melody.postIgnoringPayload(
            "/api/melody/song/radio/like",
            body: ["trackId": id, "like": isLiked]
        )
    }

    func setPlaylistSubscribed(id: Int, isSubscribed: Bool) async throws {
        // 后端没有"收藏别人的歌单"这层关系，操作不落盘也不该报错。
    }

    func addSong(id: Int, toPlaylistID playlistID: Int) async throws {
        try await manipulatePlaylistTrack(id: id, playlistID: playlistID, operation: "add")
    }

    /// 最近红心的歌：先取 ID 顺序，再批量补详情。
    /// 后端 `/song/like` 按加入时间倒序返回，所以前缀就是"最近喜欢的"。
    func melodyLikedSongs(limit: Int) async throws -> [Song] {
        let ids = try await likedSongIDs(userID: 0)
        guard !ids.isEmpty else { return [] }
        return try await songDetailsCollection(
            ids: Array(ids.prefix(max(limit, 1)))
        )
    }

    func validate(responseCode: Int, message: String? = nil) throws {
        guard (200..<300).contains(responseCode) else {
            throw APIError.server(
                statusCode: responseCode,
                message: message ?? L10n.string("ui.error.api.operation_incomplete")
            )
        }
    }

    private func securePlaybackURL(from source: String) -> URL? {
        guard var components = URLComponents(string: source) else { return nil }
        if components.scheme?.lowercased() == "http" {
            components.scheme = "https"
        }
        return components.url
    }

    private static let audioMatchQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return allowed
    }()
}
