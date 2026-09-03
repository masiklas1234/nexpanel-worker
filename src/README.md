# ZENTRA MOD CONTROL (Flutter)

Aplikasi kontrol untuk memantau dan mengendalikan device anak secara remote.

## Fitur
- 📋 List device yang terdaftar (online/offline)
- ⚡ Flash ON/OFF/Blink — nyalakan/matikan senter HP anak
- 🔒 Lock Device — kunci layar HP anak dengan pesan & PIN
- 🔓 Unlock Device — buka kunci layar HP anak
- 📺 Live Screen — pantau layar HP anak secara real-time
- 📷 Live Camera — lihat kamera HP anak secara real-time
- 🖼️ Set Wallpaper — ganti wallpaper HP anak dari URL foto

## Konfigurasi Server
Edit `lib/main.dart` baris pertama:
```dart
const String SERVER_URL = "http://denisrespanel.pteroq.xyz:10603";
```

## Cara Build

1. Install Flutter SDK
2. Extract ZIP dan masuk ke folder project
3. Edit `android/local.properties` sesuai path SDK lokal
4. Install dependency:
   ```
   flutter pub get
   ```
5. Build APK:
   ```
   flutter build apk --release
   ```
   Hasil: `build/app/outputs/flutter-apk/app-release.apk`

## Dependencies
- `http` — request ke backend server
- `shared_preferences` — cache data device lokal
