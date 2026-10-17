import Foundation

/// The optional developer API is for local tools, not web pages. It has no user authentication.
enum ControlAPIRequestPolicy {
    static func allows(_ request: String, port: UInt16) -> Bool {
        guard let headerEnd = request.range(of: "\r\n\r\n") else { return false }
        let lines = request[..<headerEnd.lowerBound].components(separatedBy: "\r\n")
        guard let first = lines.first else { return false }
        let parts = first.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/"),
              !parts[1].hasPrefix("//"), parts[2] == "HTTP/1.1" else { return false }

        var host: String?
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"),
                  line.first != " ", line.first != "\t" else { return false }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            // Reject browser requests, including navigation and DNS rebinding requests.
            if name == "origin" || name == "referer" || name.hasPrefix("sec-fetch-") { return false }
            if name == "host" {
                guard host == nil else { return false }
                host = value
            }
        }
        return host == "127.0.0.1:\(port)" || host == "localhost:\(port)"
    }
}
