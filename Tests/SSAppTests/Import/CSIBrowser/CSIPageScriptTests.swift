import Foundation
import Testing
import WebKit

@testable import SSApp

/// The scripts run in a real web view on a local page. No network: images are `data:` addresses.
@MainActor
struct CSIPageScriptTests {
  static let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4])

  func read(_ page: CSITestPage, max: Int = CSIPageScripts.maxHTMLBytes) async -> CSIScriptOutcome {
    await CSIPageScripts.run(
      CSIPageScripts.readHTML, arguments: ["max": max], in: page.webView, timeout: .seconds(10))
  }

  func fetch(_ page: CSITestPage, _ url: String, max: Int = CSIPageScripts.maxLogoBytes) async -> CSIScriptOutcome {
    await CSIPageScripts.run(
      CSIPageScripts.fetchImage, arguments: ["url": url, "max": max], in: page.webView, timeout: .seconds(10))
  }

  // MARK: Reading the page

  @Test func readsTheRenderedDocument() async {
    let page = await CSITestPage(
      html:
        "<html><body><p id='x'>ciao</p><script>document.getElementById('x').textContent='cambiato'</script></body></html>"
    )
    guard case .reply(let reply) = await read(page), let html = reply.value else {
      Issue.record("no answer")
      return
    }
    // The page after its scripts ran, which is what the parser needs.
    #expect(html.contains("cambiato"))
    #expect(html.hasPrefix("<html"))
    #expect(CSIPageReader.interpret(.reply(reply)) == .success(html))
  }

  @Test func aPageOverTheCapIsTooLargeBeforeItLeavesThePage() async {
    let page = await CSITestPage(html: "<html><body>\(String(repeating: "x", count: 5000))</body></html>")
    let outcome = await read(page, max: 1000)
    #expect(outcome == .reply(CSIScriptReply(reason: "tooLarge")))
    #expect(CSIPageReader.interpret(outcome) == .failure(.tooLarge))
  }

  @Test func aScriptErrorIsAFailure() async {
    let page = await CSITestPage(html: "<html></html>")
    let outcome = await CSIPageScripts.run(
      "throw new Error('boom');", arguments: [:], in: page.webView, timeout: .seconds(10))
    #expect(outcome == .failed)
    #expect(CSIPageReader.interpret(outcome) == .failure(.failed))
  }

  @Test func aScriptThatReturnsNothingIsAFailure() async {
    let page = await CSITestPage(html: "<html></html>")
    let outcome = await CSIPageScripts.run("return null;", arguments: [:], in: page.webView, timeout: .seconds(10))
    #expect(outcome == .failed)
  }

  @Test func aScriptThatNeverAnswersTimesOut() async {
    let page = await CSITestPage(html: "<html></html>")
    let outcome = await CSIPageScripts.run(
      "await new Promise(() => {}); return { value: 'x' };", arguments: [:], in: page.webView,
      timeout: .milliseconds(150))
    #expect(outcome == .timedOut)
    #expect(CSIPageReader.interpret(outcome) == .failure(.failed))
  }

  @Test func aCancelledTaskReturnsAtOnce() async {
    let page = await CSITestPage(html: "<html></html>")
    let webView = page.webView
    let task = Task { @MainActor in
      await CSIPageScripts.run(
        "await new Promise(() => {}); return { value: 'x' };", arguments: [:], in: webView, timeout: .seconds(30))
    }
    try? await Task.sleep(for: .milliseconds(100))
    task.cancel()
    #expect(await task.value == .failed)
  }

  @Test func theScriptsRunInTheClientWorldAndTheArgumentsAreValuesNotCode() async {
    let page = await CSITestPage(html: "<html><body></body></html>")
    // A page script defines a global; the client world does not see it.
    _ = try? await page.webView.evaluateJavaScript("window.pageSecret = 42")
    let outcome = await CSIPageScripts.run(
      "return { value: String(typeof window.pageSecret) + '|' + text };",
      arguments: ["text": "'; window.pwned = true; '"], in: page.webView, timeout: .seconds(10))
    #expect(outcome == .reply(CSIScriptReply(value: "undefined|'; window.pwned = true; '")))
    let pwned = try? await page.webView.evaluateJavaScript("typeof window.pwned") as? String
    #expect(pwned == "undefined")
  }

  @Test func theWebViewHasNoMessageHandlerBridge() async {
    let page = await CSITestPage(html: "<html></html>")
    let kind =
      try? await page.webView.evaluateJavaScript(
        "typeof (window.webkit && window.webkit.messageHandlers)") as? String
    #expect(kind == "undefined")
  }

  // MARK: Reading an image in the page

  @Test func readsAnImageAsBase64() async {
    let page = await CSITestPage(html: "<html></html>")
    let url = "data:image/png;base64," + Self.pngBytes.base64EncodedString()
    guard case .reply(let reply) = await fetch(page, url), let base64 = reply.value else {
      Issue.record("no answer")
      return
    }
    #expect(CSILogoBytes.decode(base64: base64) == Self.pngBytes)
  }

  @Test func refusesWhatIsNotAnImage() async {
    let page = await CSITestPage(html: "<html></html>")
    let text = "data:text/html;base64," + Data("<h1>x</h1>".utf8).base64EncodedString()
    #expect(await fetch(page, text) == .reply(CSIScriptReply(reason: "type")))
    let plain = "data:text/plain;base64," + Data("x".utf8).base64EncodedString()
    #expect(await fetch(page, plain) == .reply(CSIScriptReply(reason: "type")))
  }

  @Test func refusesAnImageOverTheCap() async {
    let page = await CSITestPage(html: "<html></html>")
    let url = "data:image/png;base64," + Data(repeating: 9, count: 600).base64EncodedString()
    #expect(await fetch(page, url, max: 500) == .reply(CSIScriptReply(reason: "tooLarge")))
    #expect(await fetch(page, url, max: 600) != .reply(CSIScriptReply(reason: "tooLarge")))
  }

  @Test func aFailedRequestIsAFailure() async {
    let page = await CSITestPage(html: "<html></html>")
    #expect(await fetch(page, "not a url at all") == .failed)
  }
}
