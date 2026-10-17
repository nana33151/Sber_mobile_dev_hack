import PrankLinker
import SwiftUI

/// Корень демо: экраны приложения + общие слои (джойстик, тост, панель отладки).
struct DemoRoot: View {

    @EnvironmentObject private var demo: DemoController

    var body: some View {
        Group {
            if demo.usesDesignScreens {
                DesignScreens()
            } else {
                MainScreen()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if demo.isSimulator && !demo.dismissesOnTouch {
                TiltJoystick { demo.manualTilt?.set($0) }
                    .padding(24)
                    .padding(.bottom, 80)
            }
        }
        .overlay(alignment: .top) {
            if let toast = demo.toast {
                Text(toast)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(.thinMaterial))
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: demo.toast)
        .sheet(isPresented: $demo.showsDebug) {
            DebugPanel().environmentObject(demo)
        }
    }
}
