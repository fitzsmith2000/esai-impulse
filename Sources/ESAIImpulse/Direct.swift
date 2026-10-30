import Foundation
import Network

/// How a refresh reached the DataImpulse gateway.
enum Route: String, Codable { case system, direct }

/// User preference in Settings.
enum ConnectionMode: String, CaseIterable { case auto, system, direct }

/// Minimal HTTPS/1.1 client on Network.framework that can be pinned to the physical
/// interface, bypassing TUN-mode proxies/VPNs (e.g. Clash fake-ip). Certificates are
/// validated normally against `serverName`.
enum DirectHTTP {
    static let queue = DispatchQueue(label:"esai-impulse.direct")

    /// First active physical interface (Wi-Fi preferred over Ethernet), never utun/other.
    static func physicalInterface(completion: @escaping (NWInterface?) -> Void) {
        let monitor = NWPathMonitor(prohibitedInterfaceTypes:[.other,.loopback,.cellular])
        var done = false
        monitor.pathUpdateHandler = { path in
            guard !done else { return }
            done = true
            let candidates = path.availableInterfaces.filter { !$0.name.hasPrefix("utun") && ($0.type == .wifi || $0.type == .wiredEthernet) }
            let pick = candidates.first(where:{ path.usesInterfaceType($0.type) }) ?? candidates.first
            monitor.cancel()
            completion(pick)
        }
        monitor.start(queue:queue)
        queue.asyncAfter(deadline:.now()+3) { if !done { done = true; monitor.cancel(); completion(nil) } }
    }

    struct Response { let status: Int; let body: Data }

    static func get(ip: String, port: UInt16 = 443, serverName: String, path: String, headers: [String:String] = [:],
                    interface: NWInterface?, timeout: TimeInterval = 15,
                    completion: @escaping (Result<Response,TrafficError>) -> Void) {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, serverName)
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
        let tcp = NWProtocolTCP.Options(); tcp.connectionTimeout = Int(timeout)
        let params = NWParameters(tls:tls, tcp:tcp)
        params.prohibitedInterfaceTypes = [.other]
        if let interface = interface { params.requiredInterface = interface }
        guard let nwPort = NWEndpoint.Port(rawValue:port) else { return completion(.failure(.network("bad port"))) }
        let connection = NWConnection(host:NWEndpoint.Host(ip), port:nwPort, using:params)
        var finished = false
        var buffer = Data()
        func finish(_ result: Result<Response,TrafficError>) {
            guard !finished else { return }
            finished = true
            connection.cancel()
            DispatchQueue.main.async { completion(result) }
        }
        func receive() {
            connection.receive(minimumIncompleteLength:1, maximumLength:65536) { data, _, complete, error in
                if let data = data { buffer.append(data) }
                if let parsed = parse(buffer), parsed.complete { return finish(.success(parsed.response)) }
                if complete || error != nil {
                    if let parsed = parse(buffer) { finish(.success(parsed.response)) }
                    else { finish(.failure(.network(error?.localizedDescription ?? "connection closed"))) }
                    return
                }
                receive()
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                var request = "GET \(path) HTTP/1.1\r\nHost: \(serverName)\(port == 443 ? "" : ":\(port)")\r\nUser-Agent: ESAI-Impulse\r\nAccept: */*\r\nConnection: close\r\n"
                for (k,v) in headers { request += "\(k): \(v)\r\n" }
                request += "\r\n"
                connection.send(content:Data(request.utf8), completion:.contentProcessed { error in
                    if let error = error { finish(.failure(.network(error.localizedDescription))) } else { receive() }
                })
            case .failed(let error): finish(.failure(.network(error.localizedDescription)))
            case .waiting(let error): finish(.failure(.network(error.localizedDescription)))
            default: break
            }
        }
        connection.start(queue:queue)
        queue.asyncAfter(deadline:.now()+timeout) { finish(.failure(.network("timed out"))) }
    }

    /// Parses an HTTP/1.1 response; `complete` is true once the full body is present.
    static func parse(_ data: Data) -> (response: Response, complete: Bool)? {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of:separator),
              let head = String(data:data[..<range.lowerBound], encoding:.utf8) else { return nil }
        let lines = head.components(separatedBy:"\r\n")
        let parts = lines.first?.split(separator:" ") ?? []
        guard parts.count >= 2, let status = Int(parts[1]) else { return nil }
        var headers: [String:String] = [:]
        for line in lines.dropFirst() {
            if let i = line.firstIndex(of:":") {
                headers[line[..<i].lowercased()] = line[line.index(after:i)...].trimmingCharacters(in:.whitespaces)
            }
        }
        let raw = Data(data[range.upperBound...])
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            var body = Data(); var cursor = raw.startIndex
            while true {
                guard let lineEnd = raw[cursor...].range(of:Data("\r\n".utf8)),
                      let sizeText = String(data:raw[cursor..<lineEnd.lowerBound], encoding:.utf8),
                      let size = Int(sizeText.split(separator:";").first.map(String.init)?.trimmingCharacters(in:.whitespaces) ?? "", radix:16)
                else { return (Response(status:status, body:body), false) }
                if size == 0 { return (Response(status:status, body:body), true) }
                let start = lineEnd.upperBound
                guard raw.distance(from:start, to:raw.endIndex) >= size + 2 else { return (Response(status:status, body:body), false) }
                let end = raw.index(start, offsetBy:size)
                body.append(raw[start..<end]); cursor = raw.index(end, offsetBy:2)
            }
        }
        if let length = headers["content-length"].flatMap(Int.init) {
            return (Response(status:status, body:raw.prefix(length)), raw.count >= length)
        }
        return (Response(status:status, body:raw), false)
    }
}

