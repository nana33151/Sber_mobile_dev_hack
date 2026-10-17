# iOS: линкер СберKids ↔ JS-прикол

Нативная обвязка, которая показывает JS-прикол поверх интерфейса СберKids. Только Swift и
системные фреймворки (UIKit, WebKit, CoreMotion), iOS 15+, Swift 6. Внешних зависимостей нет.

```
ios/
├── PrankLinker/        Swift Package — то, что встраивается в СберKids
│   ├── Contract/       PrankConfig и PrankPayload по схемам из contract/, ручная валидация
│   ├── Bridge/         JS-скрипт моста и разбор сообщений страницы
│   ├── Overlay/        окно поверх приложения и один показ (WKWebView, таймауты, сторож)
│   ├── Content/        откуда брать конфиг и приколы, схема prank:// для файлов
│   ├── Triggers/       тряска, наклон
│   └── Safety/         предохранитель от повторных сбоев, пауза между показами
└── PrankDemoHost/      демо-приложение для защиты: условный главный экран + панель отладки
    ├── Pranks/         config.json, мок игры cats_yarn/ и payload'ы для тестов сбоев
    └── PrankDemoHostTests/  интеграционные тесты с настоящим WKWebView
```

## Запуск демо

Откройте `ios/PrankDemoHost/PrankDemoHost.xcodeproj`, схема `PrankDemoHost`, любой iPhone-симулятор.

Демо собирает исходники `PrankLinker/Sources/PrankLinker` как статический фреймворк внутри своего
проекта — так проект стабильно открывается и собирается в Xcode без резолва Swift-пакета.
В СберKids линкер подключается как Swift Package (`ios/PrankLinker`).

- **Тряска:** в симуляторе Device → Shake (⌃⌘Z), на телефоне — потрясти.
- **Наклон в симуляторе:** джойстик справа внизу (виден только в симуляторе; касания по нему прикол
  не закрывают) или стрелки/WASD на клавиатуре Mac (I/O → Keyboard → Connect Hardware Keyboard).
- **Демо-режим для жюри:** в схеме поменяйте аргумент `-prankDemo NO` на `-prankDemo YES`. Прикол перестаёт закрываться
  касанием, и в углу появляется джойстик наклона. То же самое переключается тумблером в панели отладки.
- **Панель отладки** (жучок справа сверху): запуск любого прикола, тесты сбоев, лог событий.
- **Экраны из макета Figma** (по умолчанию): главный, «Копилки», «Дела» — картинками из
  `PrankDemoHost/PrankDemoHost/Design/` с зонами нажатия. Лапка в нижнем меню запускает прикол
  без тряски. «Скинуть денег» и «Перевести» открывают «Лимиты» — там приколы запрещены.
  Тумблер в панели отладки переключает на самодельный экран.
- **Сбой загрузки игры:** аргумент схемы `-prankFailLoad YES` (включён по умолчанию) или тумблер
  «Сломать загрузку игры» в панели отладки. Тряска → игра не грузится → танцует котик из `web/assets`.
  Чтобы запускалась сама игра, снимите галочку с `-prankFailLoad YES` в Edit Scheme → Arguments.
- **Экраны «Оплатить» и «Перевести»** запрещают приколы — тряска там попадёт в лог как пропуск.

Тесты:

```bash
cd ios/PrankLinker && xcodebuild -scheme PrankLinker -destination 'platform=iOS Simulator,name=iPhone 17' test
cd ios/PrankDemoHost && xcodebuild -scheme PrankDemoHost -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Встраивание в СберKids

```swift
let linker = PrankLinker(content: FallbackContentProvider(
    primary: CMSPrankProvider(),                         // ключ CMS + CDN, пишет приложение
    fallback: DirectoryContentProvider(root: bundledPranks) // ресурсы внутри сборки
))
linker.delegate = self
linker.attach(to: windowScene)
Task { await linker.reloadConfig() }

