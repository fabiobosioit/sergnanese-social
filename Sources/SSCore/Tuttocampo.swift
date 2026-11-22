import Foundation

// Pure functions for the tuttocampo.it import (T4.2): widget ids, ClubIds and logo addresses.
// Rules and the facts behind them: `docs/plan/tasks/wave-4-later.md` (T4.2, "Logo rule") and
// `docs/plan/notes/t4.2-spike.md`.

/// Host of the team logos shown by the widgets and of their `Teams/200` copies.
let tuttocampoLogoHost = "b2-content.tuttocampo.it"

/// `true` for a widget id: hexadecimal digits (either case) in groups of 8-4-4-4-12 separated by
/// `-`, as in `00000000-0000-4000-8000-000000000001`. Only such ids are stored, so an id can go into
/// a URL path as it is.
public func isValidTuttocampoWidgetID(_ text: String) -> Bool {
  let groups = text.split(separator: "-", omittingEmptySubsequences: false)
  return groups.map(\.count) == [8, 4, 4, 4, 12]
    && groups.allSatisfy { $0.allSatisfy { $0.isASCII && $0.isHexDigit } }
}

/// The widget id in `text`: a bare id, or a widget address as copied from the club site's iframe
/// (`https://www.tuttocampo.it/WidgetV2/Risultati/<id>`, also with a matchday segment, a query or no
/// scheme). Surrounding whitespace is ignored and the case is kept. `nil` when `text` holds no id
/// or the address is not on `tuttocampo.it`.
public func tuttocampoWidgetID(from text: String) -> String? {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  if isValidTuttocampoWidgetID(trimmed) { return trimmed }
  guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed),
    let host = url.host?.lowercased(), host == "tuttocampo.it" || host.hasSuffix(".tuttocampo.it")
  else { return nil }
  let parts = url.pathComponents
  guard let index = parts.firstIndex(where: { $0.caseInsensitiveCompare("WidgetV2") == .orderedSame }),
    parts.count > index + 2, isValidTuttocampoWidgetID(parts[index + 2])
  else { return nil }
  return parts[index + 2]
}

/// The ClubId in the address of a widget logo, or `nil` when the address does not have the expected
/// shape (that opponent then gets no logo and is listed in the import report; the id is never
/// guessed). Expected: scheme `https` or `http`, host `b2-content.tuttocampo.it`, path
/// `/Teams/<size folder>/<digits>.<extension>`; the query string is ignored.
///
/// `https://b2-content.tuttocampo.it/Teams/40/917410.png?v=2` → `"917410"`.
public func tuttocampoClubID(fromLogoURL url: URL) -> String? {
  guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
    url.host?.lowercased() == tuttocampoLogoHost
  else { return nil }
  let parts = url.pathComponents
  guard parts.count == 4, parts[0] == "/", parts[1] == "Teams", !parts[2].isEmpty,
    let dot = parts[3].lastIndex(of: ".")
  else { return nil }
  let digits = String(parts[3][..<dot])
  let fileExtension = parts[3][parts[3].index(after: dot)...]
  guard isValidTuttocampoClubID(digits), !fileExtension.isEmpty,
    fileExtension.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
  else { return nil }
  return digits
}

/// The medium-size logo of a club, `https://b2-content.tuttocampo.it/Teams/200/<ClubId>.png`, the
/// first address the logo download tries. `nil` when `clubID` is not 1 to 15 ASCII digits.
public func tuttocampoLogoURL(clubID: String) -> URL? {
  guard isValidTuttocampoClubID(clubID) else { return nil }
  return URL(string: "https://\(tuttocampoLogoHost)/Teams/200/\(clubID).png")
}

/// The name a downloaded logo is stored under in the logos folder: `"<ClubId>.png"`. `nil` when
/// `clubID` is not 1 to 15 ASCII digits.
public func tuttocampoLogoFileName(clubID: String) -> String? {
  isValidTuttocampoClubID(clubID) ? "\(clubID).png" : nil
}

/// `true` for a name `LogoStore.importLogo(data:fileName:replacing:)` accepts:
/// - tuttocampo (T4.2): 1 to 15 ASCII digits followed by `.png` (`"917410.png"`);
/// - CSI (T4.8): `csi-` followed by 1 to 60 characters among `a-z`, `0-9` and `-`, then `.png`
///   (`"csi-12345678.png"`, `"csi-us-esempio-2016.png"`; see `csiLogoFileName(id:name:)`).
///
/// Such a name holds no path and never clashes with the generated `<uuid>.png` names of logos added by
/// hand (a UUID has upper-case letters or, lower-cased, is not prefixed by `csi-`).
public func isValidImportedLogoFileName(_ name: String) -> Bool {
  guard name.hasSuffix(".png") else { return false }
  let stem = String(name.dropLast(4))
  if isValidTuttocampoClubID(stem) { return true }
  guard stem.hasPrefix("csi-") else { return false }
  let rest = stem.utf8.dropFirst(4)
  return (1...csiLogoSlugLimit).contains(rest.count)
    && rest.allSatisfy {
      (UInt8(ascii: "a")...UInt8(ascii: "z")).contains($0) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0)
        || $0 == UInt8(ascii: "-")
    }
}

/// 1 to 15 ASCII digits.
func isValidTuttocampoClubID(_ text: String) -> Bool {
  (1...15).contains(text.count) && text.allSatisfy(\.isASCIIDigit)
}
