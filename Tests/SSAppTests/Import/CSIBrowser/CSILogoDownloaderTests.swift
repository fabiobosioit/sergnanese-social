import Foundation
import SSCore
import Testing

@testable import SSApp

struct CSILogoDownloaderTests {
  static let logo = "https://static.centrosportivoitaliano.it/modulistica/logo/90000104_202609011200.jpg"

  func make(_ handler: @escaping @Sendable (URLRequest) -> CSIStubReply?) -> (CSILogoDownloader, CSIStubServer) {
    let server = CSIStubServer(handler: handler)
    return (CSILogoDownloader(configuration: server.configuration(), userAgent: "SergnaneseSocial/test"), server)
  }

  func failure(_ downloader: CSILogoDownloader, _ url: String) async -> CSILogoDownloader.Failure? {
    do {
      _ = try await downloader.download(URL(string: url)!)
      return nil
    } catch let error as CSILogoDownloader.Failure {
      return error
    } catch {
      return .network
    }
  }

  @Test func downloadsAJPEGFromTheLogoHost() async throws {
    let (downloader, server) = make { request in
      request.url?.absoluteString == Self.logo ? .image("image/jpeg") : nil
    }
    let data = try await downloader.download(URL(string: Self.logo)!)
    #expect(data == CSIStubServer.tinyImage)
    #expect(server.unexpected.isEmpty)
    #expect(server.requests.count == 1)
    #expect(server.requests.first?.headers["User-Agent"] == "SergnaneseSocial/test")
  }

  @Test(arguments: ["image/png", "image/jpeg", "image/webp", "IMAGE/JPEG; charset=binary"])
  func acceptsTheThreeImageTypes(_ type: String) async throws {
    let (downloader, server) = make { _ in .image(type) }
    _ = try await downloader.download(URL(string: Self.logo)!)
    #expect(server.unexpected.isEmpty)
  }

  @Test func anotherHostIsRefusedBeforeAnyRequest() async {
    let (downloader, server) = make { _ in .image() }
    for url in [
      "https://www.example.org/logo.jpg", "https://live.centrosportivoitaliano.it/logo.jpg",
      "https://cdncsi.csi-net.it/risultati/img_2/csi-shield-b.svg",
      "https://static.centrosportivoitaliano.it.evil.example/logo.jpg",
      "https://user:pw@static.centrosportivoitaliano.it/logo.jpg",
      "https://static.centrosportivoitaliano.it:8443/logo.jpg",
    ] {
      #expect(await failure(downloader, url) == .notAllowed, "\(url)")
    }
    #expect(server.requests.isEmpty)
  }

  @Test func httpIsRefusedBeforeAnyRequest() async {
    let (downloader, server) = make { _ in .image() }
    let url = "http://static.centrosportivoitaliano.it/modulistica/logo/90000104_1.jpg"
    #expect(await failure(downloader, url) == .notAllowed)
    #expect(await failure(downloader, "file:///etc/passwd") == .notAllowed)
    #expect(server.requests.isEmpty)
  }

  @Test func aRedirectOffTheHostIsRefusedAndNeverFollowed() async {
    let (downloader, server) = make { request in
      request.url?.absoluteString == Self.logo ? .redirect(to: "https://www.example.org/logo.jpg") : nil
    }
    #expect(await failure(downloader, Self.logo) == .notAllowed)
    #expect(server.requestedURLs == [Self.logo])
    #expect(server.unexpected.isEmpty)
  }

  @Test func aRedirectToHTTPIsRefused() async {
    let (downloader, server) = make { request in
      request.url?.absoluteString == Self.logo
        ? .redirect(to: "http://static.centrosportivoitaliano.it/modulistica/logo/90000104_2.jpg") : nil
    }
    #expect(await failure(downloader, Self.logo) == .notAllowed)
    #expect(server.requestedURLs == [Self.logo])
  }

  @Test func aRedirectOnTheSameHostIsFollowed() async throws {
    let second = "https://static.centrosportivoitaliano.it/modulistica/logo/90000104_202610010000.jpg"
    let (downloader, server) = make { request in
      switch request.url?.absoluteString {
      case Self.logo: .redirect(to: second)
      case second: .image()
      default: nil
      }
    }
    let data = try await downloader.download(URL(string: Self.logo)!)
    #expect(data == CSIStubServer.tinyImage)
    #expect(server.requestedURLs == [Self.logo, second])
  }

  @Test func overFiveMegabytesIsRefused() async {
    let big = Data(repeating: 1, count: CSILogoDownloader.maxBytes + 1)
    let (downloader, _) = make { _ in .image(body: big) }
    #expect(await failure(downloader, Self.logo) == .tooLarge)
    let exact = Data(repeating: 1, count: CSILogoDownloader.maxBytes)
    let (okDownloader, _) = make { _ in .image(body: exact) }
    #expect(await failure(okDownloader, Self.logo) == nil)
  }

  @Test func otherContentTypesAreRefused() async {
    for type in ["text/html", "image/svg+xml", "application/octet-stream", ""] {
      let (downloader, _) = make { _ in .ok(headers: type.isEmpty ? [:] : ["Content-Type": type], body: Data("x".utf8))
      }
      #expect(await failure(downloader, Self.logo) == .wrongType, "\(type)")
    }
  }

  @Test func aBadStatusIsRefused() async {
    let (downloader, _) = make { _ in .ok(status: 403, headers: ["Content-Type": "text/html"]) }
    #expect(await failure(downloader, Self.logo) == .status(403))
  }

  @Test func noCookiesAreSentOrKept() async throws {
    let cookieStorage = HTTPCookieStorage.shared
    let cookie = HTTPCookie(properties: [
      .domain: "static.centrosportivoitaliano.it", .path: "/", .name: "cf_clearance", .value: "secret",
    ])!
    cookieStorage.setCookie(cookie)
    defer { cookieStorage.deleteCookie(cookie) }
    let (downloader, server) = make { _ in
      .ok(headers: ["Content-Type": "image/png", "Set-Cookie": "a=b; Path=/"], body: CSIStubServer.tinyImage)
    }
    _ = try await downloader.download(URL(string: Self.logo)!)
    #expect(server.requests.count == 1)
    #expect(server.requests.first?.headers["Cookie"] == nil)
    #expect(server.requests.first?.headers["Authorization"] == nil)
    #expect(server.unexpected.isEmpty)
  }
}