/// Real A records via DNS-over-HTTPS, skipping proxy fake-ip ranges (198.18.0.0/15).
enum RealDNS {
    static func isFake(_ ip: String) -> Bool { ip.hasPrefix("198.18.") || ip.hasPrefix("198.19.") }
    static func addresses(from data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let answers = json["Answer"] as? [[String:Any]] else { return [] }
        return answers.compactMap { ($0["type"] as? Int) == 1 ? $0["data"] as? String : nil }
            .filter { !isFake($0) && $0.split(separator:".").count == 4 }
    }
    static func resolve(_ host: String, interface: NWInterface?, completion: @escaping ([String]) -> Void) {
        let query = "name=\(host)&type=A"
        let viaSystem = ["https://dns.google/resolve?\(query)", "https://cloudflare-dns.com/dns-query?\(query)"]
        // Fallback over the physical interface to well-known resolver IPs (certs cover these names).
        let viaDirect: [(String,String,String)] = [("8.8.8.8","dns.google","/resolve?\(query)"),
                                                  ("1.1.1.1","cloudflare-dns.com","/dns-query?\(query)")]
        func direct(_ i: Int) {
            guard i < viaDirect.count else { return completion([]) }
            let (ip,name,path) = viaDirect[i]
            DirectHTTP.get(ip:ip, serverName:name, path:path, headers:["Accept":"application/dns-json"], interface:interface, timeout:8) { result in
                if case .success(let r) = result, r.status == 200, case let ips = addresses(from:r.body), !ips.isEmpty { completion(ips) }
                else { direct(i+1) }
            }
        }
        func system(_ i: Int) {
            guard i < viaSystem.count, let url = URL(string:viaSystem[i]) else { return direct(0) }
            var request = URLRequest(url:url, cachePolicy:.reloadIgnoringLocalCacheData, timeoutInterval:8)
            request.setValue("application/dns-json", forHTTPHeaderField:"Accept")
            URLSession(configuration:.ephemeral).dataTask(with:request) { data, response, _ in
                let ips = data.map(addresses(from:)) ?? []
                DispatchQueue.main.async { ips.isEmpty ? system(i+1) : completion(ips) }
            }.resume()
        }
        system(0)
    }
}
