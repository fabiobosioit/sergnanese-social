import Foundation
import SSCore
import Testing

@testable import SSApp

struct CSIPageReaderTests {
  static let page =
    "https://live.centrosportivoitaliano.it/26/Calcio-a-11/Lombardia/Crema/C36048/G283123-girone-a-2016/"

  // MARK: Size cap and answers

  @Test func htmlAtTheCapIsKeptAndOneByteMoreIsTooLarge() {
    let cap = CSIPageScripts.maxHTMLBytes
    #expect(cap == 2 * 1024 * 1024)
    #expect(
      CSIPageReader.check(html: String(repeating: "a", count: cap)) == .success(String(repeating: "a", count: cap)))
    #expect(CSIPageReader.check(html: String(repeating: "a", count: cap + 1)) == .failure(.tooLarge))
  }

  @Test func theCapCountsUTF8BytesNotCharacters() {
    // "è" is two bytes: 1 MiB of them is exactly the cap, one more character is over it.
    let cap = CSIPageScripts.maxHTMLBytes
    #expect(
      CSIPageReader.check(html: String(repeating: "è", count: cap / 2))
        == .success(String(repeating: "è", count: cap / 2)))
    #expect(CSIPageReader.check(html: String(repeating: "è", count: cap / 2 + 1)) == .failure(.tooLarge))
  }

  @Test func answersMapToResults() {
    #expect(CSIPageReader.interpret(.reply(CSIScriptReply(value: "<html></html>"))) == .success("<html></html>"))
    #expect(CSIPageReader.interpret(.reply(CSIScriptReply(reason: "tooLarge"))) == .failure(.tooLarge))
    #expect(CSIPageReader.interpret(.reply(CSIScriptReply(reason: "empty"))) == .failure(.failed))
    #expect(CSIPageReader.interpret(.reply(CSIScriptReply(value: ""))) == .failure(.failed))
    #expect(CSIPageReader.interpret(.failed) == .failure(.failed))
    #expect(CSIPageReader.interpret(.timedOut) == .failure(.failed))
    let huge = String(repeating: "a", count: CSIPageScripts.maxHTMLBytes + 1)
    #expect(CSIPageReader.interpret(.reply(CSIScriptReply(value: huge))) == .failure(.tooLarge))
  }

  @Test func replyIsReadFromTheScriptResult() {
    #expect(CSIScriptReply(["value": "x"]) == CSIScriptReply(value: "x"))
    #expect(CSIScriptReply(["reason": "type"]) == CSIScriptReply(reason: "type"))
    #expect(CSIScriptReply(NSNull()) == nil)
    #expect(CSIScriptReply("text") == nil)
    #expect(CSIScriptReply([String: Any]()) == nil)
    #expect(CSIScriptReply(["value": 3]) == nil)
  }

  // MARK: Addresses

  @Test func canImportNeedsACSIPageThatIsNotLoading() {
    let url = URL(string: Self.page + "?j=abc")
    #expect(CSIPageReader.canImport(url: url, isLoading: false))
    #expect(!CSIPageReader.canImport(url: url, isLoading: true))
    #expect(!CSIPageReader.canImport(url: nil, isLoading: false))
    #expect(!CSIPageReader.canImport(url: URL(string: "https://challenges.cloudflare.com/cdn-cgi/x"), isLoading: false))
    #expect(!CSIPageReader.canImport(url: URL(string: "https://www.example.org/x"), isLoading: false))
    #expect(!CSIPageReader.canImport(url: URL(string: "http://live.centrosportivoitaliano.it/x"), isLoading: false))
    #expect(!CSIPageReader.canImport(url: URL(string: "https://live.centrosportivoitaliano.it/"), isLoading: false))
    #expect(!CSIPageReader.canImport(url: URL(string: "about:blank"), isLoading: false))
  }

  @Test func isOnTeamPageIgnoresTheQuery() {
    let saved = Self.page + "?j=abc"
    #expect(CSIPageReader.isOnTeamPage(url: URL(string: Self.page + "?j=other"), teamPage: saved))
    #expect(CSIPageReader.isOnTeamPage(url: URL(string: Self.page), teamPage: saved))
    let shouting = "https://LIVE.centrosportivoitaliano.it" + URL(string: Self.page)!.path.uppercased()
    #expect(CSIPageReader.isOnTeamPage(url: URL(string: shouting), teamPage: saved))
    // Another girone.
    let other = "https://live.centrosportivoitaliano.it/26/Calcio-a-11/Lombardia/Crema/C36048/G283124-girone-b-2016/"
    #expect(!CSIPageReader.isOnTeamPage(url: URL(string: other), teamPage: saved))
    // The challenge page, no page, no saved page.
    #expect(!CSIPageReader.isOnTeamPage(url: URL(string: "https://challenges.cloudflare.com/x"), teamPage: saved))
    #expect(!CSIPageReader.isOnTeamPage(url: nil, teamPage: saved))
    #expect(!CSIPageReader.isOnTeamPage(url: URL(string: Self.page), teamPage: nil))
  }

  // MARK: Logo bytes

  @Test func logoBase64IsDecodedAndCapped() {
    let bytes = Data([1, 2, 3, 4, 5])
    #expect(CSILogoBytes.decode(base64: bytes.base64EncodedString()) == bytes)
    #expect(CSILogoBytes.decode(base64: "") == nil)
    #expect(CSILogoBytes.decode(base64: "not base64!") == nil)
    let cap = 100
    #expect(CSILogoBytes.decode(base64: Data(repeating: 7, count: cap).base64EncodedString(), maxBytes: cap) != nil)
    #expect(CSILogoBytes.decode(base64: Data(repeating: 7, count: cap + 1).base64EncodedString(), maxBytes: cap) == nil)
    #expect(CSIPageScripts.maxLogoBytes == 5 * 1024 * 1024)
  }

  @Test func theBase64LengthIsCheckedBeforeDecoding() {
    let cap = 100
    let long = String(repeating: "A", count: 4000)
    #expect(CSILogoBytes.decode(base64: long, maxBytes: cap) == nil)
  }

  @Test func onlyHTTPAddressesAreReadable() {
    #expect(CSILogoBytes.isReadable(URL(string: "https://static.centrosportivoitaliano.it/modulistica/logo/1.jpg")!))
    #expect(CSILogoBytes.isReadable(URL(string: "http://static.centrosportivoitaliano.it/modulistica/logo/1.jpg")!))
    #expect(!CSILogoBytes.isReadable(URL(string: "data:image/png;base64,AAAA")!))
    #expect(!CSILogoBytes.isReadable(URL(string: "file:///etc/passwd")!))
    #expect(!CSILogoBytes.isReadable(URL(string: "javascript:alert(1)")!))
  }
}
