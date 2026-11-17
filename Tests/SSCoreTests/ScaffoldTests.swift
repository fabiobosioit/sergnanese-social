import Testing

@testable import SSCore

@Suite struct ScaffoldTests {
  @Test func scaffoldBuilds() {
    #expect(1 + 1 == 2)
  }
}
