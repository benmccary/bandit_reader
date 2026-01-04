package com.example.minimalepubreader

import android.os.Bundle
import android.view.MotionEvent
import android.webkit.WebSettings
import android.webkit.WebView
import androidx.appcompat.app.AppCompatActivity
import nl.siegmann.epublib.epub.EpubReader
import java.io.InputStream

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private var spineIndex = 0
    private lateinit var spineItems: List<nl.siegmann.epublib.domain.SpineReference>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        webView = findViewById(R.id.webView)
        configureWebView()

        loadEpub()
        renderCurrentChapter()
        setupTouchNavigation()
    }

    private fun configureWebView() {
        val settings = webView.settings
        settings.javaScriptEnabled = false
        settings.cacheMode = WebSettings.LOAD_NO_CACHE
        settings.defaultFontSize = 20
    }

    private fun loadEpub() {
        val inputStream: InputStream = assets.open("book.epub")
        val book = EpubReader().readEpub(inputStream)
        spineItems = book.spine.spineReferences
    }

    private fun renderCurrentChapter() {
        val resource = spineItems[spineIndex].resource
        val html = String(resource.data)
        val styledHtml = """
            <html>
            <head><style>
                body { font-family: serif; margin: 5%; line-height: 1.6; background-color: #fff; color: #000; }
            </style></head>
            <body></body>
            </html>
        """.trimIndent()
        webView.loadDataWithBaseURL(null, styledHtml, "text/html", "UTF-8", null)
    }

    private fun setupTouchNavigation() {
        webView.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_UP) {
                val x = event.x
                val width = webView.width
                if (x > width * 0.66 && spineIndex < spineItems.size - 1) {
                    spineIndex++; renderCurrentChapter()
                } else if (x < width * 0.33 && spineIndex > 0) {
                    spineIndex--; renderCurrentChapter()
                }
            }
            true
        }
    }
}
