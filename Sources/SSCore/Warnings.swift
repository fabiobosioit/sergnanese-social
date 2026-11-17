import Foundation

/// A non-blocking problem shown inline with a yellow triangle (missing logo, cut name, missing time…).
/// Warnings never stop a render.
public struct RenderWarning: Sendable, Equatable, Hashable {
  public enum Kind: String, Sendable, Codable, CaseIterable {
    /// The opponent has no logo; the initials circle is used.
    case missingLogo
    case missingTime
    case missingVenue
    /// A field in the template's `requires` is missing (other than time and venue).
    case missingRequiredField
    /// The opponent's display name was cut (decision D5). Fix: set a short name (`opponentID`).
    case nameTruncated
    /// Another text (venue, category) was cut to the template's limit.
    case textTruncated
    /// A postponed or cancelled match is on the image.
    case matchNotScheduled
    /// The template asked for a remote resource, which was blocked.
    case blockedRequest
  }

  public var kind: Kind
  /// Italian, ready to show.
  public var message: String
  /// The match concerned, for "Modifica" (jump to the match in Partite).
  public var matchID: EntityID?
  /// The opponent concerned, for "Imposta nome breve" and "Aggiungi logo".
  public var opponentID: EntityID?
  /// The template concerned, when the warning depends on it.
  public var templateID: String?

  public init(
    kind: Kind, message: String, matchID: EntityID? = nil, opponentID: EntityID? = nil, templateID: String? = nil
  ) {
    self.kind = kind
    self.message = message
    self.matchID = matchID
    self.opponentID = opponentID
    self.templateID = templateID
  }
}

/// The warnings of one match that do not depend on a particular template: no time, no venue, no
/// opponent logo, and, when `teamNameLimit` is given, an opponent name that will be cut.
///
/// Partite uses it with the smallest `limits.teamName` among installed templates; the render engine
/// uses it per template and adds its own template-specific warnings. Order: time, venue, logo, name.
public func matchWarnings(for detail: MatchDetail, teamNameLimit: Int?) -> [RenderWarning] {
  let match = detail.match
  let opponent = detail.opponent
  var warnings: [RenderWarning] = []
  if match.time == nil {
    warnings.append(RenderWarning(kind: .missingTime, message: CoreStrings.warningNoTime, matchID: match.id))
  }
  if match.venue.trimmingCharacters(in: .whitespaces).isEmpty {
    warnings.append(RenderWarning(kind: .missingVenue, message: CoreStrings.warningNoVenue, matchID: match.id))
  }
  if opponent.logoFile == nil {
    warnings.append(
      RenderWarning(
        kind: .missingLogo, message: CoreStrings.warningNoLogo(opponent.name), matchID: match.id,
        opponentID: opponent.id))
  }
  if let teamNameLimit {
    let shown = displayName(for: opponent, limit: teamNameLimit)
    if shown.wasCut {
      warnings.append(
        RenderWarning(
          kind: .nameTruncated, message: CoreStrings.warningNameCut(opponent.name, shown.text), matchID: match.id,
          opponentID: opponent.id))
    }
  }
  return warnings
}
