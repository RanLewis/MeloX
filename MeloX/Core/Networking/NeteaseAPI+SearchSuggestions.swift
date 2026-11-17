import Foundation

extension NeteaseAPI {
    func searchSuggestions(_ keywords: String) async throws -> [String] {
        // 后端没有补全接口；宁可返回空，也不要在输入框里显示网易的推荐词。
        []
    }
}

private struct SearchSuggestionsResponse: Decodable {
    let code: Int
    let result: Suggestions?
    let message: String?

    struct Suggestions: Decodable {
        let allMatch: [Match]?
    }

    struct Match: Decodable {
        let keyword: String
    }
}
