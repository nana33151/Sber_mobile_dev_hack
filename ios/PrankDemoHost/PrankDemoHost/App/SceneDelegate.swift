import PrankLinker
import SwiftUI
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var demo: DemoController?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let demo = DemoController()
        self.demo = demo

        let window = DemoHostWindow(windowScene: windowScene)
        window.linker = demo.linker
        window.tilt = demo.manualTilt
        window.rootViewController = UIHostingController(rootView: DemoRoot().environmentObject(demo))
        window.makeKeyAndVisible()
        self.window = window

        demo.linker.attach(to: windowScene)
        demo.presenterProvider = { [weak window] in window?.rootViewController?.topMostPresented }
        Task { await demo.linker.reloadConfig() }
    }
}

private extension UIViewController {
    var topMostPresented: UIViewController {
        presentedViewController?.topMostPresented ?? self
    }
}
