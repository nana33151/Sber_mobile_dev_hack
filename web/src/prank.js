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

        const month = new Date().getMonth();
        const isWinter = month === 11 || month === 0 || month === 1;

        // ИСПРАВЛЕНО: пути теперь прямые, так как publicDir делает их доступными
        let atlasUrl = './atlas.json';
        if (payload?.assets?.atlas) {
            atlasUrl = payload.assets.atlas;
        } else if (isWinter) {
            atlasUrl = './atlas_winter.json';
            console.log("[PrankBridge] Включена зимняя тема!");
        }

        if (!animationApi) {
            animationApi = installCatAnimationBridge(canvas, { atlasUrl });
        }

        await animationApi.ready();
        gameEngine.start();
    },

    hide: async () => {
        gameEngine.stop();
    }
};

// --- Локальный тест для разработчика (браузер) ---
const keys = {};
window.addEventListener('keydown', (e) => keys[e.key] = true);
window.addEventListener('keyup', (e) => keys[e.key] = false);
setInterval(() => gameEngine.handleKeyboard(keys), 1000 / 60);

window.mockGame = async () => {
    await window.PrankBridge.show({ version: "1", id: "test_prank" });
};
console.log("👉 Введите mockGame() в консоль для теста.");