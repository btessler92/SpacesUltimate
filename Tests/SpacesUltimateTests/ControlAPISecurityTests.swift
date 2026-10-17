import Network
import XCTest
@testable import SpacesUltimate

final class ControlAPISecurityTests: XCTestCase {
    func testDeveloperAPIRequiresOptInAndPreservesExplicitPreferences() throws {
        XCTAssertFalse(AppSettings.defaults.apiEnabled)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).apiEnabled)
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: Data(#"{"apiEnabled":true}"#.utf8)).apiEnabled)
    }

    @MainActor
    func testListenerBindsOnlyIPv4Loopback() {
        let parameters = AppControlAPI.listenerParameters(port: 37655)
        XCTAssertEqual(parameters.requiredLocalEndpoint, .hostPort(host: "127.0.0.1", port: 37655))
    }

    func testLocalCommandLineRequestsAreAccepted() {
        for host in ["127.0.0.1:37655", "localhost:37655"] {
            XCTAssertTrue(ControlAPIRequestPolicy.allows("GET /status HTTP/1.1\r\nHost: \(host)\r\nUser-Agent: curl\r\n\r\n", port: 37655))
        }
    }

    func testBrowserRequestsAreRejected() {
        for header in ["Origin: https://example.com", "Origin: null", "Referer: https://example.com/", "Sec-Fetch-Site: cross-site", "sec-fetch-mode: navigate"] {
            XCTAssertFalse(ControlAPIRequestPolicy.allows("GET /screenshot HTTP/1.1\r\nHost: 127.0.0.1:37655\r\n\(header)\r\n\r\n", port: 37655))
        }
    }

    func testRebindingAndMalformedRequestsAreRejected() {
        for request in [
            "GET /status HTTP/1.1\r\nHost: attacker.example:37655\r\n\r\n",
            "GET /status HTTP/1.1\r\nHost: 127.0.0.1:80\r\n\r\n",
            "GET /status HTTP/1.1\r\n\r\n",
            "GET /status HTTP/1.1\r\nHost: 127.0.0.1:37655\r\nHost: localhost:37655\r\n\r\n",
            "GET /status HTTP/1.1\r\nHost: 127.0.0.1:37655\r\n",
            "POST /status HTTP/1.1\r\nHost: 127.0.0.1:37655\r\n\r\n",
            "GET //example.com HTTP/1.1\r\nHost: 127.0.0.1:37655\r\n\r\n"
        ] {
            XCTAssertFalse(ControlAPIRequestPolicy.allows(request, port: 37655), request)
        }
    }
}
