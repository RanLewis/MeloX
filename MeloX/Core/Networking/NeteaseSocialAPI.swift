import Foundation

/// 私信 / 动态分享是网易云社交链路，Melody 后端没有任何对应接口。
/// 读取类返回空集合（界面显示空态），写入类抛 `.notSupported`。
extension NeteaseAPI {
    func privateMessageConversations(
        offset: Int = 0,
        limit: Int = 50
    ) async throws -> [NeteasePrivateConversation] {
        []
    }

    func privateMessageHistory(
        userID: Int,
        before: Int64? = nil,
        limit: Int = 100
    ) async throws -> [NeteasePrivateMessage] {
        []
    }

    func sendPrivateText(
        _ message: String,
        to userIDs: [Int]
    ) async throws {
        throw APIError.notSupported
    }

    func messageContacts(
        userID: Int,
        pageSize: Int = 100,
        maximumCount: Int = 1_000
    ) async throws -> [NeteaseMessageContact] {
        []
    }

    func sendPrivateMessage(
        _ resource: NeteaseShareResource,
        to userIDs: [Int],
        message: String = ""
    ) async throws {
        throw APIError.notSupported
    }

    func shareToTimeline(
        _ resource: NeteaseShareResource,
        message: String = ""
    ) async throws {
        throw APIError.notSupported
    }
}
