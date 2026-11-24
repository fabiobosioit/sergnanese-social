import Foundation

// PDF import (T4.3): the federation calendar of one of our teams, read from a PDF the user opens or drops on
// Partite. The file is read locally: no network, and nothing in it is run (text only). The flow, driven by the UI:
//
// 1. the user picks a PDF; its size is checked against `PDFCalendar.maxFileSize` before the bytes are read;
// 2. `PDFCalendarParser.parse(pdf:settings:)` (`AppServices.pdfCalendarParser`), off the main actor, gives a
//    `PDFCalendar`, or throws `PDFCalendarError` (→ `ImportIssue.pdfReadFailed(file:reason:)`);
// 3. the user picks which of our teams the calendar belongs to (the picker shows `PDFCalendar.competition`);
// 4. staging and commit as in T4.2: `ImportCandidate.make(…, source: .pdf)` for each of `fixtures`, the
//    notices of `ImportIssue.pdfNotices(for:)` on top of the review, "Crea avversario" with
//    `FetchedFixture.newOpponentDraft`, "Collega a esistente…" with `Opponent.draftAddingImportNames(of:)`,
//    then `MatchRepository.upsertFromImport`. The PDF has no logos: none is downloaded.
//
// The layout, the rules and the short-to-full name linking: `docs/plan/tasks/wave-4-later.md` (T4.3).

/// What a federation calendar PDF says: page 1 (the matchday grid) and page 2 (the club table), and our
/// matches worked out from both. Built by a `PDFCalendarParser`.
public struct PDFCalendar: Sendable, Codable, Equatable, Hashable {
  /// Largest PDF the parser reads: 10 MB. The UI checks the file size before reading the bytes.
  public static let maxFileSize = 10 * 1024 * 1024
  /// Largest number of pages the parser reads. The federation calendar has two.
  public static let maxPages = 20

  /// Andata (`A.`, autumn) or ritorno (`R.`, spring), from the prefix of a matchday date.
  public enum Leg: String, Sendable, Codable, CaseIterable {
    case andata, ritorno
  }

  /// One `GIORNATA n` block of page 1.
  public struct Matchday: Sendable, Codable, Equatable, Hashable {
    /// `n`, within `1...FieldLimits.maxRound`.
    public var number: Int
    public var leg: Leg
    /// The date printed under the block, always the Saturday of the weekend (`A. 03/10/2026`).
    public var date: DayDate

    public init(number: Int, leg: Leg, date: DayDate) {
      self.number = number
      self.leg = leg
      self.date = date
    }
  }

  /// The day a club plays its home matches (page 2, column `Giorno`).
  public enum HomeDay: String, Sendable, Codable, CaseIterable {
    /// `Sabato`: the matchday date.
    case saturday
    /// `Domenica`: the matchday date + 1 day.
    case sunday

    /// The day a home match of this club is played in the weekend of `saturday`.
    public func matchDate(saturday: DayDate) -> DayDate {
      self == .sunday ? saturday.adding(days: 1) : saturday
    }
  }

  /// One row of the club table (page 2). Texts are trimmed with whitespace collapsed, as printed.
  public struct Club: Sendable, Codable, Equatable, Hashable {
    /// `Società`, the full official name (`SAN BERNARDO CALCIO`): an alias of the opponent.
    public var fullName: String
    /// `N.`, the club number in the federation (`2015`); recorded, never a key. `nil` when empty.
    public var number: String?
    /// `Campo / Località` (`C.S.COMUNALE N.1 - PAESE - PAESE`).
    public var venue: String
    /// `Indirizzo` (`VIA ESEMPIO 4`).
    public var address: String
    /// `Orario`, the home kick-off time (`9.30` → `09:30`); `nil` when empty or not a time.
    public var time: ClockTime?
    /// `Giorno`; `nil` when it is neither `Sabato` nor `Domenica` (the club's home matches then need review).
    public var homeDay: HomeDay?
    /// The page-1 name linked to this row (`S. BERNARDO CALCIO`); `nil` when no page-1 name was linked to it.
    public var shortName: String?

    public init(
      fullName: String, number: String?, venue: String, address: String, time: ClockTime?, homeDay: HomeDay?,
      shortName: String?
    ) {
      self.fullName = fullName
      self.number = number
      self.venue = venue
      self.address = address
      self.time = time
      self.homeDay = homeDay
      self.shortName = shortName
    }

    /// The venue of a match at this club's ground, as `FetchedFixture.venue`: `"<venue>, <address>"`, an empty
    /// part left out, whitespace collapsed. `ImportCandidate.make` cuts it to `FieldLimits.venue`.
    public var matchVenue: String {
      [venue, address].map(\.collapsedWhitespace).filter { !$0.isEmpty }.joined(separator: ", ")
    }
  }

  /// A reason to check the calendar before importing it. The rows that could be read are still listed.
  public enum Problem: Sendable, Codable, Equatable, Hashable {
    /// A page-1 name linked to no page-2 row: that club's home matches get no time or venue and need review.
    case clubNotLinked(name: String)
    /// The number of distinct page-1 teams (`Riposo` left out) differs from the page-2 rows: "il PDF sembra
    /// incompleto".
    case incomplete(teams: Int, clubs: Int)
    /// A match row of matchday `matchday` that does not split into two sides at `"- "` (none or several splits),
    /// as printed. It gives no fixture.
    case unreadableRow(matchday: Int, text: String)
  }

