# iOS Prank Overlay

Простое overlay-приложение: хост-экран + прозрачный WKWebView с игрой из `web/`.

## Возможности

- **Тряска** — `ShakeDetector` (CoreMotion) или Shake Gesture в симуляторе
- **Наклон** — `TiltSource` шлёт `PrankBridge.setTilt(x, y)` в web (без DeviceOrientation permission)
- **Оверлей** — `PrankOverlayController` грузит бандл по схеме `prank://`
- Кнопка «Играть» для запуска без тряски

## Подготовка

```bash
# из корня репозитория
./scripts/sync-web-to-ios.sh
```

Скрипт соберёт `web/` (Vite) и скопирует `web/dist` → `ios/PrankApp/Resources/Web`.

## Запуск

1. Откройте `ios/PrankApp/PrankApp.xcodeproj` в Xcode
2. Выберите Team для подписи
3. Run на устройстве (наклон/тряска) или симуляторе (кнопка / Device → Shake)

## Структура

```
ios/PrankApp/
  PrankApp/
    App/           AppDelegate, SceneDelegate, Info.plist
    Screens/       HostViewController
    Sensors/       ShakeDetector, TiltSource
    Bridge/        PrankWebBridge (WKScriptMessageHandler)
    Overlay/       PrankOverlayController, PrankSchemeHandler
  Resources/Web/   собранный web (после sync)
```

CocoaPods не нужен — только UIKit + WebKit + CoreMotion.
