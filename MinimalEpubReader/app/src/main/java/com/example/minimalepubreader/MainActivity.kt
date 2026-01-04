package com.example.minimalepubreader

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.view.MotionEvent
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import nl.siegmann.epublib.epub.EpubReader
import java.io.InputStream

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private var spineIndex = 0
    private var spineItems: List<nl.siegmann.epublib.domain.SpineReference> = emptyList()
    private var currentUri: Uri? = null
    private var pendingScrollY = 0

    // Switch to OpenDocument for persistent access
    private val filePickerLauncher = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        uri?.let { 
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            try {
                contentResolver.takePersistableUriPermission(it, flags)
            } catch (e: Exception) {
                Log.e("EPUB_READER", "Failed to take persistable permission", e)
            }
            
            val prefs = getSharedPreferences("ReaderPrefs", Context.MODE_PRIVATE)
            val savedIdx = prefs.getInt("${it}_index", 0)
            val savedScroll = prefs.getInt("${it}_scroll", 0)
            openEpub(it, savedIdx, savedScroll) 
        }
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

        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                if (pendingScrollY > 0) {
                    view?.postDelayed({
                        view.scrollTo(0, pendingScrollY)
                        pendingScrollY = 0
                    }, 200)
                }
            }
        }

        val prefs = getSharedPreferences("ReaderPrefs", Context.MODE_PRIVATE)
        val lastUriStr = prefs.getString("global_last_uri", null)
        if (lastUriStr != null) {
            val uri = Uri.parse(lastUriStr)
            val lastIdx = prefs.getInt("${uri}_index", 0)
            val lastScroll = prefs.getInt("${uri}_scroll", 0)
            openEpub(uri, lastIdx, lastScroll)
        }

        openButton.setOnClickListener {
            // "application/epub+zip" is the standard mime for EPUB
            filePickerLauncher.launch(arrayOf("application/epub+zip", "application/octet-stream"))
        }

        setupTouchNavigation()
    }

    private fun openEpub(uri: Uri, savedIndex: Int, savedScroll: Int) {
        try {
            val inputStream: InputStream? = contentResolver.openInputStream(uri)
            if (inputStream != null) {
                val book = EpubReader().readEpub(inputStream)
                spineItems = book.spine.spineReferences
                spineIndex = if (savedIndex < spineItems.size) savedIndex else 0
                pendingScrollY = savedScroll
                currentUri = uri
                renderCurrentChapter()
            }
        } catch (e: Exception) {
            Log.e("EPUB_READER", "Failed to load book", e)
        }
    }

    private fun saveProgress() {
        val uri = currentUri ?: return
        val prefs = getSharedPreferences("ReaderPrefs", Context.MODE_PRIVATE)
        prefs.edit().apply {
            putString("global_last_uri", uri.toString())
            putInt("${uri}_index", spineIndex)
            putInt("${uri}_scroll", webView.scrollY)
            apply()
        }
    }

    private fun renderCurrentChapter() {
        if (spineItems.isEmpty()) return
        try {
            val resource = spineItems[spineIndex].resource
            val html = String(resource.data)
            val styledHtml = "<html><body style='margin:5%; font-family:serif;'>$html</body></html>"
            webView.loadDataWithBaseURL(null, styledHtml, "text/html", "UTF-8", null)
        } catch (e: Exception) {
            Log.e("EPUB_READER", "Render error", e)
        }
    }

    private fun setupTouchNavigation() {
        webView.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_UP) {
                val width = webView.width
                val height = webView.height
                val scrollY = webView.scrollY
                val contentHeight = (webView.contentHeight * webView.scale).toInt()

                if (event.x > width * 0.66) {
                    if (scrollY + height < contentHeight) {
                        webView.scrollBy(0, height - 40)
                    } else if (spineIndex < spineItems.size - 1) {
                        spineIndex++; renderCurrentChapter(); webView.scrollTo(0, 0)
                    }
                } else if (event.x < width * 0.33) {
                    if (scrollY > 0) {
                        webView.scrollBy(0, -(height - 40))
                    } else if (spineIndex > 0) {
                        spineIndex--; renderCurrentChapter(); webView.scrollTo(0, 0)
                    }
                }
                saveProgress()
            }
            true
        }
    }
}