  /// Title line, top centre (`ESORDIENTI MISTE FEMM. AUT.`).
  public var category: String
  /// First part of the second title line (`FASE AUTUNNALE`).
  public var phase: String
  /// Second part of the second title line (`GIRONE B`).
  public var girone: String
  /// Every `GIORNATA` block, by number.
  public var matchdays: [Matchday]
  /// Every row of the club table, in table order.
  public var clubs: [Club]
  /// Our matches, by matchday, each a fixture of our club (`ClubSettings.clubShortName`):
  /// - `date`: the matchday's Saturday, `HomeDay.matchDate(saturday:)` of the home club; `time`: the home club's;
  /// - `opponentName`: the opponent's page-1 name; `opponentAliases`: its page-2 `fullName` when linked, unless
  ///   it equals the page-1 name;
  /// - `venue`: away, the home club's `matchVenue`; at home `nil` (`ImportCandidate.make` uses `homeVenue`);
  /// - `round`: the matchday number; `competition`: `competition`; `status`: `.scheduled`; `statusText`: `""`;
  ///   no score, ClubId or logo address;
  /// - `scheduleUnknown`: the home club is not linked, or its `homeDay` is `nil` (then the Saturday, no time).
  public var fixtures: [FetchedFixture]
  /// The matchday numbers on which our club rests (`Riposo- SERGNANESE`), ascending. Information only.
  public var byes: [Int]
  /// In the order found: unreadable rows, then unlinked names, then the count check.
  public var problems: [Problem]

  public init(
    category: String, phase: String, girone: String, matchdays: [Matchday], clubs: [Club], fixtures: [FetchedFixture],
    byes: [Int], problems: [Problem]
  ) {
    self.category = category
    self.phase = phase
    self.girone = girone
    self.matchdays = matchdays
    self.clubs = clubs
    self.fixtures = fixtures
    self.byes = byes
    self.problems = problems
  }

  /// `"<category> – <phase> – <girone>"`, an empty part left out, whitespace collapsed, cut with
  /// `truncateAtWord` to `FieldLimits.competition`: `"ESORDIENTI MISTE FEMM. AUT. – FASE AUTUNNALE – GIRONE B"`.
  /// Shown by the team picker and stored as each fixture's `competition`.
  public var competition: String {
    let text = [category, phase, girone].map(\.collapsedWhitespace).filter { !$0.isEmpty }.joined(separator: " – ")
    return truncateAtWord(text, max: FieldLimits.competition).text
  }
}

/// Why a PDF gave no calendar. Becomes `ImportIssue.pdfReadFailed(file:reason:)`.
public enum PDFCalendarError: Error, Sendable, Equatable, Hashable {
  /// The bytes are not a PDF document PDFKit can open.
  case notAPDF
  /// Over `PDFCalendar.maxFileSize` bytes or `PDFCalendar.maxPages` pages. Nothing is parsed.
  case tooLarge
  /// The PDF is locked with a password. Nothing is parsed.
  case encrypted
  /// The PDF opened but is not the federation layout (calendar grid on page 1, club table on page 2): no title,
  /// no `GIORNATA` block, a block without a date, or no club table header. "Formato PDF non riconosciuto";
  /// nothing is guessed.
  case layoutNotRecognised
  /// No parser is configured in this build (the placeholder `AppServices` uses until the real parser is wired).
  case unavailable
}

/// Reads a federation calendar PDF (T4.3: `FederationPDFParser` in SSImport, PDFKit; `FakePDFCalendarParser` in
/// SSCoreFakes). A pure function: no network, no files, no state; only the text and its positions are read.
public protocol PDFCalendarParser: Sendable {
  /// The calendar in `pdf`, with our matches: the rows where one side's name equals `settings.clubShortName`
  /// compared with `searchKey` after `stripLegalPrefixes` (on page 2 after legal suffixes such as `A.S.D.` are
  /// removed too); that side gives `isHome`. Other rows are ignored. Our bye goes in `byes`, never in `fixtures`.
  /// `fixtures` may be empty (our club is not in this calendar): the UI then says so.
  ///
  /// Throws `PDFCalendarError` only: `.tooLarge` before opening when `pdf.count > PDFCalendar.maxFileSize`, else
  /// `.notAPDF`, `.encrypted`, `.tooLarge` (pages) or `.layoutNotRecognised`, in that order.
  func parse(pdf: Data, settings: ClubSettings) throws -> PDFCalendar
}

/// The parser `AppServices` uses when none is given: every PDF throws `PDFCalendarError.unavailable`. Keeps the
/// containers built before T4.3 valid.
@usableFromInline
struct UnavailablePDFCalendarParser: PDFCalendarParser {
  @usableFromInline
  init() {}

  @usableFromInline
  func parse(pdf: Data, settings: ClubSettings) throws -> PDFCalendar {
    throw PDFCalendarError.unavailable
  }
}
