import Foundation
import CryptoKit

struct AppVersion: Comparable {
    let parts: [Int]
    init(_ value: String) throws {
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy({ (48...57).contains($0) }) }),
              pieces.allSatisfy({ Int($0) != nil }) else { throw UserError("版本号格式无效。") }
        parts = pieces.map { Int($0)! }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

struct AppRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let size: Int
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey { case name, size; case browserDownloadURL = "browser_download_url" }
    }
    let tagName: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    enum CodingKeys: String, CodingKey { case body, draft, prerelease, assets; case tagName = "tag_name" }
    var version: String { String(tagName.dropFirst()) }
    var packageName: String { "LocalRightClick-\(version)-universal.pkg" }

    static func parse(_ data: Data) throws -> Self {
        let release = try JSONDecoder().decode(Self.self, from: data)
        try release.validate()
        return release
    }
    func validate() throws {
        guard !draft, !prerelease, tagName.hasPrefix("v") else { throw UserError("更新信息不是正式发布版本。") }
        _ = try AppVersion(version)
        _ = try asset(named: packageName)
        _ = try asset(named: "SHA256SUMS.txt")
    }
    func isNewer(than current: String) throws -> Bool {
        try validate()
        return try AppVersion(current) < AppVersion(version)
    }
    func asset(named name: String) throws -> Asset {
        let matches = assets.filter { $0.name == name }
        guard matches.count == 1, let asset = matches.first else { throw UserError("新版安装包或校验文件尚未准备好，请稍后再试。") }
        let url = asset.browserDownloadURL
        let limit = name == "SHA256SUMS.txt" ? 65_536 : 134_217_728
        guard asset.size > 0, asset.size <= limit,
              url.scheme == "https", url.host == "github.com", url.port == nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path == "/liudongGITHUB/LocalRightClick/releases/download/\(tagName)/\(name)" else {
            throw UserError("更新下载地址或文件大小不符合预期，已停止更新。")
        }
        return asset
    }
}

struct UpdateDownload {
    let file: URL
    let size: Int
    let sha256: String

    static func checksum(for filename: String, in data: Data) throws -> String {
        guard data.count <= 65_536, let text = String(data: data, encoding: .utf8) else { throw UserError("更新校验文件无效。") }
        let matches = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { return nil }
            let name = parts[1].trimmingCharacters(in: .whitespaces)
            guard name == filename || name == "*" + filename else { return nil }
            return String(parts[0]).lowercased()
        }
        guard matches.count == 1, let hash = matches.first, hash.utf8.count == 64,
              hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw UserError("找不到安装包的有效 SHA-256 校验值。")
        }
        return hash
    }
    func verify() throws {
        let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, size > 0, size <= 134_217_728,
              info.fileSize == size else { throw UserError("安装包大小不符或文件已改变，请重新下载。") }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.starts(with: [0x78, 0x61, 0x72, 0x21]), hash == sha256 else {
            throw UserError("安装包校验失败，请重新下载。")
        }
    }
}

final class UpdateRedirectPolicy: NSObject, URLSessionTaskDelegate {
    static func allows(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443) &&
            ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url.host ?? "")
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(Self.allows) == true ? request : nil)
    }
}

struct AppUpdateClient {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForResource = 180
        session = URLSession(configuration: configuration, delegate: UpdateRedirectPolicy(), delegateQueue: nil)
    }
    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("LocalRightClick-Updater", forHTTPHeaderField: "User-Agent")
        return request
    }
    static func validateResponse(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse, let url = response.url, UpdateRedirectPolicy.allows(url) else {
            throw UserError("更新服务器响应无效。")
        }
        if response.statusCode == 403 || response.statusCode == 429 { throw UserError("GitHub 暂时限制了访问，请稍后重试。") }
        guard response.statusCode == 200 else { throw UserError("更新请求失败（HTTP \(response.statusCode)），请稍后重试。") }
    }
    func latest() async throws -> AppRelease {
        let url = URL(string: "https://github.com/liudongGITHUB/LocalRightClick/releases/latest/download/update.json")!
        var request = request(url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.validateResponse(response)
        guard data.count <= 2_000_000 else { throw UserError("更新信息过大，已停止检查。") }
        return try AppRelease.parse(data)
    }
    func download(_ release: AppRelease) async throws -> UpdateDownload {
        try release.validate()
        let asset = try release.asset(named: release.packageName)
        let checksumAsset = try release.asset(named: "SHA256SUMS.txt")
        let (checksums, response) = try await session.data(for: request(checksumAsset.browserDownloadURL))
        try Self.validateResponse(response)
        let hash = try UpdateDownload.checksum(for: asset.name, in: checksums)
        let (temporary, packageResponse) = try await session.download(for: request(asset.browserDownloadURL))
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Self.validateResponse(packageResponse)
        try UpdateDownload(file: temporary, size: asset.size, sha256: hash).verify()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LocalRightClick-Update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let file = directory.appendingPathComponent(asset.name)
            try FileManager.default.moveItem(at: temporary, to: file)
            return UpdateDownload(file: file, size: asset.size, sha256: hash)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
