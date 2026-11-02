import Foundation

@main struct AppUpdateTests {
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw UserError(message) }
    }
    static func rejects(_ body: () throws -> Void) throws {
        do { try body() } catch { return }
        throw UserError("Invalid update was accepted")
    }
    static func main() async {
        do {
            try check(try AppVersion("1.9.9") < AppVersion("1.10.0"), "Updates must compare version components numerically")
            try check(try AppVersion("1.1.2") == AppVersion("1.1.2"), "Same version must not update")
            try check(try !(AppVersion("2.0.0") < AppVersion("1.99.99")), "Do not downgrade")
            for version in ["", "v1.2.3", "1.2", "1.2.3-beta", "1.-2.3", "1.2.999999999999999999999", "１.2.3"] {
                try rejects { _ = try AppVersion(version) }
            }
            print("PASS update version ordering and invalid versions")
            let packageName = "LocalRightClick-1.2.0-universal.pkg"
            let prefix = "https://github.com/liudongGITHUB/LocalRightClick/releases/download/v1.2.0/"
            let assets: [[String: Any]] = [
                ["name": packageName, "size": 8, "browser_download_url": prefix + packageName],
                ["name": "SHA256SUMS.txt", "size": 100, "browser_download_url": prefix + "SHA256SUMS.txt"]
            ]
            let metadata: [String: Any] = ["tag_name": "v1.2.0", "body": "Test notes", "draft": false, "prerelease": false, "assets": assets]
            func parse(_ fields: [String: Any]) throws -> AppRelease { try AppRelease.parse(JSONSerialization.data(withJSONObject: fields)) }
            let release = try parse(metadata)
            try check(try release.isNewer(than: "1.1.2"), "A newer release must be offered")
            try check(try !release.isNewer(than: "1.2.0") && !release.isNewer(than: "2.0.0"), "Same or older releases must not be offered")
            for key in ["draft", "prerelease"] {
                var bad = metadata; bad[key] = true
                try rejects { _ = try parse(bad) }
            }
            for badURL in [prefix.replacingOccurrences(of: "https:", with: "http:") + packageName,
                           "https://example.com/" + packageName, prefix + packageName + "?redirect=1",
                           prefix.replacingOccurrences(of: "v1.2.0", with: "v1.1.0") + packageName,
                           prefix.replacingOccurrences(of: "github.com", with: "github.com.evil.test") + packageName] {
                var badAssets = assets; badAssets[0]["browser_download_url"] = badURL
                var bad = metadata; bad["assets"] = badAssets
                try rejects { _ = try parse(bad) }
            }
            for badAssets in [Array(assets.dropFirst()), assets + [assets[0]],
                              [["name": packageName, "size": 134_217_729, "browser_download_url": prefix + packageName], assets[1]]] {
                var bad = metadata; bad["assets"] = badAssets
                try rejects { _ = try parse(bad) }
            }
            print("PASS release selection rejects drafts, incomplete assets and untrusted download URLs")

            let hash = "0f1fd6a4a69393cd1fe365b9d0d26a6301ca934c64a2da523815b7c330e8d7df"
            let manifest = "\(hash)  \(packageName)\n\(hash)  other.zip\n"
            try check(try UpdateDownload.checksum(for: packageName, in: Data(manifest.utf8)) == hash, "Checksum must match the exact package name")
            for bad in ["garbage  \(packageName)", "\(hash)  other.pkg", manifest + manifest] {
                try rejects { _ = try UpdateDownload.checksum(for: packageName, in: Data(bad.utf8)) }
            }
            print("PASS checksum manifest rejects missing, malformed and duplicate package checksums")

            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LRC-update-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent(packageName)
            try Data("xar!test".utf8).write(to: file)
            let download = UpdateDownload(file: file, size: 8, sha256: hash)
            try download.verify()
            try rejects { try UpdateDownload(file: file, size: 9, sha256: hash).verify() }
            let link = directory.appendingPathComponent("link.pkg")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
            try rejects { try UpdateDownload(file: link, size: 8, sha256: hash).verify() }
            try Data("xar!evil".utf8).write(to: file)
            try rejects { try download.verify() }
            print("PASS package verification detects corruption, wrong size and replaced symlinks")

            let api = URL(string: "https://github.com/liudongGITHUB/LocalRightClick/releases/latest/download/update.json")!
            try AppUpdateClient.validateResponse(HTTPURLResponse(url: api, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            for code in [302, 403, 404, 429, 500] {
                try rejects { try AppUpdateClient.validateResponse(HTTPURLResponse(url: api, statusCode: code, httpVersion: nil, headerFields: nil)!) }
            }
            try check(UpdateRedirectPolicy.allows(URL(string: "https://release-assets.githubusercontent.com/file?signature=abc")!), "GitHub asset redirects must work")
            for url in ["http://github.com/file", "https://example.com/file", "https://github.com.evil.test/file", "https://user:pass@github.com/file", "https://github.com:8080/file"] {
                try check(!UpdateRedirectPolicy.allows(URL(string: url)!), "Unsafe redirect accepted")
            }
            print("PASS update HTTP failures and unsafe redirects are rejected")

            if let option = CommandLine.arguments.firstIndex(of: "--release-directory"), option + 1 < CommandLine.arguments.count {
                let directory = URL(fileURLWithPath: CommandLine.arguments[option + 1])
                let release = try AppRelease.parse(Data(contentsOf: directory.appendingPathComponent("update.json")))
                let checksums = try Data(contentsOf: directory.appendingPathComponent("SHA256SUMS.txt"))
                let hash = try UpdateDownload.checksum(for: release.packageName, in: checksums)
                try UpdateDownload(file: directory.appendingPathComponent(release.packageName), size: release.asset(named: release.packageName).size, sha256: hash).verify()
                print("PASS generated release manifest matches the actual verified package")
            }
            let metadataOption = CommandLine.arguments.firstIndex(of: "--release-json")
            if CommandLine.arguments.contains("--live") || metadataOption != nil {
                let client = AppUpdateClient()
                let latest: AppRelease
                if let index = metadataOption, index + 1 < CommandLine.arguments.count {
                    latest = try AppRelease.parse(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1])))
                } else { latest = try await client.latest() }
                let package = try await client.download(latest)
                try package.verify()
                print("PASS live GitHub check, download and SHA-256 verification: \(latest.tagName)")
                try FileManager.default.removeItem(at: package.file.deletingLastPathComponent())
            }
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
