import Foundation

struct AccentPreset: Identifiable {
    let name: String
    let hex: String
    var id: String { hex }
    static let choices: [AccentPreset] = [
        .init(name:"esai 绿",hex:"#0A8552"),
        .init(name:"经典蓝",hex:"#2878ED"),
        .init(name:"鸢尾紫",hex:"#8054D6"),
        .init(name:"琥珀橙",hex:"#C66A08"),
        .init(name:"玫瑰红",hex:"#D5446F"),
        .init(name:"湖水青",hex:"#008A93")
    ]
}

struct AccentRGB {
    let red: Double
    let green: Double
    let blue: Double
    init?(hex: String) {
        let value = hex.trimmingCharacters(in:.whitespacesAndNewlines)
        let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }), let bits = UInt32(digits,radix:16) else { return nil }
        red = Double((bits >> 16) & 255)/255
        green = Double((bits >> 8) & 255)/255
        blue = Double(bits & 255)/255
    }
    init(red: Double, green: Double, blue: Double) {
        self.red = min(1,max(0,red)); self.green = min(1,max(0,green)); self.blue = min(1,max(0,blue))
    }
    var hex: String { String(format:"#%02X%02X%02X",Int((red*255).rounded()),Int((green*255).rounded()),Int((blue*255).rounded())) }
    private var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c/12.92 : pow((c+0.055)/1.055,2.4) }
        return 0.2126*linear(red)+0.7152*linear(green)+0.0722*linear(blue)
    }
    func readable(onDark: Bool) -> AccentRGB {
        var value = self
        // Preserve hue while keeping accented labels legible in either appearance.
        for _ in 0..<32 {
            if onDark ? value.luminance >= 0.32 : value.luminance <= 0.17 { break }
            let target = onDark ? 1.0 : 0.0
            value = AccentRGB(red:value.red*0.94+target*0.06,green:value.green*0.94+target*0.06,blue:value.blue*0.94+target*0.06)
        }
        return value
    }
}
