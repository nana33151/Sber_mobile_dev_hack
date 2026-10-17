import { installCatAnimationBridge } from "./bridge.js";

const canvas = document.querySelector("#cat-animation-overlay");
const api = installCatAnimationBridge(canvas);

async function loadDemo() {
  const { startNativeMock } = await import("../mocks/native_mock.js");
  await api.ready();
  const demo = startNativeMock(api);
  document.querySelector("#replay-demo")?.addEventListener("click", () => demo.restart());
}

loadDemo().catch((error) => console.error("Unable to start animation demo", error));
