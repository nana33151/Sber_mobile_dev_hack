package com.example.prank

import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class PrankActivity : AppCompatActivity() {

    private lateinit var webView: PrankWebView
    private lateinit var engine: PrankEngine
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 1. WebView видим сразу (было alpha = 0f)
        webView = PrankWebView(this).apply { alpha = 1f }
        setContentView(webView)

        engine = PrankEngine(webView, scope)

        webView.webViewClient = object : android.webkit.WebViewClient() {
            override fun onPageFinished(view: android.webkit.WebView?, url: String?) {
                // 2. Toast: сработал ли onPageFinished вообще
                toast("onPageFinished: $url")
                Log.d("PrankActivity", "onPageFinished: $url")

                val config = """{"version":"1","enabled":true}"""
                engine.init(config)

                val payload = """
                    {
                      "version": "1",
                      "id": "prank_001",
                      "title": "Test prank",
                      "html": "<div style='font-size:64px;color:red;text-align:center;margin-top:30%'>BOO!</div>",
                      "css": "body{background:transparent;margin:0;overflow:hidden;}",
                      "js": "",
                      "assets": {},
                      "duration_ms": 4000,
                      "dismissible": true,
                      "background": "transparent"
                    }
                """.trimIndent()
                engine.show(payload)
            }

            override fun onReceivedError(
                view: android.webkit.WebView?,
                request: android.webkit.WebResourceRequest?,
                error: android.webkit.WebResourceError?
            ) {
                // 3. Toast: если загрузка упала — покажет какой URL и почему
                toast("Error: ${request?.url} — ${error?.description}")
                Log.e("PrankActivity", "onReceivedError: ${request?.url}", null)
            }
        }

        webView.loadEngine()

        scope.launch {
            engine.events.collect { event ->
                toast("Event: $event")
                Log.d("PrankActivity", "Event: $event")
                when (event) {
                    is PrankEvent.Shown -> { webView.alpha = 1f }
                    is PrankEvent.Hidden -> { webView.alpha = 0f }
                    is PrankEvent.Error -> { webView.alpha = 0f }
                    is PrankEvent.Action -> { /* для smoke test не нужен */ }
                }
            }
        }
    }

    private fun toast(msg: String) =
        Toast.makeText(this, msg, Toast.LENGTH_LONG).show()

    override fun onDestroy() {
        scope.cancel()
        webView.destroy()
        super.onDestroy()
    }
}
