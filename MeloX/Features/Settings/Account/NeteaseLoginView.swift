import SwiftUI
import WebKit

/// 登录 Melody 后端。
///
/// 上游这里是网易云网页登录（WebView 里抓 `MUSIC_U` cookie）。本 fork 的音源
/// 换成了自建后端，凭据模型也随之变成「面板口令 → API 令牌」，所以整页改成表单。
/// 类名保留 `NeteaseLoginView`，因为设置页、音乐库、首次引导三处都用这个名字。
struct NeteaseLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library

    @State private var server = ""
    @State private var password = ""
    @State private var token = ""
    @State private var mode: CredentialMode = .password
    @State private var isBusy = false
    @State private var errorMessage: String?

    private enum CredentialMode: String, CaseIterable, Identifiable {
        case password
        case token

        var id: String { rawValue }

        var title: String {
            switch self {
            case .password: L10n.string("ui.melody.login.mode.password")
            case .token: L10n.string("ui.melody.login.mode.token")
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("ui.melody.login.mode", selection: $mode) {
                    ForEach(CredentialMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                TextField("ui.melody.login.server", text: $server)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } footer: {
                Text("ui.melody.login.server.footer")
            }

            Section {
                switch mode {
                case .password:
                    SecureField("ui.melody.login.password", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                case .token:
                    TextField("ui.melody.login.token", text: $token, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(2...4)
                        .font(.footnote.monospaced())
                }
            } footer: {
                if let errorMessage {
                    Text(verbatim: errorMessage)
                        .foregroundStyle(.red)
                } else {
                    Text(
                        mode == .password
                            ? "ui.melody.login.password.footer"
                            : "ui.melody.login.token.footer"
                    )
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if isBusy {
                            ProgressView()
                        } else {
                            Text("ui.settings.account.login")
                                .font(.body.weight(.semibold))
                        }
                        Spacer()
                    }
                }
                .disabled(isBusy || !canSubmit)
            }
        }
        .navigationTitle("ui.settings.account.login")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("ui.common.cancel", role: .cancel) {
                    dismiss()
                }
            }
        }
        .onAppear {
            if server.isEmpty {
                server = settings.melodyServerURL.isEmpty
                    ? MelodyClient.defaultServerURL
                    : settings.melodyServerURL
            }
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .password:
            !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .token:
            !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func submit() async {
        isBusy = true
        errorMessage = nil
        let trimmedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.melodyServerURL = trimmedServer == MelodyClient.defaultServerURL
            ? ""
            : trimmedServer

        let client = MelodyClient(settings: settings)
        do {
            switch mode {
            case .password:
                try await client.login(password: password)
            case .token:
                try await client.useToken(token)
            }
            await library.refresh(force: true)
            isBusy = false
            dismiss()
        } catch {
            isBusy = false
            errorMessage = error.localizedDescription
        }
    }
}

/// 上游用它清理网易云网页登录 cookie。音源换掉之后已经没有网页登录了，
/// 但登出流程仍在调用 `clear()`，保留这个空实现比到处删调用点安全。
@MainActor
enum NeteaseWebCookieStore {
    private static let dataStore = WKWebsiteDataStore.default()

    static func makePage() -> WebPage {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore
        configuration.defaultNavigationPreferences.preferredContentMode = .desktop
        return WebPage(configuration: configuration)
    }

    static func authenticatedCookieHeader() async -> String? {
        nil
    }

    static func clear() async {
        for cookie in await allCookies() where isNeteaseCookie(cookie) {
            await dataStore.httpCookieStore.deleteCookie(cookie)
        }
    }

    private static func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private static func isNeteaseCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return domain == "163.com" || domain.hasSuffix(".163.com")
    }
}