// В UIWindow приложения — единственная правка в окне:
override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
    linker.handleShakeMotion(motion)
    super.motionEnded(motion, with: event)
}

// При каждом переходе: оплата, переводы, реквизиты, лимиты — false.
linker.screenAllowsPranks = false
```

Все события приходят в `PrankLinkerDelegate.prankLinker(_:didEmit:)`: показ, закрытие с причиной,
`action`, сбои, `COMPLETED`/`FINISH`/`SHARING` из канала хакатона.

## Что гарантирует линкер

| Ситуация | Что происходит |
|---|---|
| Касание экрана | Прикол закрывается (`hidden: dismiss`), касание уходит в интерфейс под ним |
| Пустой или битый конфиг | `configRejected`, приколы выключены, запасной источник из сборки |
| Payload не прошёл схему | `failed: INVALID_PAYLOAD`, ничего не показывается |
| `show()` не резолвится за 2000 мс | `failed: TIMEOUT`, окно убрано |
| Исключение в `init()`/`show()` | `failed: INTERNAL` |
| Ошибка JS после показа | `pageError`, прикол продолжает работать |
| JS завис (бесконечный цикл) | Сторож: нет ответа 3 с → `failed`, окно убрано |
| Процесс WebView упал | `failed`, окно убрано; приложение не затронуто — это другой процесс |
| Игра не запустилась (ошибка загрузки, таймаут, сбой до первого кадра) | `failed` + нативная анимация `Options.launchFailureAnimation`: танцующий котик чуть ниже центра, ~3 с, касание убирает |
| 3 сбоя подряд | Приколы выключены до перезапуска приложения |
| Переходы наружу, `window.open`, `alert` | Блокируются |
| Уход в фон, нехватка памяти, запрещённый экран | Прикол закрывается |

## Контракт для JS-разработчика

Страница грузится по `prank://payload/index.html`, ссылки на свои файлы — относительные.
Прикол-папка: `index.html` + `payload.json` (поля `payload_schema.json` без `html`), см. `Pranks/cats_yarn/`.

Приложение → страница (линкер вызывает после загрузки):

```js
window.PrankBridge = {
  init(config) { /* PrankConfig */ return Promise.resolve(); },
  show(payload) { /* метаданные payload; резолвить после первого кадра */ },
  hide(id) { /* остановить анимации */ },
  on(event, cb) {},
  getVersion() { return "1"; }
};
```

Если `PrankBridge` не объявлен, линкер считает страницу показанной после первого кадра.

Наклон (страница сама датчики не читает — в WKWebView для этого нужен жест, а касание закрывает прикол):

```js
window.addEventListener('prank:tilt', e => { e.detail.x; e.detail.y }); // −1…1, x вправо, y вниз
// или читать window.PrankTilt.x / .y в игровом цикле
```

Страница → приложение:

```js
window.postMessage({ event: "action", payload_id: "cats_yarn", action: "pet" }, "*");
window.postMessage({ event: "error", code: "INTERNAL", message: "..." }, "*");
window.postMessage({ type: "VIBRATION_EVENT" }, "*");   // лёгкий тактильный отклик
window.postMessage({ type: "COMPLETED_EVENT" }, "*");   // один раз за показ
window.postMessage({ type: "FINISH_EVENT" }, "*");
window.postMessage({ type: "CLOSE_EVENT" }, "*");       // закрыть прикол
```

## Открытые вопросы по контракту

- `prank:tilt` и вызовы `PrankBridge` из натива в `PrankEngine_Bridge_v1.md` не описаны — нужен PR в main.
- Атласы в `source/` (~3,6 МБ PNG) — для бюджета 6 МБ стоит ужать до размеров на экране.
- `duration_ms` максимум 60 000 — хватит ли на раунд игры.
- `background` по умолчанию `opaque`, для оверлея нужен `transparent` (в моке так и стоит).
- Триггер `tap` конфликтует с «касание закрывает»: сейчас это касание элемента-якоря (`linker.handleTap()`).
