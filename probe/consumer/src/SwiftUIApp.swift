import SwiftUI
import Teak

struct ProbeApp: App {
  @Environment(\.scenePhase) var phase
  init() {
    TeakLink.registerRoute("/c2196/:kind", name: "c2196", description: "probe") { p in NSLog("PROBE: route %@", String(describing: p["kind"])) }
    Teak.sharedInstance()?.identifyUser("c-2196-probe-swiftui")
  }
  var body: some Scene {
    WindowGroup {
      Text("probe").onOpenURL { url in NSLog("PROBE: swiftui onOpenURL %@", url.absoluteString) }
    }
    .onChange(of: phase) { p in NSLog("PROBE: scenePhase %@", String(describing: p)) }
  }
}
