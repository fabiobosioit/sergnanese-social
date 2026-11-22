import Foundation
import Testing

@testable import SSCore

@Suite struct TuttocampoTests {
  let widgetID = "00000000-0000-4000-8000-000000000001"

  @Test func widgetIDShape() {
    #expect(isValidTuttocampoWidgetID(widgetID))
    #expect(isValidTuttocampoWidgetID("C1E4E5C7-493E-46D6-B5A6-B53E6730900C"))
    for bad in [
      "", "0000000-0000-4000-8000-000000000001", "00000000-0000-4000-8000-00000000000g",
      "00000000000040008000000000000001", "00000000-0000-4000-8000-000000000001/", "../../etc/passwd",
      " 00000000-0000-4000-8000-000000000001",
    ] {
      #expect(!isValidTuttocampoWidgetID(bad), "\(bad)")
    }
  }

  @Test func widgetIDFromPastedText() {
    #expect(tuttocampoWidgetID(from: "  \(widgetID)\n") == widgetID)
    #expect(tuttocampoWidgetID(from: "https://www.tuttocampo.it/WidgetV2/Risultati/\(widgetID)") == widgetID)
    #expect(tuttocampoWidgetID(from: "https://www.tuttocampo.it/WidgetV2/Classifica/\(widgetID)") == widgetID)
    #expect(
      tuttocampoWidgetID(from: "https://www.tuttocampo.it/WidgetV2/Risultati/\(widgetID)/10?y=2026-27") == widgetID)
    #expect(tuttocampoWidgetID(from: "www.tuttocampo.it/WidgetV2/Risultati/\(widgetID)") == widgetID)
    #expect(
      tuttocampoWidgetID(from: "https://www.tuttocampo.it/WidgetV2/Risultati/ABCDEF00-0000-4000-8000-000000000001")
        == "ABCDEF00-0000-4000-8000-000000000001")
    #expect(tuttocampoWidgetID(from: "https://example.com/WidgetV2/Risultati/\(widgetID)") == nil)
    #expect(tuttocampoWidgetID(from: "https://www.tuttocampo.it/WidgetV2/Risultati/") == nil)
    #expect(tuttocampoWidgetID(from: "https://www.tuttocampo.it/Lombardia/\(widgetID)") == nil)
    #expect(tuttocampoWidgetID(from: "ciao") == nil)
    #expect(tuttocampoWidgetID(from: "") == nil)
  }

  @Test func clubIDFromLogoURL() throws {
    func clubID(_ text: String) throws -> String? { tuttocampoClubID(fromLogoURL: try #require(URL(string: text))) }
    #expect(try clubID("https://b2-content.tuttocampo.it/Teams/40/917410.png?v=2") == "917410")
    #expect(try clubID("https://b2-content.tuttocampo.it/Teams/80/917410.png?v=9") == "917410")
    #expect(try clubID("https://b2-content.tuttocampo.it/Teams/200/1032395.png") == "1032395")
    #expect(try clubID("https://b2-content.tuttocampo.it/Teams/Original/917410.jpg") == "917410")
    #expect(try clubID("http://B2-CONTENT.tuttocampo.it/Teams/40/917410.png") == "917410")
    for bad in [
      "https://b-static.tuttocampo.it/Teams/40/917410.png",  // other host
      "https://b2-content.tuttocampo.it.evil.example/Teams/40/917410.png",
      "https://b2-content.tuttocampo.it/Web/Images/watermark.png",  // UI image
      "https://b2-content.tuttocampo.it/Teams/917410.png",  // no size folder
      "https://b2-content.tuttocampo.it/Teams/40/x/917410.png",  // extra segment
      "https://b2-content.tuttocampo.it/teams/40/917410.png",  // case of Teams
      "https://b2-content.tuttocampo.it/Teams/40/9174a10.png",  // not digits
      "https://b2-content.tuttocampo.it/Teams/40/917410",  // no extension
      "https://b2-content.tuttocampo.it/Teams/40/917410.",  // empty extension
      "https://b2-content.tuttocampo.it/Teams/40/1234567890123456.png",  // too long
      "ftp://b2-content.tuttocampo.it/Teams/40/917410.png",
      "file:///Teams/40/917410.png",
    ] {
      #expect(try clubID(bad) == nil, "\(bad)")
    }
  }

  @Test func logoURLAndFileName() {
    #expect(
      tuttocampoLogoURL(clubID: "917410")?.absoluteString == "https://b2-content.tuttocampo.it/Teams/200/917410.png")
    #expect(tuttocampoLogoURL(clubID: "") == nil)
    #expect(tuttocampoLogoURL(clubID: "91/7410") == nil)
    #expect(tuttocampoLogoURL(clubID: "１２３") == nil)  // full-width digits are not ASCII
    #expect(tuttocampoLogoFileName(clubID: "917410") == "917410.png")
    #expect(tuttocampoLogoFileName(clubID: "../917410") == nil)
  }

  @Test func importedLogoFileNames() {
    #expect(isValidImportedLogoFileName("917410.png"))
    #expect(isValidImportedLogoFileName("1.png"))
    for bad in [
      "", ".png", "917410.PNG", "917410.jpg", "917410", "../917410.png", "/917410.png", "91 7410.png",
      "abc.png", "\(UUID().uuidString.lowercased()).png", "1234567890123456.png",
    ] {
      #expect(!isValidImportedLogoFileName(bad), "\(bad)")
    }
  }

  @Test func teamDraftWidgetID() {
    var draft = TeamDraft(name: "Juniores", shortLabel: "Juniores")
    draft.tuttocampoWidgetID = "  "
    #expect(draft.normalized().tuttocampoWidgetID == nil)
    draft.tuttocampoWidgetID = " https://www.tuttocampo.it/WidgetV2/Risultati/\(widgetID) "
    #expect(draft.normalized().tuttocampoWidgetID == widgetID)
    #expect(draft.normalized().validate().isEmpty)
    draft.tuttocampoWidgetID = " non è un id "
    let problems = draft.normalized().validate()
    #expect(problems.map(\.field) == [.tuttocampoWidgetID])
    #expect(problems.message(for: .tuttocampoWidgetID) == CoreStrings.invalidWidgetID)
    #expect(throws: AppError.self) { try draft.validated() }
  }

  @Test func teamCarriesTheWidgetID() throws {
    let team = Team(
      id: "t", name: "Juniores", shortLabel: "Jun", sortOrder: 1, isFirstTeam: false, isActive: true,
      tuttocampoWidgetID: widgetID)
    #expect(TeamDraft(team).tuttocampoWidgetID == widgetID)
    let data = try JSONEncoder().encode(team)
    #expect(try JSONDecoder().decode(Team.self, from: data) == team)
    // JSON written before T4.2 has no key and decodes as nil.
    let old = Data(
      #"{"id":"t","name":"Juniores","shortLabel":"Jun","sortOrder":1,"isFirstTeam":false,"isActive":true}"#.utf8)
    #expect(try JSONDecoder().decode(Team.self, from: old).tuttocampoWidgetID == nil)
  }

  @Test func widgetIDInUseError() {
    let error = AppError.widgetIDInUse(by: "Juniores")
    #expect(error == .validation(field: .tuttocampoWidgetID, message: CoreStrings.widgetIDInUse("Juniores")))
    #expect(error.errorDescription?.contains("Juniores") == true)
  }
}
