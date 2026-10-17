# PrankEngine Bridge v1

Мост между нативным приложением и web-слоем пранков.
Пранк = HTML-оверлей, который нативная оболочка рендерит поверх экрана
(внутри приложения или системно — решает нативная сторона, контракт это не фиксирует).

## API

window.PrankBridge = {
  init(config)          -> Promise<void>
  show(payload)         -> Promise<void>
  hide(id?)             -> Promise<void>
  on(event, cb)         -> void
  getVersion()          -> string   // всегда "1"
}

## Семантика

init(config)   — принимает PrankConfig, включает/выключает пранки.
                 Резолвится, когда бридж готов принимать show().

show(payload)  — показать оверлей. Резолвится, когда оверлей реально
                 отрисован (первый кадр). Реджектится при ошибке.
                 Жёсткий таймаут: 2000 мс → reject с кодом TIMEOUT.

hide(id?)      — скрыть оверлей по id. Без аргумента — скрыть текущий.

on(event, cb)  — подписка на события. Возвращает void, отписки нет
                 (на хакатоне не нужно).

getVersion()   — "1". Используется для проверки совместимости.

## События

- shown   { payload_id }
- hidden  { payload_id, reason: "timeout" | "dismiss" | "manual" }
- action  { payload_id, action }       // action из data-prank-action="..." в HTML
- error   { code, message }

## Ошибки

show() реджектится объектом { code, message }, коды:
- INVALID_PAYLOAD  — не прошёл payload_schema
- NOT_SUPPORTED    — нативная сторона не умеет такой тип оверлея
- TIMEOUT          — > 2000 мс
- INTERNAL         — всё остальное

## Правила

- Имена методов и события заморожены. Изменения — только PR в main с бампом версии.
- Payload валидируется по contract/payload_schema.json на всех трёх платформах.
- base64 в assets — standard alphabet, с padding, без префикса "data:".
- Web-сторона не знает, где именно показывается оверлей. Только "покажи вот это".
