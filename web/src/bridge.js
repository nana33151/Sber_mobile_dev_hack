import { CatAnimationRenderer } from "./cat-animation.js";

let rendererPromise;

export function installCatAnimationBridge(canvas, options = {}) {
  const renderer = new CatAnimationRenderer(canvas, options);
  rendererPromise = renderer.init();

  async function handle(command = {}) {
    const instance = await rendererPromise;

    switch (command.type) {
      case "SCENE_UPDATE":
        instance.setScene(command.scene ?? command.payload ?? {});
        break;
      case "CATCH_EFFECT":
        instance.playCatch(command.payload ?? command);
        break;
      case "FINAL_DANCE":
        instance.playDance(command.payload ?? command);
        break;
      case "HIDE":
        instance.hide();
        break;
      default:
        throw new Error(`Unknown CatAnimation command: ${String(command.type)}`);
    }
  }

  const api = Object.freeze({
    ready: () => rendererPromise,
    setScene: async (scene) => (await rendererPromise).setScene(scene),
    playCatch: async (payload) => (await rendererPromise).playCatch(payload),
    playDance: async (payload) => (await rendererPromise).playDance(payload),
    hide: async () => (await rendererPromise).hide(),
    handle
  });

  window.CatAnimation = api;

  window.addEventListener("message", (event) => {
    const command = event.data;
    if (command?.channel !== "CAT_ANIMATION") return;
    handle(command).catch((error) => console.error("CatAnimation bridge error", error));
  });

  return api;
}