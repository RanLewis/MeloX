import Foundation

extension NeteaseAPI {
    func userPlayRecords(
        userID: Int,
        period: UserPlayRecordPeriod
    ) async throws -> [UserPlayRecord] {
        // 后端不记录播放历史（只有收藏与歌单）。
        []
    }
}
