import Foundation
import SSCore

/// `Tests/Fixtures/csi/<name>.html`, located from this file.
func csiFixture(_ name: String) throws -> String {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/csi/\(name).html")
  return try String(contentsOf: url, encoding: .utf8)
}

let csiTestPage = URL(
  string:
    "https://live.centrosportivoitaliano.it/26/Calcio-a-11/Lombardia/Esempio/C99001/G990001-girone-a-2016/?j=ZmFrZQ")!

/// `clubShortName: "Sergnanese"`, as the app's default club.
let csiTestSettings = ClubSettings(
  clubName: "ASD Sergnanese", clubShortName: "Sergnanese", season: "2026/27", accentColor: "#CF3326",
  socialHandle: "", homeVenue: "Campo comunale")

func csiSettings(clubShortName: String) -> ClubSettings {
  var settings = csiTestSettings
  settings.clubShortName = clubShortName
  return settings
}

// MARK: - Small pages

/// A round label of the calendar.
func csiLabel(_ text: String) -> String {
  "<div class=\"label-giornata\">\n<label>\(text)</label>\n</div>"
}

/// A match row in the shape of the real page, for the cases the fixtures do not cover.
func csiRow(
  code: String? = "P999Z1", date: String = "03/10/26", time: String = "16:00", home: String = "Sergnanese",
  away: String = "ASD Esempio Uno",
  homeLogo: String = "https://static.centrosportivoitaliano.it/modulistica/logo/90000001_202601010000.jpg",
  awayLogo: String = "https://static.centrosportivoitaliano.it/modulistica/logo/90000002_202601010000.jpg",
  homeGoals: String = "-", awayGoals: String = "-", tooltip: String = "CAMPO PROVA Via Prova 1 (999Z1)"
) -> String {
  func side(_ name: String, _ logo: String) -> String {
    """
    <div class="d-flex align-items-center gap-2 ">
    <span class="logo-squadra"><div class="ratio ratio-1x1"><img class="obj-contain" alt="x" src="\(logo)"></div></span>
    <span class="nome-squadra">\(name)</span>
    </div>
    """
  }
  let href = code.map { "/26/Calcio-a-11/Lombardia/Esempio/\($0)/?j=ZmFrZQ" } ?? "/26/Calcio-a-11/Lombardia/Esempio/"
  return """
    <div class="row-card"><div data-time="timegC">
    <a href="\(href)" class="btn btn-gara" data-bs-toggle="tooltip" data-bs-title="\(tooltip)" tabindex="-1">
    <div class="d-flex flex-column"><span>\(date)</span><span class="js-gg-min ">\(time)</span></div>
    <div class="vr"></div>
    <div class="d-flex flex-column">\(side(home, homeLogo))\(side(away, awayLogo))</div>
    <div class="vr"></div>
    <div class="d-flex flex-column js-gg-pt "><span>\(homeGoals)</span>
    <span>\(awayGoals)</span></div>
    </a></div></div>
    """
}

/// A page with `body` inside the calendar card.
func csiPage(base: String? = nil, body: String) -> String {
  """
  <!DOCTYPE html><html lang="it"><head>\(base.map { "<base href=\"\($0)\">" } ?? "")<title>Girone</title></head><body>
  <main><div class="card"><div class="card-body">
  \(body)
  </div></div></main></body></html>
  """
}
