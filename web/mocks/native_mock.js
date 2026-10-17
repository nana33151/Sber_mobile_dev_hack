export function setupNativeMocks() {
    // Проверяем, есть ли уже мосты (если запущено в реальном WebView)
    if (!window.AndroidBridge) {
        window.AndroidBridge = {
            postMessage: function(jsonString) {
                console.log("%c[Mock AndroidBridge] Получено от JS:", "color: #4CAF50; font-weight: bold;", jsonString);
            }
        };
    }

    if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.prankBridge) {
        window.webkit = window.webkit || {};
        window.webkit.messageHandlers = window.webkit.messageHandlers || {};
        window.webkit.messageHandlers.prankBridge = {
            postMessage: function(jsonString) {
                console.log("%c[Mock iOS prankBridge] Получено от JS:", "color: #2196F3; font-weight: bold;", jsonString);
            }
        };
    }
    console.log("%c[Mocks] Мок-окружение натива успешно загружено.", "color: #9E9E9E; font-style: italic;");
}