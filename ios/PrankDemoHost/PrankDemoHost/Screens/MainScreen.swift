import PrankLinker
import SwiftUI

/// Условный главный экран СберKids: поверх него появляется прикол.
struct MainScreen: View {

    @EnvironmentObject private var demo: DemoController

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Привет, Маша!")
                        .font(.largeTitle.bold())
                    Text("Потряси телефон — что-то будет 🙂")
                        .foregroundColor(.secondary)

                    card(title: "Копилка", subtitle: "Велосипед", value: "1 250 из 8 000", color: Color(red: 0.13, green: 0.63, blue: 0.22))
                    card(title: "Карманные деньги", subtitle: "На карте", value: "340 ₽", color: Color(red: 0.2, green: 0.45, blue: 0.9))

                    HStack(spacing: 12) {
                        NavigationLink(destination: PaymentScreen()) { action("Оплатить", "creditcard") }
                        NavigationLink(destination: PaymentScreen(title: "Перевод")) { action("Перевести", "arrow.left.arrow.right") }
                    }

                    Text("Дела на сегодня").font(.title3.bold()).padding(.top, 8)
                    ForEach(["Почистить зубы", "Сделать уроки", "Погулять с собакой", "Прочитать главу книги"], id: \.self) { task in
                        HStack {
                            Image(systemName: "circle")
                            Text(task)
                            Spacer()
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    }
                }
                .padding(16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { demo.showsDebug = true } label: { Image(systemName: "ladybug") }
                        .accessibilityLabel("Панель отладки прикола")
                }
            }
            .onAppear { demo.linker.screenAllowsPranks = true }
        }
        .navigationViewStyle(.stack)
    }

    private func card(title: String, subtitle: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).opacity(0.85)
            Text(value).font(.title2.bold())
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20).fill(color))
    }

    private func action(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.tertiarySystemFill)))
    }
}

/// Экран оплаты: приколы здесь запрещены (бизнес-ограничение трека).
struct PaymentScreen: View {
    @EnvironmentObject private var demo: DemoController
    var title = "Оплата"

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield").font(.system(size: 48))
            Text("\(title): приколы здесь не показываются")
                .multilineTextAlignment(.center)
            Text("Потрясите телефон — в логе будет «экран запрещает приколы»")
                .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .navigationTitle(title)
        .onAppear { demo.linker.screenAllowsPranks = false }
        .onDisappear { demo.linker.screenAllowsPranks = true }
    }
}

/// Виртуальный наклон для симулятора: тянуть ручку — как наклонять телефон.
struct TiltJoystick: View {
    let onChange: (PrankTilt) -> Void
    @State private var offset: CGSize = .zero
    private let radius: CGFloat = 56

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).frame(width: radius * 2, height: radius * 2)
            Circle().fill(Color.accentColor).frame(width: 40, height: 40).offset(offset)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dx = value.translation.width, dy = value.translation.height
                    let length = max(1, (dx * dx + dy * dy).squareRoot())
                    let scale = min(1, radius / length)
                    offset = CGSize(width: dx * scale, height: dy * scale)
                    onChange(PrankTilt(x: Double(offset.width / radius), y: Double(offset.height / radius)))
                }
                .onEnded { _ in
                    offset = .zero
                    onChange(.zero)
                }
        )
        .accessibilityLabel("Наклон телефона")
    }
}
