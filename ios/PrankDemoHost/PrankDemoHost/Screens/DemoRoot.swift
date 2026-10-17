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
            // В симуляторе нет датчиков: наклон — джойстиком (или стрелками на клавиатуре).
            if demo.isSimulator {
                TiltJoystick { demo.manualTilt?.set($0) }
                    .background(GeometryReader { proxy in
                        Color.clear
                            .onAppear { demo.joystickFrame = proxy.frame(in: .global) }
                            .onChange(of: proxy.frame(in: .global)) { demo.joystickFrame = $0 }
                    })
                    .padding(24)
                    .padding(.bottom, 80)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Размыть фон под игрой. Нажатие не закрывает прикол — можно переключать прямо во время игры.
            Button {
                demo.blursBackground.toggle()
            } label: {
                Label(demo.blursBackground ? "Фон: размыт" : "Размыть фон",
                      systemImage: demo.blursBackground ? "drop.fill" : "drop")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { demo.blurButtonFrame = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { demo.blurButtonFrame = $0 }
            })
            .padding(.trailing, 12)
            .padding(.top, 4)
            .accessibilityLabel("Размыть фон под игрой")
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
