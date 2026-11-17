import Foundation

enum PersonalFMMode: String {
    case familiar = "FAMILIAR"
    case explore = "EXPLORE"
}

extension NeteaseAPI {
    func homePage(
        refresh: Bool = false,
        cursor: String? = nil
    ) async throws -> HomePagePayload {
        // 后端没有"首页聚合块"这种编排接口。这里返回一个空 payload，
        // 真正的分区由 HomeRecommendationFallbackLoader 用真实接口拼出来：
        // 推荐歌单 = 我的歌单，为你推荐 / 私人 FM = 最近红心。
        let data = try JSONSerialization.data(
            withJSONObject: ["blocks": [Any](), "hasMore": false]
        )
        return try JSONDecoder().decode(HomePagePayload.self, from: data)
    }

    func topSongs(
        region: HomeMusicRegion,
        limit: Int = 12
    ) async throws -> [Song] {
        // 没有分地区热歌榜，用最近红心充数。
        try await melodyLikedSongs(limit: min(max(limit, 1), 100))
    }

    func personalizedNewSongs(
        region: HomeMusicRegion,
        limit: Int = 12
    ) async throws -> [Song] {
        // 没有"个性化新歌"；用最近红心顶替，语义上最接近"为你推荐"。
        try await melodyLikedSongs(limit: min(max(limit, 1), 100))
    }

    func recommendedPodcastPrograms(
        limit: Int = 12
    ) async throws -> [PodcastProgram] {
        // 后端没有播客库。
        []
    }

    func personalFM(
        mode: PersonalFMMode = .explore,
        limit: Int = 30
    ) async throws -> [Song] {
        // 没有电台推荐算法；私人 FM 也用最近红心，至少每一首都能播。
        try await melodyLikedSongs(limit: min(max(limit, 1), 50))
    }
}
