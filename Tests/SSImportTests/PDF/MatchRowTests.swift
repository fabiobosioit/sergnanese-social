import Testing

@testable import SSImport

@Suite("Federation PDF: match rows")
struct MatchRowTests {
  @Test("a plain row splits into home and away")
  func plain() {
    #expect(MatchRow.split("CREMONESE- RIOZZESE") == .match(home: "CREMONESE", away: "RIOZZESE"))
    #expect(MatchRow.split("A- B") == .match(home: "A", away: "B"))
    #expect(MatchRow.split("  ESEMPIO   UNO-   ESEMPIO DUE ") == .match(home: "ESEMPIO UNO", away: "ESEMPIO DUE"))
  }

  @Test("a name with ' - ' inside it is not split there")
  func hyphenInName() {
    #expect(MatchRow.split("A - B- C") == .match(home: "A - B", away: "C"))
    #expect(MatchRow.split("A- B - C") == .match(home: "A", away: "B - C"))
  }

  @Test("no separator, or two, is unreadable")
  func unreadable() {
    #expect(MatchRow.split("A B") == .unreadable)
    #expect(MatchRow.split("A - B") == .unreadable)
    #expect(MatchRow.split("A- B- C") == .unreadable)
    #expect(MatchRow.split("") == .unreadable)
    #expect(MatchRow.split("A-") == .unreadable)
    #expect(MatchRow.split("- B") == .unreadable)
    #expect(MatchRow.split("A-B") == .unreadable)
  }

  @Test("Riposo on the home side is a bye of the away side, in any case")
  func bye() {
    #expect(MatchRow.split("Riposo- A") == .bye(club: "A"))
    #expect(MatchRow.split("RIPOSO- ESEMPIO UNO") == .bye(club: "ESEMPIO UNO"))
    #expect(MatchRow.split("riposo- A") == .bye(club: "A"))
    // Riposo as the away side is just a name.
    #expect(MatchRow.split("A- Riposo") == .match(home: "A", away: "Riposo"))
  }

  @Test("matchday labels and dates")
  func labels() {
    #expect(CalendarGrid.matchdayNumber("GIORNATA 7") == 7)
    #expect(CalendarGrid.matchdayNumber("Giornata 12") == 12)
    #expect(CalendarGrid.matchdayNumber("GIORNATA") == nil)
    #expect(CalendarGrid.matchdayNumber("GIORNATA 7 bis") == nil)
    #expect(CalendarGrid.matchdayDate("A. 03/10/2026")?.0 == .andata)
    #expect(CalendarGrid.matchdayDate("R. 14/03/2027")?.0 == .ritorno)
    #expect(CalendarGrid.matchdayDate("R. 14/03/2027")?.1.value == "2027-03-14")
    #expect(CalendarGrid.matchdayDate("X. 03/10/2026") == nil)
    #expect(CalendarGrid.matchdayDate("A. 31/02/2026") == nil)
    #expect(CalendarGrid.matchdayDate("A. 03/10") == nil)
  }

  @Test("home day: Sabato and Domenica, any case and accents")
  func homeDay() {
    #expect(ClubTable.homeDay("Sabato") == .saturday)
    #expect(ClubTable.homeDay("DOMENICA") == .sunday)
    #expect(ClubTable.homeDay("domenica ") == .sunday)
    #expect(ClubTable.homeDay("Venerdì") == nil)
    #expect(ClubTable.homeDay("") == nil)
  }
}
