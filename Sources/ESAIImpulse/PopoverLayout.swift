import Foundation
import CoreGraphics

enum PopoverLayout {
    static let preferredSize = CGSize(width:400,height:540)
    static let screenMargin: CGFloat = 8
    static let chromeAllowance: CGFloat = 28

    static func size(available: CGSize) -> CGSize {
        CGSize(width:min(preferredSize.width,max(1,available.width-chromeAllowance-2*screenMargin)),
               height:min(preferredSize.height,max(1,available.height-chromeAllowance-2*screenMargin)))
    }

    static func origin(for frame: CGRect, inside visible: CGRect) -> CGPoint {
        let bounds = visible.insetBy(dx:screenMargin,dy:screenMargin)
        return CGPoint(x:max(bounds.minX,min(frame.minX,bounds.maxX-frame.width)),
                       y:max(bounds.minY,min(frame.minY,bounds.maxY-frame.height)))
    }

    static func anchoredOrigin(for frame: CGRect, inside visible: CGRect, anchor: CGRect) -> CGPoint {
        // The arrow can meet the menu bar. Reserve margins only at the sides and bottom.
        let top = max(visible.minY + frame.height + screenMargin, anchor.minY)
        return CGPoint(x:max(visible.minX+screenMargin,min(frame.minX,visible.maxX-screenMargin-frame.width)),
                       y:max(visible.minY+screenMargin,top-frame.height))
    }
}
