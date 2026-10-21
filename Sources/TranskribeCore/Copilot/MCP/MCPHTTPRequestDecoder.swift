import Foundation

/// Decodes one HTTP/1 request. The caller closes the connection after its response.
public enum MCPHTTPRequestDecoder {
    public enum Result {
        case incomplete
        case request(MCPHTTPHandler.Request)
        case failure(Int)
    }

    public static func decode(_ data: Data) -> Result {
        guard data.count <= 2_097_152 else { return .failure(413) }
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 16_384 ? .failure(431) : .incomplete
        }
        guard boundary.upperBound <= 16_384 else { return .failure(431) }
        guard let head = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { return .failure(400) }
        let lines = head.components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ")
        guard start.count == 3, start[2] == "HTTP/1.1" || start[2] == "HTTP/1.0", start[1].hasPrefix("/") else { return .failure(400) }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .failure(400) }
            let name = String(line[..<colon]).lowercased()
            guard !name.isEmpty, name.utf8.allSatisfy({ (33...126).contains($0) && $0 != 58 }),
                  headers[name] == nil else { return .failure(400) }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let body = Data(data[boundary.upperBound...])
        if let encoding = headers["transfer-encoding"] {
            guard encoding.lowercased() == "chunked", headers["content-length"] == nil else { return .failure(400) }
            return decodeChunks(body, method: String(start[0]), path: String(start[1]), headers: headers)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return .failure(400) }
        guard length <= MCPHTTPHandler.maximumBodyBytes else { return .failure(413) }
        guard body.count >= length else { return .incomplete }
        return .request(.init(method: String(start[0]), path: String(start[1]), headers: headers, body: Data(body.prefix(length))))
    }

    private static func decodeChunks(_ data: Data, method: String, path: String, headers: [String: String]) -> Result {
        var offset = data.startIndex
        var body = Data()
        let crlf = Data("\r\n".utf8)
        while true {
            guard let end = data.range(of: crlf, in: offset..<data.endIndex) else { return .incomplete }
            guard let line = String(data: data[offset..<end.lowerBound], encoding: .ascii),
                  let sizeText = line.split(separator: ";", maxSplits: 1).first,
                  let size = Int(sizeText, radix: 16), size >= 0 else { return .failure(400) }
            guard size <= MCPHTTPHandler.maximumBodyBytes - body.count else { return .failure(413) }
            offset = end.upperBound
            if size == 0 {
                guard data.count - offset >= 2 else { return .incomplete }
                guard data[offset..<(offset + 2)] == crlf else { return .failure(400) }
                return .request(.init(method: method, path: path, headers: headers, body: body))
            }
            guard data.count - offset >= size + 2 else { return .incomplete }
            body.append(data[offset..<(offset + size)])
            offset += size
            guard data[offset..<(offset + 2)] == crlf else { return .failure(400) }
            offset += 2
        }
    }
}
