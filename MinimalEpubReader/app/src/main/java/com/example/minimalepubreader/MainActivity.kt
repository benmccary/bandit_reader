package com.example.minimalepubreader

import android.content.*
import android.net.Uri
import android.os.BatteryManager
import android.os.Bundle
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import nl.siegmann.epublib.epub.EpubReader
import java.io.InputStream
import java.text.SimpleDateFormat
import java.util.*

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private lateinit var progressText: TextView
    private lateinit var openButton: Button
    private var spineIndex = 0
    private var spineItems: List<nl.siegmann.epublib.domain.SpineReference> = emptyList()
    private var currentUri: Uri? = null
    private var pendingScrollY = 0
    private var totalBookSize: Long = 0

    private val filePickerLauncher = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        uri?.let { 
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            try { contentResolver.takePersistableUriPermission(it, flags) } catch (e: Exception) {}
            val prefs = getSharedPreferences("ReaderPrefs", Context.MODE_PRIVATE)
            openEpub(it, prefs.getInt("${it}_index", 0), prefs.getInt("${it}_scroll", 0)) 
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        webView = findViewById(R.id.webView)
        progressText = findViewById(R.id.progressText)
        openButton = findViewById(R.id.openButton)

        webView.settings.apply { javaScriptEnabled = false; defaultFontSize = 20 }

        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                if (pendingScrollY > 0) {
                    view?.postDelayed({ 
                        view.scrollTo(0, pendingScrollY)
                        pendingScrollY = 0 
                        updateStatusLine()
                    }, 200)
                } else {
                    updateStatusLine()
                }
            }
        }

        val prefs = getSharedPreferences("ReaderPrefs", Context.MODE_PRIVATE)
        prefs.getString("global_last_uri", null)?.let {
            val uri = Uri.parse(it)
            openEpub(uri, prefs.getInt("${uri}_index", 0), prefs.getInt("${uri}_scroll", 0))
        }

        openButton.setOnClickListener { 
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
                totalBookSize = spineItems.sumOf { it.resource.data.size.toLong() }
                renderCurrentChapter()
                // Hide button after loading
                toggleUI(false)
            }
        } catch (e: Exception) { Log.e("EPUB_READER", "Load failed", e) }
    }

    private fun toggleUI(show: Boolean) {
        val visibility = if (show) View.VISIBLE else View.GONE
        openButton.visibility = visibility
        progressText.visibility = visibility
    }

    private fun updateStatusLine() {
        if (spineItems.isEmpty() || totalBookSize == 0L) return
        var bytesRead: Long = 0
        for (i in 0 until spineIndex) { bytesRead += spineItems[i].resource.data.size }
        val contentHeight = (webView.contentHeight * webView.scale).toInt()
        if (contentHeight > 0) {
            bytesRead += (spineItems[spineIndex].resource.data.size * (webView.scrollY.toFloat() / contentHeight.toFloat())).toLong()
        }
        val percent = (bytesRead.toFloat() / totalBookSize.toFloat() * 100).toInt()
        val time = SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date())
        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val batLevel = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        progressText.text = "$time  |  $batLevel%  |  $percent% Complete"
    }

    private fun renderCurrentChapter() {
        if (spineItems.isEmpty()) return
        val html = String(spineItems[spineIndex].resource.data)
        val styledHtml = "<html><body style='margin:5%; font-family:serif;'>$html</body></html>"
        webView.loadDataWithBaseURL(null, styledHtml, "text/html", "UTF-8", null)
    }

    private fun setupTouchNavigation() {
        webView.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_UP) {
                val width = webView.width
                val height = webView.height
                val contentHeight = (webView.contentHeight * webView.scale).toInt()

                when {
                    // LEFT 33%: Previous Page
                    event.x < width * 0.33 -> {
                        if (webView.scrollY > 0) {
                            webView.scrollBy(0, -(height - 40))
                        } else if (spineIndex > 0) {
                            spineIndex--; renderCurrentChapter(); webView.scrollTo(0, 0)
                        }
                    }
                    // RIGHT 33%: Next Page
                    event.x > width * 0.66 -> {
                        if (webView.scrollY + height < contentHeight) {
                            webView.scrollBy(0, height - 40)
                        } else if (spineIndex < spineItems.size - 1) {
                            spineIndex++; renderCurrentChapter(); webView.scrollTo(0, 0)
                        }
                    }
                    // CENTER 33%: Toggle Menu
                    else -> {
                        val isCurrentlyVisible = openButton.visibility == View.VISIBLE
                        toggleUI(!isCurrentlyVisible)
                    }
                }
                updateStatusLine()
                saveProgress()
            }
            true
        }
    }

    private fun saveProgress() {
        currentUri?.let { uri ->
            getSharedPreferences("ReaderPrefs", Context.MODE_PRIVATE).edit().apply {
                putString("global_last_uri", uri.toString())
                putInt("${uri}_index", spineIndex)
                putInt("${uri}_scroll", webView.scrollY)
                apply()
            }
        }
    }
}
