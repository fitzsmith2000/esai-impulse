// Renders AppIcon.iconset PNGs: rounded accent square + radio-waves symbol.
import AppKit
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath:out,withIntermediateDirectories:true)
for (base,scales) in [(16,[1,2]),(32,[1,2]),(128,[1,2]),(256,[1,2]),(512,[1,2])] {
    for s in scales {
        let px = base*s
        let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:px,pixelsHigh:px,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)
        let r = CGFloat(px), inset = r*0.1
        let rect = NSRect(x:inset,y:inset,width:r-2*inset,height:r-2*inset)
        let path = NSBezierPath(roundedRect:rect,xRadius:rect.width*0.225,yRadius:rect.width*0.225)
        NSGradient(starting:NSColor(srgbRed:0.10,green:0.62,blue:0.42,alpha:1),ending:NSColor(srgbRed:0.02,green:0.42,blue:0.27,alpha:1))!.draw(in:path,angle:-90)
        let cfg = NSImage.SymbolConfiguration(pointSize:r*0.42,weight:.semibold).applying(.init(paletteColors:[.white]))
        if let sym = NSImage(systemSymbolName:"antenna.radiowaves.left.and.right",accessibilityDescription:nil)?.withSymbolConfiguration(cfg) {
            let sz = sym.size
            sym.draw(in:NSRect(x:(r-sz.width)/2,y:(r-sz.height)/2,width:sz.width,height:sz.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        let name = s == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"\(out)/\(name)"))
    }
}
