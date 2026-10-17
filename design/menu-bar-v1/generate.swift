import AppKit
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
func icon(_ pixels: Int) -> NSImage {
 let ctx = CGContext(data:nil,width:pixels,height:pixels,bitsPerComponent:8,bytesPerRow:pixels*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 ctx.scaleBy(x:CGFloat(pixels)/18,y:CGFloat(pixels)/18)
 ctx.translateBy(x:0,y:18);ctx.scaleBy(x:1,y:-1)
 ctx.setFillColor(NSColor.black.cgColor)
 ctx.fillEllipse(in:CGRect(x:1,y:1,width:16,height:16))
 ctx.setBlendMode(.clear)
 ctx.setStrokeColor(NSColor.black.cgColor); ctx.setLineWidth(2.2);ctx.setLineCap(.round)
 ctx.move(to:CGPoint(x:9,y:9));ctx.addLine(to:CGPoint(x:17,y:17));ctx.strokePath()
 // Short second cut keeps the quota wedge separate at menu-bar scale.
 ctx.setLineWidth(1.35);ctx.setLineCap(.butt)
 ctx.move(to:CGPoint(x:10.35,y:11.25));ctx.addLine(to:CGPoint(x:10.35,y:18));ctx.strokePath()
 return NSImage(cgImage:ctx.makeImage()!,size:NSSize(width:18,height:18))
}
func save(_ image:NSImage,_ name:String) {
 let data=NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
 try! data.write(to:dir.appendingPathComponent(name))
}
save(icon(18),"ToktaMenuTemplate.png")
save(icon(36),"ToktaMenuTemplate@2x.png")
save(icon(54),"ToktaMenuTemplate@3x.png")
let preview=NSImage(size:NSSize(width:1000,height:560))
preview.lockFocus()
NSColor(calibratedWhite:0.94,alpha:1).setFill();NSRect(x:0,y:0,width:1000,height:560).fill()
func text(_ s:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ color:NSColor) {
 (s as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:.medium),.foregroundColor:color])
}
text("TOKTA / MENU BAR",40,505,20,.black)
text("Monochrome token · diagonal cut · separate quota segment",40,472,14,.darkGray)
for (x,dark) in [(CGFloat(40),false),(CGFloat(520),true)] {
 let rect=NSRect(x:x,y:55,width:440,height:390)
 (dark ? NSColor(calibratedWhite:0.09,alpha:1) : NSColor.white).setFill()
 NSBezierPath(roundedRect:rect,xRadius:20,yRadius:20).fill()
 let color:NSColor=dark ? .white : .black
 let mark=icon(480)
 let tinted=NSImage(size:NSSize(width:480,height:480));tinted.lockFocus()
 mark.draw(in:NSRect(x:0,y:0,width:480,height:480));color.setFill();NSRect(x:0,y:0,width:480,height:480).fill(using:.sourceIn);tinted.unlockFocus()
 tinted.draw(in:NSRect(x:x+136,y:220,width:168,height:168))
 text(dark ? "DARK" : "LIGHT",x+24,406,12,dark ? .lightGray : .gray)
 text("18 pt · actual size",x+24,156,13,dark ? .lightGray : .gray)
 tinted.draw(in:NSRect(x:x+25,y:110,width:18,height:18))
 text("72%",x+50,109,13,color)
 text("Tokta",x+124,109,13,color)
}
preview.unlockFocus();save(preview,"preview.png")
