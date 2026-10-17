# Cat animation overlay

Cross-platform visual layer written in plain JavaScript and Canvas. It has no runtime dependencies and can run in a browser, Android WebView or iOS WKWebView.

The renderer owns only visuals:

- cat states with zero, one or two yarn balls;
- yarn-ball sprites at coordinates supplied by game mechanics;
- catch particles;
- a four-frame, 1.6-second final dance;
- responsive sizing for compact, portrait and landscape phone screens;
- Retina-ready optimized PNG assets totaling about 1.21 MB.

Sensors, gravity, collisions and game rules are intentionally outside this module. See `contract/animation_api.md` for the integration API.

## Local demo

Serve the repository root with any static server and open `/web/src/index.html`.

```bash
python3 -m http.server 8765
```

Then open `http://localhost:8765/web/src/index.html`.

## Tests

```bash
cd web
npm test
```
