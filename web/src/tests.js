export function runTests() {
    console.log("%c=== ЗАПУСК ТЕСТОВ PRANK BRIDGE v1 (Strict Schemas) ===", "font-weight: bold; font-size: 16px; color: #ff9800;");

    let passed = 0;
    let failed = 0;

    function assert(condition, message) {
        if (condition) {
            console.log(`%c[PASS] ${message}`, "color: #4CAF50; font-weight: bold;");
            passed++;
        } else {
            console.error(`[FAIL] ${message}`);
            failed++;
        }
    }

    const validPayload = {
        version: "1",
        id: "test_prank_01",
        html: `<h1>Тест</h1>`,
        duration_ms: 500,
        background: "dim"
    };

    async function runAsyncTests() {
        try {
            // 1. Проверка Schema: Неверный id (заглавные буквы)
            try {
                await window.PrankBridge.show({ ...validPayload, id: "Test_PrAnk" });
                assert(false, "Должна была быть ошибка INVALID_PAYLOAD для заглавных букв в ID");
            } catch (e) {
                assert(e.code === "INVALID_PAYLOAD", "Отклонен невалидный ID (INVALID_PAYLOAD)");
            }

            // 2. Проверка Schema: Слишком маленький duration_ms (<500)
            try {
                await window.PrankBridge.show({ ...validPayload, duration_ms: 100 });
                assert(false, "Должна была быть ошибка для duration_ms < 500");
            } catch (e) {
                assert(e.code === "INVALID_PAYLOAD", "Отклонен duration_ms < 500");
            }

            // 3. Проверка нативного config: Отключение пранков
            await window.PrankBridge.init({ version: "1", enabled: false });
            try {
                await window.PrankBridge.show(validPayload);
                assert(false, "Должна была быть ошибка NOT_SUPPORTED (пранки выключены)");
            } catch (e) {
                assert(e.code === "NOT_SUPPORTED", "Блокировка show() при enabled: false");
            }

            // 4. Успешный сценарий
            await window.PrankBridge.init({ version: "1", enabled: true });
            let shownFired = false;
            window.PrankBridge.on('shown', () => shownFired = true);

            await window.PrankBridge.show(validPayload);
            assert(shownFired, "Событие 'shown' сработало");

            const container = document.getElementById('prank-container');
            assert(container.innerHTML.includes("Тест"), "HTML отрисован");

            // 5. Проверка сворачивания по таймауту
            let hiddenReason = "";
            window.PrankBridge.on('hidden', (data) => hiddenReason = data.reason);

            // Ждем 600мс (duration_ms = 500), чтобы сработал таймаут скрытия
            await new Promise(r => setTimeout(r, 700));
            assert(hiddenReason === "timeout", "Событие 'hidden' сработало с reason: 'timeout'");

        } catch (e) {
            console.error("Ошибка в асинхронных тестах:", e);
            failed++;
        }

        setTimeout(() => {
            console.log(`%c=== РЕЗУЛЬТАТЫ: Успешно: ${passed}, Провалено: ${failed} ===`, `font-weight: bold; color: ${failed > 0 ? '#f44336' : '#4CAF50'};`);
        }, 500);
    }

    runAsyncTests();
}