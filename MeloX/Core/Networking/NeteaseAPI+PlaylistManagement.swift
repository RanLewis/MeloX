import Foundation

extension NeteaseAPI {
    func removeSong(id: Int, fromPlaylistID playlistID: Int) async throws {
        try await manipulatePlaylistTrack(id: id, playlistID: playlistID, operation: "del")
    }

    func manipulatePlaylistTrack(id: Int, playlistID: Int, operation: String) async throws {
        // 后端的 op 只认 add / del，`trackIds` 是数字数组（网易那边是 JSON 字符串）。
        let op = operation == "del" ? "del" : "add"
        try await melody.postIgnoringPayload(
            "/api/melody/playlist/manipulate/tracks",
            body: [
                "op": op,
                "pid": playlistID,
                "trackIds": [id],
            ]
        )
    }

    func deletePlaylist(id: Int) async throws {
        // 后端没有歌单删除出口：只同步网易侧的歌单，不在本地建删。
        throw APIError.server(
            statusCode: 501,
            message: L10n.string("ui.error.api.operation_incomplete")
        )
    }

    func createPlaylist(name: String, isPrivate: Bool) async throws -> Playlist {
        // 同上：后端只镜像已存在的歌单，没有创建入口。
        throw APIError.server(
            statusCode: 501,
            message: L10n.string("ui.error.api.operation_incomplete")
        )
    }
}
