# Cat animation API

The renderer is presentation-only. Device sensors, physics, collision detection and game rules remain in the host application.

All coordinates are normalized: `x = 0...1`, `y = 0...1`. The overlay canvas has `pointer-events: none` and never intercepts application input.

## Direct JavaScript API

```js
await window.CatAnimation.ready();

window.CatAnimation.setScene({
  visible: true,
  cats: [
    { id: "cat-1", x: 0.2, y: 0.78, balls: 0 },
    { id: "cat-2", x: 0.5, y: 0.78, balls: 1 },
    { id: "cat-3", x: 0.8, y: 0.78, balls: 2 }
  ],
  yarns: [
    { id: "yarn-1", x: 0.4, y: 0.25, variant: 3, rotation: 0.4 }
  ]
});

window.CatAnimation.playCatch({
  catId: "cat-2",
  x: 0.5,
  y: 0.7
});

window.CatAnimation.playDance({ durationMs: 1600 });
window.CatAnimation.hide();
```

`setScene` may be called on every physics frame. The renderer limits the scene to four cats, eight yarn balls and two collected balls per cat.

## Message bridge

Android WebView and iOS WKWebView can call `window.CatAnimation.handle(command)` or dispatch a page message with `channel: "CAT_ANIMATION"`.

```js
window.postMessage({
  channel: "CAT_ANIMATION",
  type: "SCENE_UPDATE",
  scene: {
    visible: true,
    cats: [],
    yarns: []
  }
}, "*");
```

Supported commands:

- `SCENE_UPDATE`
- `CATCH_EFFECT`
- `FINAL_DANCE`
- `HIDE`

The canvas emits `cat-animation:ready` and `cat-animation:dance-complete` DOM events.
