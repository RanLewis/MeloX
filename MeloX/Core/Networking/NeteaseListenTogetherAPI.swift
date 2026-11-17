import Foundation

enum ListenTogetherCommandType: String {
    case play = "PLAY"
    case pause = "PAUSE"
    case next = "NEXT"
    case previous = "PREV"
    case goTo = "GOTO"
    case progress = "PROGRESS"
}

/// 一起听是网易云的实时房间能力（房间存在网易云侧，靠轮询 + 指令上报同步）。
/// Melody 后端没有这套东西，所以这里保留全部方法签名，统一抛 `.notSupported`：
/// UI 会拿到一条明确的「当前后端不支持」提示，而不是卡在一个永远失败的请求上。
extension NeteaseAPI {
    func createListenTogetherRoom() async throws -> ListenTogetherRoomPayload {
        throw APIError.notSupported
    }

    func listenTogetherRoomStatus() async throws
        -> ListenTogetherRoomStatus {
        throw APIError.notSupported
    }

    func checkListenTogetherRoom(
        roomID: String
    ) async throws -> ListenTogetherRoomCheck {
        throw APIError.notSupported
    }

    func acceptListenTogetherInvitation(
        roomID: String,
        inviterID: String
    ) async throws -> ListenTogetherRoomPayload {
        throw APIError.notSupported
    }

    func listenTogetherPlayback(
        roomID: String
    ) async throws -> ListenTogetherPlaybackPayload {
        throw APIError.notSupported
    }

    func reportListenTogetherPlaylist(
        roomID: String,
        userID: Int,
        version: Int,
        displaySongIDs: [Int],
        randomSongIDs: [Int],
        commandType: String = "REPLACE"
    ) async throws {
        throw APIError.notSupported
    }

    func reportListenTogetherCommand(
        roomID: String,
        commandType: ListenTogetherCommandType,
        progressMilliseconds: Int64,
        isPlaying: Bool,
        formerSongID: Int?,
        targetSongID: Int,
        clientSequence: Int
    ) async throws {
        throw APIError.notSupported
    }

    @discardableResult
    func sendListenTogetherHeartbeat(
        roomID: String,
        songID: Int,
        isPlaying: Bool,
        progressMilliseconds: Int64
    ) async throws -> Int? {
        throw APIError.notSupported
    }

    func endListenTogetherRoom(roomID: String) async throws {
        throw APIError.notSupported
    }
}
