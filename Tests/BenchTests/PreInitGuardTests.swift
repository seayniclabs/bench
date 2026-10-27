import Foundation
import Testing
@testable import BenchCore

@Suite("Requests before initialize")
struct PreInitGuardTests {
    func reply(_ guardState: inout PreInitGuard, _ json: String) -> [String: Any]? {
        guard let data = guardState.intercept(Data(json.utf8)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    @Test("server/discover gets method-not-found under its own id")
    func discoverKeepsId() {
        var g = PreInitGuard()
        let r = reply(&g, #"{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{}}"#)
        #expect(r?["id"] as? Int == 1)
        #expect((r?["error"] as? [String: Any])?["code"] as? Int == -32601)
        #expect(!g.initialized)
    }

    @Test("String ids come back unchanged; ping gets an empty result")
    func pingAndStringId() {
        var g = PreInitGuard()
        let r = reply(&g, #"{"jsonrpc":"2.0","id":"abc","method":"ping"}"#)
        #expect(r?["id"] as? String == "abc")
        #expect((r?["result"] as? [String: Any])?.isEmpty == true)
    }

    @Test("initialize, notifications and everything after initialize pass through")
    func passThrough() {
        var g = PreInitGuard()
        #expect(g.intercept(Data(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{}}"#.utf8)) == nil)
        #expect(g.intercept(Data(#"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{}}"#.utf8)) == nil)
        #expect(g.initialized)
        #expect(g.intercept(Data(#"{"jsonrpc":"2.0","id":3,"method":"server/discover"}"#.utf8)) == nil)
        #expect(g.intercept(Data(#"{"jsonrpc":"2.0","id":4,"method":"tools/list"}"#.utf8)) == nil)
    }
}
