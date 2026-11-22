import Foundation
import SSCore

/// `Tests/Fixtures/tuttocampo/<name>.html`, located from this file.
func tuttocampoFixture(_ name: String) throws -> String {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/tuttocampo/\(name).html")
  return try String(contentsOf: url, encoding: .utf8)
}

func day(_ text: String) -> DayDate {
  guard let date = try? DayDate(text) else { fatalError("bad test date \(text)") }
  return date
}

func clock(_ text: String) -> ClockTime {
  guard let time = try? ClockTime(text) else { fatalError("bad test time \(text)") }
  return time
}

let testWidgetPage = URL(string: "https://www.tuttocampo.it/WidgetV2/Risultati/00000000-0000-4000-8000-000000000001")!

let testSettings = ClubSettings(
  clubName: "ASD Sergnanese", clubShortName: "Sergnanese", season: "2026/27", accentColor: "#CF3326",
  socialHandle: "", homeVenue: "Campo comunale")

func testTeam(widgetID: String?) -> Team {
  Team(
    id: "team-1", name: "Prima squadra", shortLabel: "Prima", sortOrder: 0, isFirstTeam: true, isActive: true,
    tuttocampoWidgetID: widgetID)
}

/// A temporary folder removed by `cleanup()`.
struct TempFolder {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory.appendingPathComponent("ssimport-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  func cleanup() { try? FileManager.default.removeItem(at: url) }
}

// MARK: - Small widget pages

/// A widget page built from parts, for the cases the sanitised fixtures do not cover.
func widgetPage(
  base: String? = nil, caption: String? = "Risultati Giornata 11", selectedSlide: String? = nil, body: String
) -> String {
  """
  <!DOCTYPE html><html><head>\(base.map { "<base href='\($0)'/>" } ?? "")</head><body>
  <div id="content">
  \(selectedSlide.map { "<div class=\"swiper-slide selected\"><a href=\"/x\"><span title=\"\($0)\">\($0)</span></a></div>" } ?? "")
  <div id="table_results_content"><table class="tc-table table-results">
  \(caption.map { "<caption title=\"\($0)\"></caption>" } ?? "")
  <tbody>
  \(body)
  </tbody></table></div></div></body></html>
  """
}

func dateRow(_ text: String) -> String {
  "<tr class=\"date\"><td colspan=\"4\"><span>\(text)</span></td></tr>"
}

func matchRow(
  home: String, away: String, homeGoal: String = "-", awayGoal: String = "-",
  title: String = "Partita da giocare", homeLogo: String? = "https://b2-content.tuttocampo.it/Teams/40/900001.png?v=1",
  awayLogo: String? = "https://b2-content.tuttocampo.it/Teams/40/900002.png?v=1", time: String = "15:00"
) -> String {
  func image(_ source: String?) -> String { source.map { "<img class=\"hide_small\" src='\($0)'/>" } ?? "" }
  return """
    <tr class="match  ">
    <td class="match-time"><span class="hour"><a href="https://www.tuttocampo.it/p">\(time) </a></span></td>
    <td class="team home "><a class="team-name" href="https://www.tuttocampo.it/s">\(home) </a>\(image(homeLogo))<a href="https://www.tuttocampo.it/p"><span class="goal " title="\(title)">\(homeGoal) </span></a></td>
    <td class="team away "><a href="https://www.tuttocampo.it/p"><span class="goal " title="\(title)">\(awayGoal) </span></a>\(image(awayLogo))<a class="team-name" href="https://www.tuttocampo.it/s">\(away) </a></td>
    <td class="details"></td>
    </tr>
    """
}
