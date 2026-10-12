import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 180),
                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "InputPilot Test"
let field = NSTextField(frame: NSRect(x: 30, y: 60, width: 360, height: 28))
field.placeholderString = "InputPilot integration fixture"
window.contentView?.addSubview(field)
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
app.run()
