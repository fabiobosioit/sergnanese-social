import Foundation
import SSCore
import SSData
import Testing

/// The whole engine on real services: seed, database file, templates, render. No UI.
@MainActor
@Suite(.serialized)
struct WorkflowTests {
  @Test func seedShowsNextWeekend() async throws {
    let env = try Env()
    #expect(try env.database.matches.count(source: nil) == 0)
    try await env.seed()
    let weekend = env.weekend
    let matches = try env.database.matches.list(from: weekend.saturday, to: weekend.sunday, teamID: nil)
    #expect(matches.count == 9)
    #expect(matches.allSatisfy { $0.match.date >= weekend.saturday && $0.match.date <= weekend.sunday })
  }

  @Test func editedTimeSurvivesReopeningTheDatabase() async throws {
    let env = try Env()
    try await env.seed()
    let weekend = env.weekend
    let target = try #require(
      try env.database.matches.list(from: weekend.saturday, to: weekend.sunday, teamID: nil)
        .first { $0.match.time != nil })
    let draft = MatchDraft(
      teamID: target.match.teamID, opponentID: target.match.opponentID, date: target.match.date,
      time: try ClockTime("18:45"), isHome: target.match.isHome, venue: target.match.venue,
      competition: target.match.competition, round: target.match.round, status: target.match.status,
      notes: target.match.notes, source: target.match.source)
    _ = try env.database.matches.update(id: target.match.id, with: draft)

    let reopened = try AppDatabase.open(paths: env.paths)
    let stored = try reopened.matches.get(id: target.match.id)
    #expect(stored.match.time?.value == "18:45")
  }

  @Test func defaultPlanWritesFilesWithExactSizes() async throws {
    let env = try Env()
    try await env.seed()
    let request = RenderRequest(weekend: env.weekend)
    let plan = try env.renderer.plan(request)
    // One programme story per day (9 matches: 4 on Saturday, 5 on Sunday) and one pre-match post.
    #expect(plan.images.count == 3)
    let images = try await env.render(request)
    #expect(images.count == 3)
    for (image, planned) in zip(images, plan.images) {
      let size = try #require(pngSize(image.record.fileURL))
      #expect(size.width == planned.width && size.height == planned.height)
      #expect(image.record.width == planned.width && image.record.height == planned.height)
    }
    let sizes = Set(images.map { "\($0.record.width)x\($0.record.height)" })
    #expect(sizes == ["1080x1920", "1080x1350"])
    #expect(try env.database.renders.list(from: nil, to: nil).count == 3)
  }

  @Test func twelveMatchesMakeTwoProgrammeStories() async throws {
    let env = try Env()
    let team = try env.database.teams.create(TeamDraft(name: "Prima Squadra", shortLabel: "Prima", isFirstTeam: true))
    let sunday = env.weekend.sunday
    for index in 0..<12 {
      let opponent = try env.database.opponents.create(OpponentDraft(name: "Squadra Numero \(index)"))
      _ = try env.database.matches.create(
        MatchDraft(
          teamID: team.id, opponentID: opponent.id, date: sunday,
          time: try ClockTime(String(format: "%02d:%02d", 8 + index / 2, (index % 2) * 30)), isHome: index % 2 == 0,
          venue: "Campo Comunale"))
    }
    let ids = try env.database.matches.list(from: sunday, to: sunday, teamID: nil).map(\.match.id)
    #expect(ids.count == 12)
    let request = RenderRequest(
      weekend: env.weekend, selections: [TemplateSelection(templateID: "story-programme", matchIDs: ids)])
    let images = try await env.render(request)
    #expect(images.count == 2)
    #expect(images.allSatisfy { $0.record.width == 1080 && $0.record.height == 1920 })
    #expect(images.compactMap { $0.record.page?.total } == [2, 2])
  }

  @Test func importedUserTemplateIsListedAndRenders() async throws {
    let env = try Env()
    try await env.seed()
    // A user template: a built-in copied under another id, zipped with the files at the zip root.
    let source = env.root.appendingPathComponent("user-template", isDirectory: true)
    try FileManager.default.copyItem(at: env.paths.builtinTemplates.appendingPathComponent("post-prematch"), to: source)
    let manifestURL = source.appendingPathComponent("manifest.json")
    let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
      .replacingOccurrences(of: "\"post-prematch\"", with: "\"user-prematch\"")
      .replacingOccurrences(of: "Post · Pre-partita", with: "Post utente")
    try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
    let zip = env.root.appendingPathComponent("user-template.zip")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.arguments = ["-r", "-q", zip.path, "."]
    process.currentDirectoryURL = source
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)

    let outcome = try env.templates.install(from: zip, replace: false)
    guard case .installed(let installed) = outcome else {
      Issue.record("not installed: \(outcome)")
      return
    }
    #expect(installed.isBuiltin == false)
    #expect(try env.templates.list().contains { $0.id == "user-prematch" })

    let weekend = env.weekend
    let match = try #require(
      try env.database.matches.list(from: weekend.saturday, to: weekend.sunday, teamID: nil)
        .first { $0.team.isFirstTeam })
    let images = try await env.render(
      RenderRequest(
        weekend: weekend, selections: [TemplateSelection(templateID: "user-prematch", matchIDs: [match.match.id])]))
    #expect(images.count == 1)
    let size = try #require(pngSize(images[0].record.fileURL))
    #expect(size.width == 1080 && size.height == 1350)
  }

  @Test func opponentWithoutLogoStillRenders() async throws {
    let env = try Env()
    let team = try env.database.teams.create(TeamDraft(name: "Prima Squadra", shortLabel: "Prima", isFirstTeam: true))
    let opponent = try env.database.opponents.create(OpponentDraft(name: "ASD Senza Logo"))
    #expect(opponent.logoFile == nil)
    let match = try env.database.matches.create(
      MatchDraft(
        teamID: team.id, opponentID: opponent.id, date: env.weekend.sunday, time: try ClockTime("15:00"),
        isHome: true, venue: "Campo Comunale"))
    let request = RenderRequest(
      weekend: env.weekend, selections: [TemplateSelection(templateID: "post-prematch", matchIDs: [match.id])])
    let plan = try env.renderer.plan(request)
    #expect(plan.warnings.contains { $0.kind == .missingLogo })
    let images = try await env.render(request)
    #expect(images.count == 1)
    let size = try #require(pngSize(images[0].record.fileURL))
    #expect(size.width == 1080 && size.height == 1350)
  }
}
