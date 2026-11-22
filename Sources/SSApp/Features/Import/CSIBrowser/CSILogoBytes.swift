import Foundation

/// Checks on logo bytes that come from the page.
enum CSILogoBytes {
  /// The bytes in `base64`, or `nil` when it is not base64, is empty, or decodes to more than `maxBytes`.
  /// The length is checked before decoding, so a huge answer is never decoded.
  static func decode(base64: String, maxBytes: Int = CSIPageScripts.maxLogoBytes) -> Data? {
    guard base64.utf8.count <= (maxBytes / 3 + 1) * 4, let data = Data(base64Encoded: base64),
      !data.isEmpty, data.count <= maxBytes
    else { return nil }
    return data
  }

  /// Only `https` and `http` addresses are read.
  static func isReadable(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else { return false }
    return (scheme == "https" || scheme == "http") && url.host?.isEmpty == false
  }
}
