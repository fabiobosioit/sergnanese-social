import Foundation
import Testing

@testable import SSCore

@Suite struct TemplateManifestTests {
  func decode(_ json: String) throws -> TemplateManifest { try TemplateManifest.decode(from: Data(json.utf8)) }

  func problems(_ json: String) -> [String] {
    do {
      _ = try decode(json)
      return []
    } catch AppError.template(let problems) {
      return problems
    } catch {
      return ["unexpected \(error)"]
    }
  }

  @Test func decodesTheDocumentedExample() throws {
    let manifest = try decode(
      """
      {
        "id": "post-prematch", "name": "Post · Pre-partita", "version": "1.0.0", "format": "post",
        "width": 1080, "height": 1350, "kind": "single", "purpose": "prematch", "pageSize": null,
        "requires": ["time", "venue"], "limits": { "teamName": 16, "venue": 14, "category": 22 },
        "description": "unknown top-level keys are ignored"
      }
      """)
    #expect(manifest.id == "post-prematch")
    #expect(manifest.format == .post && manifest.kind == .single && manifest.purpose == .prematch)
    #expect(manifest.width == 1080 && manifest.height == 1350)
    #expect(manifest.pageSize == nil)
    #expect(manifest.requires == [.time, .venue])
    #expect(manifest.limits == TemplateLimits(teamName: 16, venue: 14, category: 22))
  }

  @Test func decodesAListTemplateWithOptionalFieldsMissing() throws {
    let manifest = try decode(
      """
      {"id":"story-programme","name":"Programma","version":"1.2.10","format":"story","width":1080,
       "height":1920.0,"kind":"list","purpose":"programme","pageSize":10}
      """)
    #expect(manifest.pageSize == 10 && manifest.height == 1920)
    #expect(manifest.requires.isEmpty && manifest.limits == TemplateLimits())
  }

  @Test func reportsEveryProblemInItalian() {
    let found = problems(
      """
      {"id":"Bad ID","version":"1.0","format":"square","width":"1080","height":0,"kind":"list",
       "purpose":"prematch","requires":["time","colour"],"limits":{"teamname":16,"venue":-1}}
      """)
    #expect(
      found.contains("manifest.id può contenere solo lettere minuscole, cifre e trattini (al massimo 64 caratteri)."))
    #expect(found.contains("manifest.name manca."))
    #expect(found.contains("manifest.version deve avere la forma 1.0.0."))
    #expect(found.contains("manifest.format deve essere uno di: post, story."))
    #expect(found.contains("manifest.width deve essere un numero intero."))
    #expect(found.contains("manifest.height deve essere un numero intero da 100 a 4096."))
    #expect(found.contains("manifest.pageSize è obbligatorio per i template di tipo list."))
    #expect(found.contains { $0.hasPrefix("manifest.requires contiene «colour»") })
    #expect(found.contains { $0.hasPrefix("manifest.limits.teamname non è previsto") })
    #expect(found.contains("manifest.limits.venue deve essere un numero intero maggiore di zero."))
    #expect(found.count == 10)
  }

  @Test func rejectsNonObjectsAndBooleans() {
    #expect(problems("[1,2]") == ["manifest.json non è un oggetto JSON valido."])
    #expect(problems("not json") == ["manifest.json non è un oggetto JSON valido."])
    let found = problems(
      """
      {"id":"a","name":"A","version":"1.0.0","format":"post","width":true,"height":1350,"kind":"single","purpose":"other"}
      """)
    #expect(found == ["manifest.width deve essere un numero intero."])
  }

  @Test func singleTemplatesIgnorePageSize() throws {
    let manifest = try decode(
      """
      {"id":"a","name":"A","version":"1.0.0","format":"post","width":1080,"height":1350,"kind":"single",
       "purpose":"other","pageSize":5}
      """)
    #expect(manifest.pageSize == nil)
  }

  @Test func encodesBackToTheSameManifest() throws {
    let manifest = TemplateManifest(
      id: "story-programme", name: "Programma", version: "1.0.0", format: .story, width: 1080, height: 1920,
      kind: .list, purpose: .programme, pageSize: 10, requires: [.time], limits: TemplateLimits(teamName: 22))
    let data = try JSONEncoder().encode(manifest)
    #expect(try TemplateManifest.decode(from: data) == manifest)
  }

  @Test(arguments: [
    (TemplateKind.list, TemplatePurpose.fulltime, true), (.list, .programme, false), (.single, .fulltime, false),
    (.single, .prematch, false),
  ])
  func resultsRecapIsAListWithPurposeFulltime(_ kind: TemplateKind, _ purpose: TemplatePurpose, _ expected: Bool) {
    let manifest = TemplateManifest(
      id: "t", name: "T", version: "1.0.0", format: .story, width: 1080, height: 1920, kind: kind, purpose: purpose,
      pageSize: kind == .list ? 10 : nil)
    #expect(manifest.isResultsRecap == expected)
  }

  @Test func templateIDs() {
    #expect(isValidTemplateID("post-prematch"))
    #expect(isValidTemplateID("story2"))
    #expect(!isValidTemplateID("-lead"))
    #expect(!isValidTemplateID("Upper"))
    #expect(!isValidTemplateID("with space"))
    #expect(!isValidTemplateID("../escape"))
    #expect(!isValidTemplateID(""))
    #expect(!isValidTemplateID("città"))
  }

  @Test func versionsCompareNumerically() {
    #expect(compareTemplateVersions("1.10.0", "1.9.0") == .orderedDescending)
    #expect(compareTemplateVersions("1.0.0", "1.0.0") == .orderedSame)
    #expect(compareTemplateVersions("0.9.9", "1.0.0") == .orderedAscending)
    #expect(compareTemplateVersions("garbage", "0.0.1") == .orderedAscending)
  }
}
