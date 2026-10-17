import AppKit
import Foundation

let app = NSApplication.shared
private var retainedDelegate: AppDelegate? = AppDelegate()
app.delegate = retainedDelegate
app.setActivationPolicy(.accessory)
app.run()
