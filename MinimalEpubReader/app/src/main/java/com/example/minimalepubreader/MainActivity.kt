package com.example.minimalepubreader

import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.view.MotionEvent
import android.webkit.WebView
import android.widget.Button
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import nl.siegmann.epublib.epub.EpubReader
import java.io.InputStream

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private var spineIndex = 0
    private var spineItems: List<nl.siegmann.epublib.domain.SpineReference> = emptyList()

    private val filePickerLauncher = registerForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        uri?.let { openEpub(it) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        webView = findViewById(R.id.webView)
        val openButton: Button = findViewById(R.id.openButton)

        webView.settings.apply {
            javaScriptEnabled = false
            defaultFontSize = 20
        }

        openButton.setOnClickListener {
            filePickerLauncher.launch("application/epub+zip")
        }

        setupTouchNavigation()
    }

    private fun openEpub(uri: Uri) {
        try {
            val inputStream: InputStream? = contentResolver.openInputStream(uri)
            if (inputStream != null) {
                val book = EpubReader().readEpub(inputStream)
                spineItems = book.spine.spineReferences
                spineIndex = 0
                renderCurrentChapter()
                Log.d("EPUB_READER", "Loaded book with ${spineItems.size} chapters")
            }
        } catch (e: Exception) {
            Log.e("EPUB_READER", "Failed to open EPUB", e)
        }
    }

    private fun renderCurrentChapter() {
        if (spineItems.isEmpty()) return
        try {
            val resource = spineItems[spineIndex].resource
            val html = String(resource.data)
            // Escaping $html from bash by using single quotes around EOL in the script
            val styledHtml = "<html><body style='margin:5%; font-family:serif;'>$html</body></html>"
            webView.loadDataWithBaseURL(null, styledHtml, "text/html", "UTF-8", null)
        } catch (e: Exception) {
            Log.e("EPUB_READER", "Render failed", e)
        }
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
