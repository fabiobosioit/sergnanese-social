import Foundation
import SSCore
import Testing

@testable import SSRender

/// The custom scheme only serves the page, files inside the template folder and logos.
@Suite struct TemplateSiteTests {
  let root: URL
  let site: TemplateSite

  init() throws {
    root = try makeTemporaryFolder("TemplateSiteTests")
    let template = root.appendingPathComponent("template", isDirectory: true)
    let logos = root.appendingPathComponent("logos", isDirectory: true)
    try FixtureTemplates.write(
      folder: template, files: ["template.html": "raw {{mustache}}", "assets/a.css": "body{}", ".hidden": "x"])
    try FixtureTemplates.write(folder: logos, files: ["team.png": "png"])
    try FixtureTemplates.write(folder: root, files: ["secret.txt": "secret"])
    try FileManager.default.createSymbolicLink(
      at: template.appendingPathComponent("assets/link.txt"),
      withDestinationURL: root.appendingPathComponent("secret.txt"))
    site = TemplateSite(host: "page7", page: Data("page".utf8), templateFolder: template, logosFolder: logos)
  }

  func resolve(_ text: String) -> TemplateSite.Resource {
    guard let url = URL(string: text) else { return .notFound }
    return site.resolve(url)
  }

  @Test func servesPageFilesAndLogos() {
    #expect(resolve("ss-template://page7/template.html") == .page)
    #expect(resolve("ss-template://page7/") == .page)
    guard case .file(let css) = resolve("ss-template://page7/assets/a.css") else {
      Issue.record("css not served")
      return
    }
    #expect(css.lastPathComponent == "a.css")
    guard case .file(let logo) = resolve("ss-template://page7/_logos/team.png") else {
      Issue.record("logo not served")
      return
    }
    #expect(logo.lastPathComponent == "team.png")
    #expect(site.pageURL.absoluteString == "ss-template://page7/template.html")
  }

  @Test func refusesEverythingElse() {
    let refused = [
      "ss-template://other/assets/a.css",  // another host (an older page)
      "https://page7/assets/a.css",
      "ss-template://page7/../secret.txt",
      "ss-template://page7/%2E%2E/secret.txt",
      "ss-template://page7/assets/%2e%2e/%2e%2e/secret.txt",
      "ss-template://page7/assets/..%2F..%2Fsecret.txt",
      "ss-template://page7/_logos/../secret.txt",
      "ss-template://page7/_logos/%2E%2E%2Fsecret.txt",
      "ss-template://page7/_logos/sub/team.png",
      "ss-template://page7/.hidden",
      "ss-template://page7/assets",  // a directory
      "ss-template://page7/missing.png",
      "ss-template://page7/assets/link.txt",  // symbolic link pointing outside the folder
      "ss-template://page7/assets%5C..%5C..%5Csecret.txt",
    ]
    for url in refused {
      #expect(resolve(url) == .notFound, "\(url)")
    }
  }

  @Test func noLogosFolderServesNoLogos() {
    var withoutLogos = site
    withoutLogos.logosFolder = nil
    #expect(withoutLogos.resolve(URL(string: "ss-template://page7/_logos/team.png")!) == .notFound)
  }

  @Test func mimeTypes() {
    #expect(TemplateSite.mimeType(for: URL(fileURLWithPath: "/a/b.woff2")) == "font/woff2")
    #expect(TemplateSite.mimeType(for: URL(fileURLWithPath: "/a/b.CSS")) == "text/css")
    #expect(TemplateSite.mimeType(for: URL(fileURLWithPath: "/a/b.svg")) == "image/svg+xml")
  }
}
