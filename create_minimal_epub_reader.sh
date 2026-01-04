#!/bin/bash

BASE_DIR="$(pwd)"                  # ~/dev/minimal_reader
PROJECT_DIR="$BASE_DIR/MinimalEpubReader"
APP_DIR="$PROJECT_DIR/app"
SRC_DIR="$APP_DIR/src/main"
PACKAGE_DIR="$SRC_DIR/java/com/example/minimalepubreader"
RES_DIR="$SRC_DIR/res"
ASSETS_DIR="$SRC_DIR/assets"
LIBS_DIR="$APP_DIR/libs"
ASSET_SOURCE="$BASE_DIR/assets/book.epub"
EPUBLIB_JAR="$BASE_DIR/epublib-core-3.1.jar"
EPUBLIB_URL="https://maven.xmappservice.com/nexus/content/repositories/public/com/positiondev/epublib/epublib-core/3.1/epublib-core-3.1.jar"

echo "🛠 Creating Minimal EPUB Reader project in $PROJECT_DIR..."

# Remove old project if exists
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# Step 1: create minimal Gradle build and wrapper
cd "$PROJECT_DIR"
gradle init --type basic
gradle wrapper --gradle-version 8.1.1
chmod +x gradlew

# Step 2: create project structure
mkdir -p "$PACKAGE_DIR"
mkdir -p "$RES_DIR/layout"
mkdir -p "$RES_DIR/values"
mkdir -p "$ASSETS_DIR"
mkdir -p "$LIBS_DIR"

# Step 3: copy EPUB
if [ ! -f "$ASSET_SOURCE" ]; then
    echo "❌ Missing EPUB file at $ASSET_SOURCE"
    exit 1
fi
cp "$ASSET_SOURCE" "$ASSETS_DIR/"

# Step 4: copy epublib-core
if [ ! -f "$EPUBLIB_JAR" ]; then
    echo "📥 Downloading epublib-core-3.1.jar..."
    curl -L -o "$EPUBLIB_JAR" "$EPUBLIB_URL"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to download epublib-core. Exiting."
        exit 1
    fi
fi
cp "$EPUBLIB_JAR" "$LIBS_DIR/"

# Step 5: write gradle.properties
cat > "$PROJECT_DIR/gradle.properties" <<EOL
android.useAndroidX=true
android.enableJetifier=true
EOL

# Step 6: root build.gradle
cat > "$PROJECT_DIR/build.gradle" <<EOL
buildscript {
    repositories {
        google()
        mavenCentral()
        flatDir { dirs 'app/libs' }
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.1.1'
        classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.0"
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        flatDir { dirs 'app/libs' }
    }
}
EOL

# Step 7: settings.gradle
cat > "$PROJECT_DIR/settings.gradle" <<EOL
rootProject.name = 'MinimalEpubReader'
include ':app'
EOL

# Step 8: app/build.gradle
cat > "$APP_DIR/build.gradle" <<EOL
apply plugin: 'com.android.application'
apply plugin: 'kotlin-android'

android {
    namespace 'com.example.minimalepubreader'
    compileSdk 34

    defaultConfig {
        applicationId "com.example.minimalepubreader"
        minSdk 26
        targetSdk 34
        versionCode 1
        versionName "1.0"
    }

    buildTypes {
        release { minifyEnabled false }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_11
        targetCompatibility JavaVersion.VERSION_11
    }

    kotlinOptions { jvmTarget = '11' }
}

repositories {
    google()
    mavenCentral()
    flatDir { dirs 'libs' }
}

dependencies {
    implementation files('libs/epublib-core-3.1.jar')
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'androidx.core:core-ktx:1.12.0'
    implementation 'org.slf4j:slf4j-android:1.7.36'
}
EOL

# Step 9: AndroidManifest.xml
cat > "$SRC_DIR/AndroidManifest.xml" <<EOL
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.minimalepubreader">
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.READ_MEDIA_DOCUMENTS" />
    <application
        android:label="MinimalEpubReader"
        android:theme="@style/Theme.AppCompat.Light.NoActionBar"
        android:hardwareAccelerated="true">
        <activity android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
EOL

# Step 10: MainActivity.kt
cat > "$PACKAGE_DIR/MainActivity.kt" <<'EOL'
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
EOL

# Step 11: activity_main.xml
cat > "$RES_DIR/layout/activity_main.xml" <<EOL
<?xml version="1.0" encoding="utf-8"?>
<RelativeLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <Button android:id="@+id/openButton"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="Open Book"
        android:layout_alignParentTop="true" />

    <TextView android:id="@+id/progressText"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:gravity="center"
        android:padding="4dp"
        android:textSize="12sp"
        android:text="Loading status..."
        android:background="#FFFFFF"
        android:textColor="#000000"
        android:layout_alignParentBottom="true" />

    <WebView android:id="@+id/webView"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:layout_below="@id/openButton"
        android:layout_above="@id/progressText" />

</RelativeLayout>
EOL

# Step 12: strings.xml
cat > "$RES_DIR/values/strings.xml" <<EOL
<resources>
    <string name="app_name">MinimalEpubReader</string>
</resources>
EOL

echo "✅ Minimal EPUB Reader project created in $PROJECT_DIR!"
echo "Next steps:"
echo "1️⃣ Build the APK: cd $PROJECT_DIR && ./gradlew assembleDebug"
echo "2️⃣ Install on Supernote: adb install -r app/build/outputs/apk/debug/app-debug.apk"
