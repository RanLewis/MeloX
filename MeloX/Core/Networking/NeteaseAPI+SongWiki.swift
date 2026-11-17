import Foundation

extension NeteaseAPI {
    func songWiki(id: Int) async throws -> SongWiki {
        // 歌曲百科是网易的运营内容，后端没有对应数据。
        throw APIError.server(
            statusCode: 501,
            message: L10n.string("ui.error.song_wiki.load_failed")
        )
    }
}
