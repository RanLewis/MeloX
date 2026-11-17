import Foundation

/// 播客（电台）整套接口都依赖网易云 djradio 数据，Melody 后端只有歌曲 / 歌单 /
/// 歌手 / 专辑 / 搜索。读取类统一返回空集合让各页面显示空态，
/// 订阅写入抛 `.notSupported`。
extension NeteaseAPI {
    func podcastCategories() async throws -> [PodcastCategory] {
        []
    }

    func featuredPodcasts() async throws -> [Podcast] {
        []
    }

    func personalizedPodcasts(
        limit: Int = 12
    ) async throws -> [Podcast] {
        []
    }

    func podcasts(
        categoryID: Int,
        offset: Int = 0,
        limit: Int = 30
    ) async throws -> PodcastPage {
        PodcastPage(podcasts: [], hasMore: false, totalCount: 0)
    }

    func podcast(id: Int) async throws -> Podcast {
        throw APIError.notSupported
    }

    func podcastPrograms(
        radioID: Int,
        offset: Int = 0,
        limit: Int = 30,
        ascending: Bool = false
    ) async throws -> PodcastProgramPage {
        PodcastProgramPage(programs: [], hasMore: false, totalCount: 0)
    }

    func subscribedPodcasts(
        offset: Int = 0,
        limit: Int = 50
    ) async throws -> PodcastPage {
        PodcastPage(podcasts: [], hasMore: false, totalCount: 0)
    }

    func setPodcastSubscribed(
        id: Int,
        isSubscribed: Bool
    ) async throws {
        throw APIError.notSupported
    }
}
