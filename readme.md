# Bandit Reader 🦹‍♂️📖

A minimalist, high-performance EPUB reader designed specifically for E-ink devices like the **Supernote Nomad**. 

Bandit Reader strips away the bloat of modern reading apps to provide a clean, distraction-free experience with optimized refresh rates and high-contrast UI.

## Features
* **True Progress Tracking:** Calculates completion percentage based on total book bytes and scroll position, not just chapter count.
* **E-ink Optimized UI:** Ultra-minimalist interface with auto-hiding controls to maximize screen real estate.
* **Integrated Status Bar:** Quick-glance Clock, Battery Level, and Progress % accessible via a center-tap toggle.
* **Gesture Navigation:** Left/Right 33% taps for page turns; Center 33% tap for menu.
* **Deep Memory:** Automatically remembers the last book opened and your exact scroll position.

## Dependencies
To build this project, you need the following installed on your machine:

1.  **JDK 11:** Required for Android Gradle builds.
2.  **Android SDK:** Specifically `build-tools` and `platform-tools` (for `adb`).
3.  **Gradle 8.1.1:** (Included via the wrapper in the build script).
4.  **Epublib-core 3.1:** The engine used for parsing EPUB files.
5.  **Adb:** To sideload the app onto your Nomad.

## Installation & Deployment

Follow these commands to build and install **Bandit Reader** on your device:

### 1. Build the Project
Run the master bash script provided in the repo to generate the Android project structure:
```bash
chmod +x create_minimal_epub_reader.sh
./create_minimal_epub_reader.sh