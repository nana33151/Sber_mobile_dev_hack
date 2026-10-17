package com.example.prank

import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect

class PrankActivity : AppCompatActivity() {

    private lateinit var webView: PrankWebView
    private lateinit var engine: PrankEngine
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        webView = PrankWebView(this).apply {
            alpha = 1f
            onEnginePageFinished = {
                Log.d("PrankActivity", "engine page finished")
                engine.init("""{"version":"1","enabled":true}""")
                engine.show(PRANK_001_PAYLOAD)
            }
        }
        setContentView(webView)

        engine = PrankEngine(webView, scope)

        scope.launch {
            engine.events.collect { event ->
                Log.d("PrankActivity", "Event: $event")
                when (event) {
                    is PrankEvent.Shown  -> webView.alpha = 1f
                    is PrankEvent.Hidden -> { webView.alpha = 0f; finish() }
                    is PrankEvent.Error  -> { webView.alpha = 0f; finish() }
                    is PrankEvent.Action -> { /* лог только */ }
                }
            }
        }

        webView.loadEngine()
    }

    override fun onDestroy() {
        scope.cancel()
        webView.destroy()
        super.onDestroy()
    }

    companion object {
        // Движок использует только id и assets.atlas. Остальные поля — no-op,
        // оставим только то, что имеет смысл, чтобы не путать.
        private const val PRANK_001_PAYLOAD = """
            {
              "version": "1",
              "id": "prank_001",
              "assets": {}
            }
        """
    }
}
