import Foundation
import Mustache
import SSCore
import Synchronization

/// Fills `template.html` with a context, using compiled Mustache templates cached by template id and
/// version. The cache entry also remembers the source text, so a template replaced without a version
/// bump is recompiled instead of serving stale HTML.
public final class TemplateHTML: Sendable {
  private struct Entry: Sendable {
    var source: String
    var template: MustacheTemplate
  }

  private let cache = Mutex<[String: Entry]>([:])

  public init() {}

  /// The HTML of `template` filled with `context`.
  public func render(_ template: InstalledTemplate, context: TemplateContext) throws -> String {
    let compiled = try compiledTemplate(for: template)
    return compiled.render(try Self.mustacheValue(of: context))
  }

  /// Number of compiled templates in the cache (for tests).
  var cachedCount: Int { cache.withLock { $0.count } }

  func compiledTemplate(for template: InstalledTemplate) throws -> MustacheTemplate {
    let file = template.folder.appendingPathComponent("template.html")
    let source: String
    do {
      source = try String(contentsOf: file, encoding: .utf8)
    } catch {
      throw AppError.render(message: RenderStrings.cannotReadTemplate(file.path))
    }
    let key = "\(template.id)@\(template.manifest.version)"
    if let entry = cache.withLock({ $0[key] }), entry.source == source { return entry.template }
    let compiled: MustacheTemplate
    do {
      compiled = try MustacheTemplate(string: source)
    } catch {
      throw AppError.template(problems: [RenderStrings.mustacheInvalid(String(describing: error))])
    }
    cache.withLock { $0[key] = Entry(source: source, template: compiled) }
    return compiled
  }

  /// The context as plain Swift dictionaries, arrays, strings, integers and booleans. Optional values
  /// that are `nil` are absent, so `{{#time}}` / `{{^time}}` sections work. Strings that are empty
  /// after trimming are absent too: swift-mustache treats every `String` as true, `""` included, so
  /// without this `{{^match.venue}}` would never run for a match without a venue.
  static func mustacheValue(of context: TemplateContext) throws -> [String: Any] {
    let encoder = JSONEncoder()
    let data: Data
    switch context {
    case .single(let single): data = try encoder.encode(single)
    case .list(let list): data = try encoder.encode(list)
    }
    let object = try JSONSerialization.jsonObject(with: data)
    return plain(object) as? [String: Any] ?? [:]
  }

  /// Converts Foundation JSON objects to native Swift values Mustache can walk. Dictionary entries
  /// whose value is a blank string are dropped (array elements are kept, so positions do not move).
  static func plain(_ value: Any) -> Any {
    switch value {
    case let dictionary as [String: Any]:
      return dictionary.filter { !isBlankString($0.value) }.mapValues(plain)
    case let array as [Any]: return array.map(plain)
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
      let double = number.doubleValue
      return double.rounded() == double && abs(double) < 1e15 ? Int(double) : double
    case let string as String: return string
    default: return value
    }
  }

  private static func isBlankString(_ value: Any) -> Bool {
    guard let string = value as? String else { return false }
    return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
