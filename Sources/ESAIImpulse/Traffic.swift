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
}

enum TrafficClient {
    static let endpoint = URL(string:"https://gw.dataimpulse.com:777/api/stats")!
    static func fetch(login: String, password: String, completion: @escaping (Result<TrafficStats,TrafficError>) -> Void) {
        var request = URLRequest(url:endpoint, cachePolicy:.reloadIgnoringLocalCacheData, timeoutInterval:25)
        let token = Data("\(login):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)",forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        URLSession(configuration:config).dataTask(with:request) { data, response, error in
            let result: Result<TrafficStats,TrafficError>
            if let error = error { result = .failure(.network(error.localizedDescription)) }
            else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                result = .failure(http.statusCode == 401 ? .unauthorized : .http(http.statusCode))
            } else if let data = data, let stats = try? JSONDecoder().decode(TrafficStats.self,from:data) {
                result = .success(stats)
            } else { result = .failure(.decoding) }
            DispatchQueue.main.async { completion(result) }
        }.resume()
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
