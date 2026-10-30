import Foundation

/// A named snapshot of the status bar style and typography.
struct StatusConfig: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var style: StatusStyle
    var typography: StatusTypography
    var isBuiltIn: Bool { id == StatusConfig.builtInID }
    static let builtInID = "builtin.default"
    static let builtIn = StatusConfig(id:builtInID, name:"默认", style:.iconText, typography:.defaults)
    func matches(style s: StatusStyle, typography t: StatusTypography) -> Bool { style == s && typography.clamped() == t.clamped() }
}

/// Persists user configurations as JSON in UserDefaults ("sb.configs"); the built-in 默认 is never stored.
enum StatusConfigStore {
    static let configsKey = "sb.configs", activeKey = "sb.activeConfig"
    static func load(_ d: UserDefaults) -> [StatusConfig] {
        let saved = d.data(forKey:configsKey).flatMap { try? JSONDecoder().decode([StatusConfig].self, from:$0) } ?? []
        return [StatusConfig.builtIn] + saved.filter { !$0.isBuiltIn }.map { var c = $0; c.typography = c.typography.clamped(); return c }
    }
    static func save(_ configs: [StatusConfig], _ d: UserDefaults) {
        let user = configs.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(user) { d.set(data, forKey:configsKey) }
    }
    static func exportJSON(_ configs: [StatusConfig]) -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? e.encode(configs.filter { !$0.isBuiltIn })) ?? Data("[]".utf8)
    }
    /// Merges imported configurations; imported entries get fresh ids so nothing existing is overwritten.
    static func importJSON(_ data: Data, into configs: [StatusConfig]) -> [StatusConfig]? {
        guard let list = try? JSONDecoder().decode([StatusConfig].self, from:data) else { return nil }
        return configs + list.filter { !$0.isBuiltIn }.map {
            var c = $0; c.id = UUID().uuidString; c.typography = c.typography.clamped(); return c
        }
    }
    static func nextName(_ configs: [StatusConfig], prefix: String) -> String {
        var n = 1
        while configs.contains(where:{ $0.name == "\(prefix) \(n)" }) { n += 1 }
        return "\(prefix) \(n)"
    }
}
