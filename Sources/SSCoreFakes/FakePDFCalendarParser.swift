import Foundation
import SSCore

/// A federation PDF parser with one canned answer, for `--mock`, previews and tests. It ignores the bytes and the
/// settings: every PDF gives `outcome`.
///
/// `AppServices.fake()` uses `scenario(referenceSaturday:)`, which covers the T4.3 cases against the fixture data
/// set (see the table there).
public struct FakePDFCalendarParser: PDFCalendarParser {
  /// What every `parse` returns or throws.
  public var outcome: Result<PDFCalendar, PDFCalendarError>

  public init(outcome: Result<PDFCalendar, PDFCalendarError>) {
    self.outcome = outcome
  }

  /// Every PDF gives `calendar`.
  public init(calendar: PDFCalendar) {
    self.init(outcome: .success(calendar))
  }

  /// Every PDF throws `error` (`.layoutNotRecognised` for "Formato PDF non riconosciuto").
  public init(failing error: PDFCalendarError) {
    self.init(outcome: .failure(error))
  }

  public func parse(pdf: Data, settings: ClubSettings) throws -> PDFCalendar {
    try outcome.get()
  }

  // MARK: Scenario

  /// `scenarioCalendar(referenceSaturday:)` for every PDF.
  public static func scenario(referenceSaturday: DayDate) -> FakePDFCalendarParser {
    FakePDFCalendarParser(calendar: scenarioCalendar(referenceSaturday: referenceSaturday))
  }

  /// A fake calendar ("ESORDIENTI FEMMINILI – FASE AUTUNNALE – GIRONE A", five matchdays, matchday `n` on
  /// `referenceSaturday + 7 × (n − 2)`, four clubs in the table, five teams on page 1), dated around
  /// `referenceSaturday` (pass the data set's, after shifting). Staged for **Femminile** with
  /// `Resources/Fixtures/matches.json` (S = the reference Saturday):
  ///
  /// | Giornata | Fixture | Candidate |
  /// |---|---|---|
  /// | 1 | our bye | no fixture; `.pdfBye(matchday: 1)` |
  /// | 2 | away at "S. ILARIO", Sunday S+1 (club plays Domenica) 10:30, venue "C.S. COMUNALE - SANT'ILARIO, VIA ROMA 10", alias "G.S. SANT'ILARIO CITTA" | found through the alias (G.S. Sant'Ilario Città); `.changed` (the stored match is at home, 18:00, postponed) |
  /// | 3 | home vs "BORGO LUCENTE", Saturday S+7 17:30 (our club's time), no venue, alias "POL. BORGO LUCENTE" | `.new` with `homeVenue` |
  /// | 4 | away at "AURORA PIANENGO", Saturday S+14 15:00, venue "ORATORIO AURORA - PIANENGO, VIA MANZONI 2", alias "A.S.D. AURORA PIANENGO 1990" | `.needsReview` (`opponentNotFound`); "Crea avversario" saves the alias, then `.new` |
  /// | 5 | away at "NUOVA ESEMPIO", Saturday S+21, no time, no venue, `scheduleUnknown` | `.needsReview` (`opponentNotFound`, `scheduleUnknown`) |
  ///
  /// Problems, in this order: `.unreadableRow(matchday: 4, text: "BORGO LUCENTE NUOVA ESEMPIO")`,
  /// `.clubNotLinked(name: "NUOVA ESEMPIO")`, `.incomplete(teams: 5, clubs: 4)`. Every fixture has round = matchday,
  /// `competition`, status `.scheduled` and `statusText` `""`.
  public static func scenarioCalendar(referenceSaturday: DayDate) -> PDFCalendar {
    let saturday = referenceSaturday
    func day(_ matchday: Int) -> DayDate { saturday.adding(days: 7 * (matchday - 2)) }
    let ilario = PDFCalendar.Club(
      fullName: "G.S. SANT'ILARIO CITTA", number: "9001", venue: "C.S. COMUNALE - SANT'ILARIO", address: "VIA ROMA 10",
      time: ClockTime(hour: 10, minute: 30), homeDay: .sunday, shortName: "S. ILARIO")
    let lucente = PDFCalendar.Club(
      fullName: "POL. BORGO LUCENTE", number: "9002", venue: "CAMPO SPORTIVO - BORGO LUCENTE", address: "VIA DANTE 3",
      time: ClockTime(hour: 15, minute: 30), homeDay: .saturday, shortName: "BORGO LUCENTE")
    let ours = PDFCalendar.Club(
      fullName: "SERGNANESE A.S.D.", number: "9003", venue: "CAMPO COMUNALE - SERGNANO", address: "VIA ESEMPIO 1",
      time: ClockTime(hour: 17, minute: 30), homeDay: .saturday, shortName: "SERGNANESE")
    let aurora = PDFCalendar.Club(
      fullName: "A.S.D. AURORA PIANENGO 1990", number: "9004", venue: "ORATORIO AURORA - PIANENGO",
      address: "VIA MANZONI 2", time: ClockTime(hour: 15, minute: 0), homeDay: .saturday, shortName: "AURORA PIANENGO")
    var calendar = PDFCalendar(
      category: "ESORDIENTI FEMMINILI", phase: "FASE AUTUNNALE", girone: "GIRONE A",
      matchdays: (1...5).map { PDFCalendar.Matchday(number: $0, leg: .andata, date: day($0)) },
      clubs: [ilario, lucente, ours, aurora], fixtures: [], byes: [1],
      problems: [
        .unreadableRow(matchday: 4, text: "BORGO LUCENTE NUOVA ESEMPIO"), .clubNotLinked(name: "NUOVA ESEMPIO"),
        .incomplete(teams: 5, clubs: 4),
      ])
    let competition = calendar.competition
    func fixture(
      _ matchday: Int, home: PDFCalendar.Club?, isHome: Bool, opponent: String, alias: PDFCalendar.Club?
    ) -> FetchedFixture {
      FetchedFixture(
        date: home?.homeDay?.matchDate(saturday: day(matchday)) ?? day(matchday), time: home?.time, isHome: isHome,
        opponentName: opponent, round: matchday, status: .scheduled, statusText: "",
        venue: isHome ? nil : home?.matchVenue, opponentAliases: alias.map { [$0.fullName] } ?? [],
        competition: competition, scheduleUnknown: home?.homeDay == nil)
    }
    calendar.fixtures = [
      fixture(2, home: ilario, isHome: false, opponent: "S. ILARIO", alias: ilario),
      fixture(3, home: ours, isHome: true, opponent: "BORGO LUCENTE", alias: lucente),
      fixture(4, home: aurora, isHome: false, opponent: "AURORA PIANENGO", alias: aurora),
      fixture(5, home: nil, isHome: false, opponent: "NUOVA ESEMPIO", alias: nil),
    ]
    return calendar
  }

