import { installCatAnimationBridge } from "./bridge.js";
import { GameEngine } from "./game-engine.js";

const canvas = document.querySelector("#cat-animation-overlay");
let animationApi = null;
let gameEngine = new GameEngine();

window.PrankBridge = {
    getVersion: () => "1",
    on: () => {},
    emit: (event, data) => {
        const message = JSON.stringify({ event, data });
        if (window.AndroidBridge?.postMessage) window.AndroidBridge.postMessage(message);
        else if (window.webkit?.messageHandlers?.prankBridge?.postMessage) window.webkit.messageHandlers.prankBridge.postMessage(message);
        else console.log(`[Mock Native] ${event}:`, data);
    },

    init: async (config) => {
        console.log("[PrankBridge] Init:", config);
    },

    show: async (payload) => {
        console.log("[PrankBridge] Вызов show()", payload);

        let atlasUrl = './atlas.json';
        if (payload?.assets?.atlas) {
            atlasUrl = payload.assets.atlas;
        }

        if (!animationApi) {
            animationApi = installCatAnimationBridge(canvas, { atlasUrl });
        }

        await animationApi.ready();
        // На iOS натив заранее шлёт setNativeTilt — тогда DeviceOrientation не трогаем.
        if (payload?.native_tilt === true) {
            gameEngine.useNativeTilt = true;
        }
        await gameEngine.start();
        window.PrankBridge.emit('shown', { payload_id: payload?.id ?? 'cats_yarn' });
    },

    hide: async (id) => {
        gameEngine.stop();
        window.PrankBridge.emit('hidden', { payload_id: id ?? 'cats_yarn', reason: 'manual' });
    },

    /** Вызывается из WKWebView: evaluateJavaScript("PrankBridge.setTilt(x,y)") */
    setTilt: (x, y) => {
        gameEngine.setNativeTilt(x, y);
    }
};

window.__prankSetTilt = (x, y) => gameEngine.setNativeTilt(x, y);

// --- Локальный тест для разработчика (браузер) ---
const keys = {};
window.addEventListener('keydown', (e) => keys[e.key] = true);
window.addEventListener('keyup', (e) => keys[e.key] = false);
setInterval(() => gameEngine.handleKeyboard(keys), 1000 / 60);

window.mockGame = async () => {
    await window.PrankBridge.show({ version: "1", id: "test_prank" });
};
console.log("👉 Введите mockGame() в консоль для теста.");