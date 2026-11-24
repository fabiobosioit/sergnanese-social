import Testing

@testable import SSImport

@Suite("Federation PDF: club names")
struct ClubNamesTests {
  @Test("words: case, dots, legal forms and accents do not matter")
  func words() {
    #expect(ClubNames.words("SERGNANESE A.S.D.") == ["SERGNANESE"])
    #expect(ClubNames.words("A.S.D. Esempio Uno") == ["ESEMPIO", "UNO"])
    #expect(ClubNames.words("ESEMPIO UNO MILANO SSD A RL") == ["ESEMPIO", "UNO", "MILANO"])
    #expect(ClubNames.words("ESEMPIO SEI A R.L.") == ["ESEMPIO", "SEI"])
    #expect(ClubNames.words("ESEMPIO DUE S.P.A.") == ["ESEMPIO", "DUE"])
    #expect(ClubNames.words("Esempio Tre S.R.L.") == ["ESEMPIO", "TRE"])
    #expect(ClubNames.words("Pol. Esempio Quattro") == ["ESEMPIO", "QUATTRO"])
    #expect(ClubNames.words("REAL ESEMPIO CF Sq.B") == ["REAL", "ESEMPIO", "CF", "SQB"])
    #expect(ClubNames.words("REAL ESEMPIO CF sq.B") == ["REAL", "ESEMPIO", "CF", "SQB"])
    #expect(ClubNames.words("Città   d'Esempio") == ["CITTA", "D", "ESEMPIO"])
    #expect(ClubNames.words("ESEMPIO 1970") == ["ESEMPIO", "1970"])
  }

  @Test("a name made only of legal forms keeps its words")
  func onlyLegalWords() {
    #expect(ClubNames.words("A.S.D.") == ["ASD"])
    #expect(ClubNames.words("") == [])
  }

  @Test("S. stands for SAN, SANTO and SANTA, only to compare")
  func saint() {
    #expect(ClubNames.same(ClubNames.words("S. ESEMPIO CALCIO"), ClubNames.words("SAN ESEMPIO CALCIO")))
    #expect(ClubNames.same(ClubNames.words("S. Esempio"), ClubNames.words("SANTO ESEMPIO")))
    #expect(ClubNames.same(ClubNames.words("SANTA ESEMPIO"), ClubNames.words("S ESEMPIO")))
    #expect(!ClubNames.same(ClubNames.words("S. ESEMPIO"), ClubNames.words("SANDRO ESEMPIO")))
    #expect(!ClubNames.same(ClubNames.words("ESEMPIO"), ClubNames.words("ESEMPIO UNO")))
  }

  @Test("begins(with:) needs every word of the prefix; an empty prefix matches nothing")
  func prefix() {
    let long = ClubNames.words("ALFA MILANO SSD A RL")
    #expect(ClubNames.begins(long, with: ClubNames.words("ALFA")))
    #expect(ClubNames.begins(long, with: ClubNames.words("ALFA MILANO")))
    #expect(!ClubNames.begins(long, with: ClubNames.words("MILANO")))
    #expect(!ClubNames.begins(long, with: ClubNames.words("ALFA MILANO NORD")))
    #expect(!ClubNames.begins(long, with: []))
  }

  @Test("team keys ignore case and spacing")
  func teamKey() {
    #expect(ClubNames.teamKey("Real  Esempio Sq.B ") == ClubNames.teamKey("REAL ESEMPIO SQ.B"))
  }

  // MARK: Linking

  private func link(_ names: [String], _ clubs: [String]) -> [Int?] {
    ClubNames.link(names: names, clubNames: clubs)
  }

  @Test("rules 1 and 2: equal, or the row starts with all the words")
  func equalOrPrefix() {
    let clubs = ["ALFA MILANO SSD A RL", "BETA S.P.A.", "SAN GAMMA CALCIO", "DELTA 1911", "EPSILON CF sq.B"]
    let names = ["ALFA", "BETA", "S. GAMMA CALCIO", "DELTA 1911", "EPSILON CF Sq.B"]
    #expect(link(names, clubs) == [0, 1, 2, 3, 4])
  }

  @Test("an exact row wins over a longer name that starts the same way")
  func exactBeforePrefix() {
    let clubs = ["ESEMPIO UNO MILANO SSD A RL", "ESEMPIO"]
    #expect(link(["ESEMPIO", "ESEMPIO UNO"], clubs) == [1, 0])
    #expect(link(["ESEMPIO UNO", "ESEMPIO"], clubs) == [0, 1])
  }

  @Test("a prefix name settles once the rows taken by other links are out of the way")
  func prefixChain() {
    let clubs = ["ESEMPIO UNO MILANO", "ESEMPIO CALCIO"]
    #expect(link(["ESEMPIO", "ESEMPIO UNO"], clubs) == [1, 0])
  }

  @Test("a name that fits two rows is not guessed")
  func ambiguous() {
    #expect(link(["ESEMPIO"], ["ESEMPIO UNO", "ESEMPIO DUE"]) == [nil])
    #expect(link(["ESEMPIO"], ["ESEMPIO UNO", "ESEMPIO UNO"]) == [nil])
  }

  @Test("rule 3: one name and one row left over belong together")
  func leftOver() {
    #expect(link(["ALFA", "BETA", "GAMMA RARO"], ["ALFA SSD", "BETA", "XYZ"]) == [0, 1, 2])
  }

  @Test("rule 3 does not apply with two names or two rows left")
  func notLeftOver() {
    #expect(link(["ALFA", "UNO", "DUE"], ["ALFA", "TRE", "QUATTRO"]) == [0, nil, nil])
    #expect(link(["ALFA", "UNO"], ["ALFA", "TRE", "QUATTRO"]) == [0, nil])
  }

  @Test("a name with no row stays unlinked when every row is taken")
  func missingRow() {
    #expect(link(["ALFA", "BETA"], ["ALFA"]) == [0, nil])
  }

  @Test("our own club links through its legal suffix")
  func ourRow() {
    #expect(link(["SERGNANESE", "ALFA"], ["SERGNANESE A.S.D.", "ALFA"]) == [0, 1])
  }
}
