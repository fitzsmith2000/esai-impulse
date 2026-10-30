import Foundation
import Security

/// Shape of `GET https://gw.dataimpulse.com:777/api/stats`. Values are bytes.
struct TrafficStats: Codable, Equatable {
    var total: Double
    var used: Double
    var left: Double
    enum CodingKeys: String, CodingKey { case total = "total_traffic", used = "traffic_used", left = "traffic_left" }
    init(total: Double, used: Double, left: Double) { self.total = total; self.used = used; self.left = left }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        func number(_ key: CodingKeys) throws -> Double {
            if let v = try? c.decode(Double.self,forKey:key) { return v }
            if let s = try? c.decode(String.self,forKey:key), let v = Double(s) { return v }
            throw DecodingError.dataCorruptedError(forKey:key,in:c,debugDescription:"not a number")
        }
        left = try number(.left)
        total = (try? number(.total)) ?? 0
        used = (try? number(.used)) ?? max(0,total-left)
    }
    static func gb(_ bytes: Double) -> Double { bytes/1e9 }
    var leftGB: Double { Self.gb(left) }
    var usedFraction: Double { total > 0 ? min(1,max(0,used/total)) : 0 }
}

enum TrafficError: Error {
    case missingCredentials, unauthorized, http(Int), decoding, network(String)
    /// The system route failed at the network/TLS layer (typical of a proxy/VPN dropping it).
    case blocked(system: String, direct: String?)
    var fallbackEligible: Bool { if case .network = self { return true }; return false }
    var message: String { if case .network(let m) = self { return m }; return "\(self)" }
}

/// Fetches stats over the normal system network, or directly over the physical interface.
enum TrafficClient {
    static let host = "gw.dataimpulse.com"
    static let port: UInt16 = 777
    static let endpoint = URL(string:"https://gw.dataimpulse.com:777/api/stats")!
    /// Route that last worked; tried first in auto mode. Cleared on network changes.
    static var preferredRoute: Route?
    static var cachedIPs: [String] = []
    static func resetCache() { preferredRoute = nil; cachedIPs = [] }

    static func authorization(_ login: String?, _ password: String?) -> String? {
        guard let l = login, let p = password else { return nil }
        return "Basic " + Data("\(l):\(p)".utf8).base64EncodedString()
    }

    static func fetch(login: String, password: String, mode: ConnectionMode,
                      completion: @escaping (Result<(TrafficStats,Route),TrafficError>) -> Void) {
        let auth = authorization(login,password)
        let order: [Route]
        switch mode {
        case .system: order = [.system]
        case .direct: order = [.direct]
        case .auto: order = preferredRoute == .direct ? [.direct,.system] : [.system,.direct]
        }
        var errors: [Route:TrafficError] = [:]
        func attempt(_ index: Int) {
            guard index < order.count else {
                let sys = errors[.system]?.message, dir = errors[.direct]?.message
                if let sys = sys { return completion(.failure(.blocked(system:sys, direct:dir))) }
                return completion(.failure(.network(dir ?? "unknown")))
            }
            let route = order[index]
            raw(route:route, authorization:auth) { result in
                switch result {
                case .success(let r):
                    if r.status == 401 { return completion(.failure(.unauthorized)) }
                    guard r.status == 200 else { return completion(.failure(.http(r.status))) }
                    guard let stats = try? JSONDecoder().decode(TrafficStats.self, from:r.body) else { return completion(.failure(.decoding)) }
                    preferredRoute = route
                    completion(.success((stats,route)))
                case .failure(let e):
                    errors[route] = e
                    if e.fallbackEligible { attempt(index+1) } else { completion(.failure(e)) }
                }
            }
        }
        attempt(0)
    }

    /// One request over one route; returns status + body without interpreting them.
    static func raw(route: Route, authorization: String?, completion: @escaping (Result<DirectHTTP.Response,TrafficError>) -> Void) {
        switch route {
        case .system:
            var request = URLRequest(url:endpoint, cachePolicy:.reloadIgnoringLocalCacheData, timeoutInterval:20)
            if let auth = authorization { request.setValue(auth, forHTTPHeaderField:"Authorization") }
            request.setValue("application/json", forHTTPHeaderField:"Accept")
            let config = URLSessionConfiguration.ephemeral; config.urlCache = nil
            URLSession(configuration:config).dataTask(with:request) { data, response, error in
                let result: Result<DirectHTTP.Response,TrafficError>
                if let error = error { result = .failure(.network(error.localizedDescription)) }
                else if let http = response as? HTTPURLResponse { result = .success(.init(status:http.statusCode, body:data ?? Data())) }
                else { result = .failure(.network("no response")) }
                DispatchQueue.main.async { completion(result) }
            }.resume()
        case .direct:
            DirectHTTP.physicalInterface { interface in
                DispatchQueue.main.async {
                    guard let interface = interface else { return completion(.failure(.network("no physical network interface"))) }
                    let go: ([String]) -> Void = { ips in
                        guard !ips.isEmpty else { return completion(.failure(.network("DNS-over-HTTPS lookup failed"))) }
                        cachedIPs = ips
                        var headers = ["Accept":"application/json"]
                        if let auth = authorization { headers["Authorization"] = auth }
                        func tryIP(_ i: Int, _ last: TrafficError?) {
                            guard i < ips.count else { cachedIPs = []; return completion(.failure(last ?? .network("unreachable"))) }
                            DirectHTTP.get(ip:ips[i], port:port, serverName:host, path:"/api/stats", headers:headers, interface:interface, timeout:15) { result in
                                if case .failure(let e) = result { tryIP(i+1, e) } else { completion(result) }
                            }
                        }
                        tryIP(0, nil)
                    }
                    if !cachedIPs.isEmpty { go(cachedIPs) } else { RealDNS.resolve(host, interface:interface, completion:go) }
                }
            }
        }
    }
}

/// Credentials live only in the login Keychain.
enum CredentialStore {
    static let service = "com.fitzsmith2000.esai-impulse"
    private static func query(_ account: String) -> [String:Any] {
        [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:account]
    }
    static func read(_ account: String) -> String? {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary,&item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data:data,encoding:.utf8)
    }
    @discardableResult static func write(_ account: String, _ value: String) -> Bool {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(account); q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(q as CFDictionary,nil) == errSecSuccess
        }
        return status == errSecSuccess
    }
    static func delete(_ account: String) { SecItemDelete(query(account) as CFDictionary) }
    static var credentials: (String,String)? {
        guard let l = read("login"), let p = read("password"), !l.isEmpty, !p.isEmpty else { return nil }
        return (l,p)
    }
}

enum AlertLevel: Int, Codable { case normal = 0, low = 1, depleted = 2
    static func of(leftGB: Double, threshold: Double) -> AlertLevel {
        leftGB <= 0 ? .depleted : leftGB < threshold ? .low : .normal
    }
}

/// Fire once per downward crossing; re-arm when traffic recovers.
func alertTransition(previous: AlertLevel, current: AlertLevel) -> AlertLevel? {
    current.rawValue > previous.rawValue ? current : nil
}

func formatGB(_ gb: Double, locale: Locale = Locale(identifier:"en_US")) -> String {
    let f = NumberFormatter(); f.locale = locale; f.numberStyle = .decimal
    f.minimumFractionDigits = 1; f.maximumFractionDigits = 1
    return (f.string(from:NSNumber(value:gb)) ?? String(format:"%.1f",gb)) + " GB"
}
/// Status bar text: negative remaining shows as `0 GB`.
func statusText(leftGB: Double) -> String { leftGB <= 0 ? "0 GB" : formatGB(leftGB) }