  // MARK: Opponent matching (T4.10)

  /// `matchingScenarioCalendar(referenceSaturday:)` for every PDF.
  public static func matchingScenario(referenceSaturday: DayDate) -> FakePDFCalendarParser {
    FakePDFCalendarParser(calendar: matchingScenarioCalendar(referenceSaturday: referenceSaturday))
  }

  /// A fake calendar with one fixture for each opponent-matching result (T4.10) against the opponents of
  /// `Resources/Fixtures/matches.json`: four home matches on the Saturdays from `referenceSaturday`, 17:30, matchdays
  /// 1 to 4, no problems.
  ///
  /// | Giornata | Fixture | `ImportCandidate.opponentMatch` |
  /// |---|---|---|
  /// | 1 | "BORGO LUCENTE S.R.L." | `.exact`: Pol. Borgo Lucente (legal prefix and suffix ignored) |
  /// | 2 | "VIRTUS CAMPOFELICI" | `.proposed` and pre-filled: Virtus Campofelice (one letter differs) |
  /// | 3 | "ORATORIO CALCIO" | `.ambiguous`: the three "Oratorio …" opponents proposed ("oratorio" has 7+ letters) |
  /// | 4 | "NUOVA ESEMPIO" | `.notFound` |
  public static func matchingScenarioCalendar(referenceSaturday: DayDate) -> PDFCalendar {
    let names = ["BORGO LUCENTE S.R.L.", "VIRTUS CAMPOFELICI", "ORATORIO CALCIO", "NUOVA ESEMPIO"]
    let dates = names.indices.map { referenceSaturday.adding(days: 7 * $0) }
    var calendar = PDFCalendar(
      category: "ESORDIENTI FEMMINILI", phase: "FASE PRIMAVERILE", girone: "GIRONE C",
      matchdays: dates.enumerated().map { PDFCalendar.Matchday(number: $0.offset + 1, leg: .andata, date: $0.element) },
      clubs: [], fixtures: [], byes: [], problems: [])
    let competition = calendar.competition
    calendar.fixtures = zip(names, dates).enumerated().map { index, pair in
      FetchedFixture(
        date: pair.1, time: ClockTime(hour: 17, minute: 30), isHome: true, opponentName: pair.0, round: index + 1,
        status: .scheduled, statusText: "", competition: competition)
    }
    return calendar
  }
}
