import Foundation
import WebKit

/// What a script run in the page answered: a text, or a reason it has none.
struct CSIScriptReply: Sendable, Equatable {
  var value: String?
  var reason: String?

  /// Reads `{ value: "…" }` or `{ reason: "…" }`; `nil` for anything else.
  init?(_ result: Any) {
    guard let dictionary = result as? [String: Any] else { return nil }
    let value = dictionary["value"] as? String
    let reason = dictionary["reason"] as? String
    guard value != nil || reason != nil else { return nil }
    self.value = value
    self.reason = reason
  }

  init(value: String? = nil, reason: String? = nil) {
    self.value = value
    self.reason = reason
  }
}

/// How a script call ended.
enum CSIScriptOutcome: Sendable, Equatable {
  case reply(CSIScriptReply)
  /// A JavaScript error, an unreadable answer or a page that went away.
  case failed
  /// No answer within the time limit.
  case timedOut
}

/// The scripts the app runs in the CSI page. They run in `WKContentWorld.defaultClient`, a world of their
/// own that the page's scripts cannot see into. Arguments are passed as values, never spliced into the
/// text. The page cannot call back into the app: there are no message handlers; only the app asks.
enum CSIPageScripts {
  /// Longest HTML the app reads: 2 MB.
  static let maxHTMLBytes = 2 * 1024 * 1024
  /// Longest logo, in the page and when downloaded: 5 MB.
  static let maxLogoBytes = 5 * 1024 * 1024

  /// `document.documentElement.outerHTML`, or `{reason: "tooLarge"}` past `max` UTF-16 units (a count that
  /// is never above the UTF-8 byte count, so a page past it is past the byte cap too). Argument: `max`.
  static let readHTML = """
    const root = document.documentElement;
    if (!root) { return { reason: "empty" }; }
    const html = root.outerHTML;
    if (html.length > max) { return { reason: "tooLarge" }; }
    return { value: html };
    """

  /// The bytes of the image at `url` as base64, read in the page session. Refuses a response that is not
  /// `ok`, not `image/*` or longer than `max` bytes (checked on the header and while reading).
  /// Arguments: `url`, `max`.
  static let fetchImage = """
    const response = await fetch(url);
    if (!response.ok) { return { reason: "status" }; }
    const type = (response.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
    if (!type.startsWith("image/")) { return { reason: "type" }; }
    const declared = Number(response.headers.get("content-length"));
    if (declared > max) { return { reason: "tooLarge" }; }
    const reader = response.body.getReader();
    const chunks = [];
    let total = 0;
    for (;;) {
      const step = await reader.read();
      if (step.done) { break; }
      total += step.value.length;
      if (total > max) { await reader.cancel(); return { reason: "tooLarge" }; }
      chunks.push(step.value);
    }
    let binary = "";
    for (const chunk of chunks) {
      for (let index = 0; index < chunk.length; index += 0x8000) {
        binary += String.fromCharCode.apply(null, chunk.subarray(index, index + 0x8000));
      }
    }
    return { value: btoa(binary) };
    """

  /// Runs `body` in the client world of `webView` and waits for the answer, at most `timeout`. Returns when
  /// the task is cancelled too (as `.failed`; the script itself cannot be stopped).
  @MainActor
  static func run(
    _ body: String, arguments: [String: Any], in webView: WKWebView, timeout: Duration
  ) async -> CSIScriptOutcome {
    let call = PendingCall()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<CSIScriptOutcome, Never>) in
        call.continuation = continuation
        if Task.isCancelled {
          call.finish(.failed)
          return
        }
        let timer = Task { @MainActor in
          try? await Task.sleep(for: timeout)
          call.finish(.timedOut)
        }
        call.timer = timer
        webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .defaultClient) { result in
          switch result {
          case .success(let value):
            call.finish(CSIScriptReply(value).map { .reply($0) } ?? .failed)
          case .failure:
            call.finish(.failed)
          }
        }
      }
    } onCancel: {
      Task { @MainActor in call.finish(.failed) }
    }
  }

  /// The one-shot state of a script call: whichever of the answer, the timer and the cancellation comes
  /// first resumes the continuation, the others do nothing.
  @MainActor
  private final class PendingCall {
    var continuation: CheckedContinuation<CSIScriptOutcome, Never>?
    var timer: Task<Void, Never>?

    func finish(_ outcome: CSIScriptOutcome) {
      timer?.cancel()
      timer = nil
      guard let continuation else { return }
      self.continuation = nil
      continuation.resume(returning: outcome)
    }
  }
}
