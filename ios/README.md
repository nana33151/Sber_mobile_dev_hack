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
    ├── Pranks/         config.json, payload.json игры cats_yarn и payload'ы для тестов сбоев
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

## Игра в линкере

Игра — `web/` из main, без сборки и без копий: демо кладёт папку `web/` в приложение целиком,
линкер открывает `web/src/index.html` (`PrankContent.entry`), а статику ищет в `web/assets`
(`PrankContent.publicDirectory`, как `publicDir` у Vite: `src/atlas.json` → `assets/atlas.json`).
Схема `prank://` отдаёт файлы с CORS, поэтому работают `<script type="module">`, `import()` и `fetch()`.

Что линкер делает за игру:

| Игре нужно | Линкер |
|---|---|
| `deviceorientation` (gamma/beta) | Шлёт синтетические события из CoreMotion (или джойстика в симуляторе). Разрешение на датчики не нужно |
| `webkit.messageHandlers.prankBridge.postMessage(json)` | Принимает `{ event, data }`, как и `postMessage` страницы |
| `action: cat_caught` | Лёгкая вибрация (`Options.hapticActions`) |
| `action: game_won` | `.completed` приложению, прикол плавно закрывается (`Options.completionActions`) |
| Прозрачный оверлей | Фон страницы и всё, кроме `<canvas>` (заглушка «экран SberKids» для браузера), скрыты |
| Холодный WebKit | Прогревается через 1,5 с после `attach`, чтобы первый показ уложился в 2 с |
| Фон не мешает игре | `linker.blursBackground = true` — приложение под игрой размывается, можно переключать во время игры (в демо — кнопка «Размыть фон» и тумблер в отладке) |
| Игра запустилась | Вибрация «успех» на первом кадре (`Options.hapticOnLaunch`) |

`window.PrankBridge` из модуля линкер ждёт до 1,5 с, иначе — `NO_BRIDGE` в лог. Ошибки ресурсов
(`RESOURCE`) и `console.error` (`CONSOLE`) приходят приложению как `pageError`.

Правки в игре: в `game-engine.js` котики больше не появляются друг на друге, клубки не появляются
друг на друге и при движении расталкиваются (коллизии считаются в долях короткой стороны экрана).
`cat-animation.js` отправлял `cat-animation:dance-complete` без `bubbles`, а
`game-engine.js` слушает его на `window` — `game_won` не приходил. Добавлен `{ bubbles: true }`.

### Общий контракт страницы

Приложение → страница: `window.PrankBridge.init(config)`, `show(payload)` (резолвить после первого
кадра), `hide(id)`; наклон — `deviceorientation` и `prank:tilt` (`{ x, y }` в долях g).

Страница → приложение:

```js
window.webkit.messageHandlers.prankBridge.postMessage(JSON.stringify({ event: "action", data: { action: "cat_caught" } }));
window.postMessage({ event: "error", code: "INTERNAL", message: "..." }, "*");
window.postMessage({ type: "VIBRATION_EVENT" }, "*");   // лёгкий тактильный отклик
window.postMessage({ type: "COMPLETED_EVENT" }, "*");   // один раз за показ
window.postMessage({ type: "CLOSE_EVENT" }, "*");       // закрыть прикол
```

## Открытые вопросы

- Зимой (дек–фев) игра грузит `atlas_winter.json`, которого в `web/assets` нет → игра не запустится,
  сыграет нативный котик-заглушка. Нужен зимний атлас.
- В `atlas.json` к краям некоторых клубков попадают пиксели соседних кадров (тонкие полоски).
- `lottie-web` в `web/package.json` — внешняя библиотека; в коде не используется, лучше убрать.
- Триггер `tap` конфликтует с «касание закрывает»: сейчас это касание элемента-якоря (`linker.handleTap()`).
