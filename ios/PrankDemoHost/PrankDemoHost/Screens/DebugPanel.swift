import PrankLinker
import SwiftUI

/// Панель для демо и отладки: вызвать прикол, прогнать сбои, посмотреть лог.
struct DebugPanel: View {

    @EnvironmentObject private var demo: DemoController
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Запуск")) {
                    Button("Как тряска (триггер из конфига)") { closeThen { demo.linker.handleShakeMotion(.motionShake) } }
                    Button("Скрыть прикол") { demo.linker.hide() }
                    Button("Перечитать конфиг") { Task { await demo.linker.reloadConfig() } }
                    Toggle("Сломать загрузку игры", isOn: $demo.failsGameLoading)
                    Toggle("Закрывать касанием", isOn: $demo.dismissesOnTouch)
                    Toggle("Экраны из макета Figma", isOn: $demo.usesDesignScreens)
                        .disabled(!DesignImages.areAvailable)
                }

                Section(header: Text("Приколы и тесты сбоев")) {
                    ForEach(DemoController.payloadIDs, id: \.self) { id in
                        Button(id) { closeThen { demo.linker.show(payloadID: id) } }
                    }
                }

                Section(header: HStack {
                    Text("Лог")
                    Spacer()
                    Button("Очистить") { demo.clearLog() }.font(.caption)
                }) {
                    if demo.log.isEmpty {
                        Text("Пока пусто").foregroundColor(.secondary)
                    }
                    ForEach(demo.log) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.time, style: .time).font(.caption2).foregroundColor(.secondary)
                            Text(entry.text).font(.footnote).foregroundColor(entry.isProblem ? .red : .primary)
                        }
                    }
                }
            }
            .navigationTitle("Прикол: отладка")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Прикол показывается поверх всего, поэтому сначала убираем панель.
    private func closeThen(_ action: @escaping @MainActor () -> Void) {
        presentationMode.wrappedValue.dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            action()
        }
    }
}
