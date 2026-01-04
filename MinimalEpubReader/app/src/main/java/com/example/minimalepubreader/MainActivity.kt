package com.example.minimalepubreader

import android.os.Bundle
import android.util.Log
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

        try {
            loadEpub()
            renderCurrentChapter()
            setupTouchNavigation()
            Log.d("EPUB_READER", "App initialized successfully")
        } catch (e: Exception) {
            Log.e("EPUB_READER", "Initialization failed", e)
        }
    }

    private fun configureWebView() {
        webView.settings.apply {
            javaScriptEnabled = false
            defaultFontSize = 20
        }
    }

    private fun loadEpub() {
        val inputStream: InputStream = assets.open("book.epub")
        val book = EpubReader().readEpub(inputStream)
        spineItems = book.spine.spineReferences
        Log.d("EPUB_READER", "Loaded book with ${spineItems.size} chapters")
    }

    private fun renderCurrentChapter() {
        if (spineItems.isEmpty()) return
        val resource = spineItems[spineIndex].resource
        val html = String(resource.data)
        val styledHtml = "<html><body style='margin:5%; font-family:serif;'>$html</body></html>"
        webView.loadDataWithBaseURL(null, styledHtml, "text/html", "UTF-8", null)
        Log.d("EPUB_READER", "Rendering chapter index: $spineIndex")
    }

    private fun setupTouchNavigation() {
        webView.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_UP) {
                val width = webView.width
                if (event.x > width * 0.66 && spineIndex < spineItems.size - 1) {
                    spineIndex++; renderCurrentChapter()
                } else if (event.x < width * 0.33 && spineIndex > 0) {
                    spineIndex--; renderCurrentChapter()
                }
            }
            true
        }
    }
}
