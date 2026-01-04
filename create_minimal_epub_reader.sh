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
EOL

# Step 11: activity_main.xml
cat > "$RES_DIR/layout/activity_main.xml" <<EOL
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical">
    <Button android:id="@+id/openButton"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="Open Book" />
    <WebView android:id="@+id/webView"
        android:layout_width="match_parent"
        android:layout_height="match_parent" />
</LinearLayout>
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
