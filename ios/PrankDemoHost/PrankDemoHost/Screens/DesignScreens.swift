import PrankLinker
import SwiftUI
import UIKit

/// Экраны СберKids из макета Figma — картинками с зонами нажатия.
/// Нужны, чтобы на защите прикол появлялся поверх «настоящего» интерфейса.
/// Картинки сняты с макета без строки статуса Android и навигационной панели.
enum DesignImages {
    static let home = "design_home.jpg"
    static let tabBar = "design_tabbar.png"
    static let piggy = "design_piggy.jpg"
    static let tasks = "design_tasks.jpg"
    static let limits = "design_limits.jpg"

    static var areAvailable: Bool { UIImage(named: home) != nil && UIImage(named: tabBar) != nil }

    /// Фон макета: им заливаем область под строкой статуса iOS.
    static let background = Color(red: 0.953, green: 0.957, blue: 0.965)
}

/// Зона нажатия в пикселях исходной картинки.
struct Hotspot: Identifiable {
    let id = UUID()
    let rect: CGRect
    let label: String
    let action: () -> Void

    init(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ label: String, action: @escaping () -> Void) {
        rect = CGRect(x: x, y: y, width: width, height: height)
        self.label = label
        self.action = action
    }
}

struct DesignScreens: View {

    enum Tab { case home, piggy, tasks }

    @EnvironmentObject private var demo: DemoController
    @State private var tab: Tab = .home
    @State private var showsLimits = false

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                DesignImages.background.ignoresSafeArea()

                switch tab {
                case .home:
                    DesignImageScreen(imageName: DesignImages.home, bottomInset: 110) { [
                        // «Скинуть денег» — перевод: экран лимитов, где приколы запрещены.
                        Hotspot(170, 664, 255, 214, "Скинуть денег") { showsLimits = true }
                    ] }
                case .piggy:
                    DesignImageScreen(imageName: DesignImages.piggy, bottomInset: 110) { [
                        Hotspot(43, 28, 100, 100, "Назад") { tab = .home },
                        Hotspot(327, 1313, 283, 260, "Перевести") { showsLimits = true }
                    ] }
                case .tasks:
                    DesignImageScreen(imageName: DesignImages.tasks, bottomInset: 110) { [
                        Hotspot(43, 28, 100, 100, "Назад") { tab = .home }
                    ] }
                }

                tabBar

                NavigationLink(destination: LimitsDesignScreen(), isActive: $showsLimits) { EmptyView() }
                    .hidden()
            }
            .navigationBarHidden(true)
            .onAppear { demo.linker.screenAllowsPranks = true }
        }
        .navigationViewStyle(.stack)
        .overlay(alignment: .bottomLeading) {
            Button { demo.showsDebug = true } label: {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
            .padding(.leading, 12)
            .padding(.bottom, 96)
            .accessibilityLabel("Панель отладки прикола")
        }
    }

    /// Нижнее меню из макета. Лапка по центру — запустить прикол без тряски (удобно в симуляторе).
    private var tabBar: some View {
        DesignImageView(imageName: DesignImages.tabBar) { [
            Hotspot(35, 30, 124, 150, "Главный") { tab = .home },
            Hotspot(159, 30, 124, 150, "Копилки") { tab = .piggy },
            Hotspot(283, 20, 124, 170, "Лапка: прикол") { demo.linker.trigger() },
            Hotspot(407, 30, 124, 150, "Дела") { tab = .tasks },
            Hotspot(531, 30, 124, 150, "Контент") {}
        ] }
        .background(DesignImages.background.ignoresSafeArea(edges: .bottom))
    }
}

/// Экран лимитов — из тех, где приколы запрещены (бизнес-ограничение трека).
struct LimitsDesignScreen: View {
    @EnvironmentObject private var demo: DemoController
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack {
            DesignImages.background.ignoresSafeArea()
            DesignImageScreen(imageName: DesignImages.limits, bottomInset: 24) { [
                Hotspot(43, 28, 100, 100, "Назад") { presentationMode.wrappedValue.dismiss() }
            ] }
        }
        .navigationBarHidden(true)
        .onAppear { demo.linker.screenAllowsPranks = false }
        .onDisappear { demo.linker.screenAllowsPranks = true }
    }
}

/// Прокручиваемая картинка экрана на всю ширину.
struct DesignImageScreen: View {
    let imageName: String
    var bottomInset: CGFloat = 0
    let hotspots: () -> [Hotspot]

    var body: some View {
        ScrollView(showsIndicators: false) {
            DesignImageView(imageName: imageName, hotspots: hotspots)
                .padding(.bottom, bottomInset)
        }
    }
}

/// Картинка из макета с зонами нажатия, масштабированная по ширине экрана.
struct DesignImageView: View {
    let imageName: String
    let hotspots: () -> [Hotspot]

    var body: some View {
        if let image = UIImage(named: imageName) {
            let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
            GeometryReader { proxy in
                let scale = proxy.size.width / pixelSize.width
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: proxy.size.width, height: pixelSize.height * scale)
                    ForEach(hotspots()) { spot in
                        Button(action: spot.action) {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: spot.rect.width * scale, height: spot.rect.height * scale)
                        .offset(x: spot.rect.minX * scale, y: spot.rect.minY * scale)
                        .accessibilityLabel(spot.label)
                    }
                }
            }
            .aspectRatio(pixelSize.width / pixelSize.height, contentMode: .fit)
        } else {
            Text("Нет картинки \(imageName)").foregroundColor(.secondary).padding()
        }
    }
}
