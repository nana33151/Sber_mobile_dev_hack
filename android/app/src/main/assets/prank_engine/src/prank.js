import { installCatAnimationBridge } from "./bridge.js";
import { GameEngine } from "./game-engine.js";

const canvas = document.querySelector("#cat-animation-overlay");
const gameEngine = new GameEngine();

let animationApi = null;

const ATLAS_DEFAULT = "./assets/atlas.json";
const ATLAS_WINTER = "./assets/atlas_winter.json";

window.PrankBridge = {
  getVersion: () => "1",
  on: () => {},

  emit: (event, data) => {
    const message = JSON.stringify({ event, data });
    if (window.AndroidBridge?.postMessage) {
      window.AndroidBridge.postMessage(message);
    } else if (window.webkit?.messageHandlers?.prankBridge?.postMessage) {
      window.webkit.messageHandlers.prankBridge.postMessage(message);
    } else {
      console.log(`[Mock Native] ${event}:`, data);
    }
  },

  init: async (config) => {
    console.log("[PrankBridge] init:", config);
  },

  show: async (payload) => {
    console.log("[PrankBridge] show()", payload);
    try {
      const atlasUrl = resolveAtlasUrl(payload);
      if (!animationApi) {
        animationApi = installCatAnimationBridge(canvas, { atlasUrl });
      }
      await animationApi.ready();
      console.log("[PrankBridge] renderer ready");

      const mode = payload?.mode ?? "game";

      if (mode === "final_dance") {
        // Режим страницы «Оплата»: без игры, сразу финальный танец.
        startFinalDance(payload);
      } else if (!gameEngine.isPlaying) {
        // Обычная игра: котики ловят клубки.
        gameEngine.start();
        console.log("[PrankBridge] game started");
      }

      window.PrankBridge.emit("shown", {
        payload_id: payload?.id ?? "prank_001",
      });
    } catch (e) {
      console.error("[PrankBridge] show() failed:", e);
      window.PrankBridge.emit("error", {
        code: "INIT_FAILED",
        message: String(e?.message || e),
      });
    }
  },

  hide: async (reason) => {
    console.log("[PrankBridge] hide()", reason);
    try {
      gameEngine.stop();
    } catch (e) {
      console.error("[PrankBridge] stop failed:", e);
    }
    try {
      animationApi?.hide();
    } catch (e) {
      console.error("[PrankBridge] hide failed:", e);
    }
    window.PrankBridge.emit("hidden", { reason: reason || "manual" });
  },

  switchMode: (mode) => {
    console.log("[PrankBridge] switchMode ignored:", mode);
  },
};

/**
 * Финальная анимация без геймплея: один котик в центре экрана
 * отплясывает победный танец, после чего отправляем game_won
 * (PrankEngine среагирует на него и закроет оверлей).
 */
function startFinalDance(payload) {
  console.log("[PrankBridge] final_dance: показываем финальный танец");

  // Сцена с одним котиком в центре — рендерер рисует dance-кадры
  // поверх cat'ов из сцены, поэтому пустую сцену использовать нельзя.
  animationApi.setScene({
    visible: true,
    cats: [{ id: "solo-cat", x: 0.5, y: 0.5, balls: 2, scale: 1.2 }],
    yarns: [],
  });

  const durationMs = Math.max(1000, Number(payload?.duration_ms) || 2200);

  const onComplete = () => {
    window.removeEventListener("cat-animation:dance-complete", onComplete);
    console.log("[PrankBridge] final_dance complete → game_won");
    window.PrankBridge.emit("action", { action: "game_won" });
  };
  window.addEventListener("cat-animation:dance-complete", onComplete);

  animationApi.playDance({ durationMs });
}

function resolveAtlasUrl(payload) {
  if (payload?.assets?.atlas) return payload.assets.atlas;
  const month = new Date().getMonth();
  const isWinter = month === 11 || month === 0 || month === 1;
  const file = isWinter ? "atlas_winter.json" : "atlas.json";
  return new URL(`../assets/${file}`, import.meta.url).toString();
}

// ─── локальный тест в браузере ───
const keys = {};
window.addEventListener("keydown", (e) => (keys[e.key] = true));
window.addEventListener("keyup", (e) => (keys[e.key] = false));
setInterval(() => gameEngine.handleKeyboard(keys), 1000 / 60);

window.mockGame = async () => {
  await window.PrankBridge.show({ version: "1", id: "test_prank" });
};
window.mockFinalDance = async () => {
  await window.PrankBridge.show({
    version: "1",
    id: "test_final_dance",
    mode: "final_dance",
    duration_ms: 2200,
  });
};
console.log("👉 mockGame() / mockFinalDance() для теста в браузере");
