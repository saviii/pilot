import Foundation
import Testing

@testable import PilotKit

/// The Christmas tree plug (a Govee H5083), over Govee's online API.
@Suite struct GoveePlugs {
    let plug = GoveePlug(sku: "H5083", device: "AA:BB:CC:DD:EE:FF:00:11", name: "Circular Smart Plug")

    @Test func findsThePlugAndSkipsWhatCantSwitch() throws {
        #expect(try Govee.plugs(from: fixture("govee-devices.json")) == [plug])
    }

    @Test func listingSendsTheKey() {
        let request = Govee.devicesRequest(key: "k")
        #expect(request.url?.absoluteString == "https://openapi.api.govee.com/router/api/v1/user/devices")
        #expect(request.value(forHTTPHeaderField: "Govee-API-Key") == "k")
        // Without this Govee answers 400 with an empty body.
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func switchingOn() throws {
        let request = Govee.controlRequest(key: "k", plug: plug, on: true, requestId: "r1")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.lastPathComponent == "control")
        let body = try bodyOf(request)
        let payload = try #require(body["payload"] as? [String: Any])
        let capability = try #require(payload["capability"] as? [String: Any])
        #expect(payload["sku"] as? String == "H5083")
        #expect(payload["device"] as? String == plug.device)
        #expect(capability["instance"] as? String == "powerSwitch")
        #expect(capability["value"] as? Int == 1)
    }

    @Test func switchingOff() throws {
        let request = Govee.controlRequest(key: "k", plug: plug, on: false)
        let body = try bodyOf(request)
        let capability = (body["payload"] as? [String: Any])?["capability"] as? [String: Any]
        #expect(capability?["value"] as? Int == 0)
    }

    @Test func readsWhetherItsOn() throws {
        #expect(try Govee.isOn(fromState: fixture("govee-state.json")) == true)
    }

    @Test func aBadKeySaysSo() {
        #expect(throws: GoveeError(message: "Govee didn't accept that key.")) {
            try Govee.plugs(from: Data(#"{"message":"Invalid API Key","status":401}"#.utf8))
        }
    }

    @Test func anEmptyReplyIsAnError() {
        #expect(throws: GoveeError.self) { try Govee.plugs(from: Data()) }
    }
}

private func bodyOf(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}
