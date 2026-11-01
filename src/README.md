# ZARR CHAT — aplikasi Flutter

Klien Android untuk backend ZARR CHAT (Node.js + Socket.IO).

* v53: suara notifikasi benar-benar berbeda: Ping, Pop, Lonceng, Ding Dong kini punya berkas suara dan saluran notifikasi Android sendiri (sebelumnya pilihan hanya mengubah bunyi di dalam aplikasi, sedangkan notifikasi Android selalu memakai suara tetap). Baru: pilih MP3 sendiri (maks 8 MB) untuk Suara Notifikasi (maks 30 detik) dan untuk Nada Panggilan (maks 60 detik) di Pengaturan > Audio & Notifikasi; MP3 dipakai untuk bunyi di dalam aplikasi, notifikasi Android (termasuk saat aplikasi tertutup, lewat Backend v35), dan dering telepon masuk. Tile baru: Nada Panggilan dan Tes nada panggilan. Berkas baru: `res/raw/notif_ping|pop|lonceng|dingdong.wav`; diubah: `lib/audio_storage.dart`, `lib/push.dart`, `lib/calls.dart`, `android/.../MainActivity.kt` (saluran `com.zarr.chat/sounds`). Butuh Backend v35.
* v52: layar Panggilan dan Notifikasi punya mode pilih ala WhatsApp: tekan lama sebuah baris = langsung terpilih (baris diwarnai; di Panggilan foto bercentang hijau, di Notifikasi ada lingkaran centang), bar atas berganti jadi jumlah terpilih + ikon Hapus + menu titik tiga (Pilih semua); ketuk baris lain untuk menambah/mencabut, tombol kembali membatalkan. Hapus meminta konfirmasi. Tulisan waktu di riwayat panggilan tidak lagi dobel ("18:18 18:18" -> "18:18"; hari lain "Kemarin, 18:18"). Butuh Backend v34. Berkas yang berubah: `lib/calls.dart`, `lib/chats_tab.dart`, `lib/widgets.dart`.
* v51: panel emoji & sticker dibuat sedang seperti WhatsApp: sticker 6 kolom (sel maksimal 70 dp, sebelumnya 4 kolom yang besar), kotak "Buat stiker" jadi sel pertama grid (menggantikan tombol lebar), jarak antar-sticker dan judul bagian dirapatkan, tab Emoji/Sticker lebih ramping, emoji ±9 kolom, tinggi panel 290 dp. Berlaku juga untuk panel sticker di saluran. Berkas yang berubah: `lib/chat_screen.dart`.
* v50: daftar chat bergaya WhatsApp: tekan lama sebuah chat/grup = langsung masuk mode pilih (baris diwarnai + centang hijau di foto, bar atas berganti menjadi jumlah terpilih dengan ikon Sematkan, Hapus, Bisukan, Arsipkan, dan menu titik tiga: Pilih semua / Lihat profil). Ketuk baris lain untuk menambah/mencabut pilihan; tombol kembali membatalkan pilihan. Chat yang disematkan (maksimal 3, disimpan di HP ini) tampil paling atas dengan ikon pin. Berkas yang berubah: `lib/chats_tab.dart`.
* v49: menu titik tiga di pojok kanan atas penampil foto dan video (chat, grup, channel) dengan "Simpan ke galeri" seperti WhatsApp: foto masuk ke Pictures/ZARR CHAT, video ke Movies/ZARR CHAT (Android 10+ tanpa izin tambahan; Android 9 ke bawah meminta izin penyimpanan). Foto/video yang dibuka tetap otomatis tersimpan di folder aplikasi. File baru yang berubah: `lib/media.dart`, `MainActivity.kt` (saluran `com.zarr.chat/gallery`), `AndroidManifest.xml`.
* v48: gelembung "bot sedang merespon" diperkecil (robot, tulisan, titik, bantalan, sudut, bayangan); tulisan BOT MD diubah dari "sedang memproses" menjadi "sedang", dan gelembung Meta AI (tiga titik) ikut diperkecil.
* v47: tampilan chat dirapikan: keterangan di bawah foto/video/lagu dibatasi selebar media-nya (tidak ada lagi ruang kosong di samping foto atau pemutar lagu), ada jarak antara pemutar lagu dan keterangannya, dan durasi pemutar memakai durasi dari keterangan bot ("⏱️ 3:12") sehingga tidak tampil "--:--" sebelum diputar.

## Ganti domain / port
Ubah satu baris di `lib/config.dart`:

```dart
const String kBaseUrl = 'http://DOMAIN:PORT';
```
Lalu `flutter build apk --release`. API, Socket.IO, media, dan panel admin otomatis ikut.
Port harus sama dengan `PORT` di `config.js` backend.

## Panel Admin
Akun admin/superadmin/developer melihat menu **Pengaturan → Panel Admin** (dashboard, pengguna, laporan, pengumuman,
pengaturan, audit log, error). Semua dibuka di dalam aplikasi, tanpa browser.

## Panggilan
Panggilan antar jaringan berbeda butuh server TURN di backend (lihat README backend).
Nada dering (panggilan masuk) dan nada tunggu (penelepon) dibuat otomatis di dalam aplikasi, tanpa file suara tambahan.
Layar panggilan video punya tombol bisukan, speaker, kamera mati/hidup, dan balik kamera depan/belakang.

## Saluran (Channel)
Tab **Pembaruan** berisi kartu Status dan daftar Saluran. Tombol **+** membuat status atau saluran baru; **Jelajahi** mencari saluran.
Pemilik saluran mengirim teks/foto/video; pengikut membaca, memberi reaksi (tahan pesan), membisukan, atau berhenti mengikuti.
Kode ada di `lib/channels.dart`. Backend wajib versi yang menyertakan `migrations/004_channels.sql` (otomatis dijalankan saat server start).

## Foto profil / grup / saluran
Memilih foto membuka layar **Atur foto** (`lib/avatar_cropper.dart`): geser, cubit/slider zoom, putar, lalu **Selesai** — seperti WhatsApp.
Hasilnya PNG persegi 512x512 yang baru diunggah setelah Anda menekan Selesai.

## Kode undangan grup
Kode berupa 6 atau 8 angka acak (dibuat server), sehingga domain/port tidak terlihat. Menu **+ → Gabung dengan kode** untuk bergabung.

## Centang biru grup & saluran
Hanya bisa diberikan dari **Panel Admin → tab Grup / Saluran** (owner/admin), bukan oleh pemilik grup/saluran.

## Build
`flutter pub get` lalu `flutter build apk --release`. Package: `com.zarr.chat`. Butuh Flutter 3.24+ (Dart 3.5+); compileSdk 35 dan NDK 27 diatur di `android/app/build.gradle.kts`.
HTTP (tanpa HTTPS) sudah diizinkan lewat `usesCleartextTraffic` dan `network_security_config.xml`.

## Batasan
- Belum ada push notification saat aplikasi tertutup.
- Panggilan hanya tersambung jika penerima membuka aplikasi; antar jaringan berbeda butuh server TURN.
- Pesan belum end-to-end encrypted.

## Sticker & pesan (gaya WhatsApp)
- **Buat sticker**: pilih gambar → editor (`lib/sticker_editor.dart`): cubit untuk zoom, geser, putar dua jari, tombol Putar/Balik/Pas/Penuh, pilih latar (transparan/warna) → hasil PNG 512×512.
- **Panel sticker**: ketuk = langsung kirim; tahan = Kirim / Tambahkan ke favorit / Hapus sticker.
- **Sticker di chat**: ketuk sticker (milik sendiri atau orang lain) → Tambahkan / Hapus dari favorit (endpoint backend `POST /api/stickers/save`).
- **Tahan pesan** = mode pilih (bilah atas: balas, salin, teruskan, hapus, ⋮). Ikon hapus membuka dialog merah "Hapus untuk semua orang / Hapus untuk saya".
- **Foto profil**: di daftar chat → pratinjau kecil (pesan/telepon/video/info); di chat, ketuk nama/foto → halaman Info kontak; ketuk foto di sana → layar penuh dengan zoom (`lib/profile_view.dart`).

## Background & Wallpaper
Pengaturan → **Background & Wallpaper** (`lib/wallpaper.dart`). Dua bagian: *Background aplikasi* (semua layar) dan *Wallpaper chat*.
Masing-masing: Bawaan (belum diatur), Upload foto dari galeri, dan 5 gambar bawaan di `assets/wallpapers/wp1..wp5.jpg` (ganti file untuk mengubahnya).
Ada slider Redupkan (chat) / Kabut (aplikasi). Pilihan disimpan di perangkat (SharedPreferences + salinan foto di penyimpanan aplikasi).

## Musik Latar
Pengaturan → **Suara → Musik Latar** (`lib/music.dart`). Saat dinyalakan, lagu `assets/audio/musik_latar.mp3` diputar berulang
lewat layanan foreground (`just_audio` + `just_audio_background`), jadi tetap menyala saat aplikasi dikecilkan/ditutup, dan
otomatis menyala lagi setiap aplikasi dibuka, sampai kamu mematikannya. Pilihan disimpan di perangkat (SharedPreferences).
Musik dijeda otomatis selama panggilan suara/video lalu dilanjutkan. Ganti lagu dengan menimpa file mp3 di `assets/audio/`.
Android: izin `FOREGROUND_SERVICE_MEDIA_PLAYBACK` + `POST_NOTIFICATIONS`, `MainActivity` memakai `AudioServiceActivity`.

## Tampilan neo (garis hitam)
Kartu/baris memakai garis tinta tebal + bayangan keras dan latar solid (`NeoCard`, `NeoTile`, `NeoSwitchTile`, `NeoSection`, `NeoRow`
di `lib/widgets.dart`) sehingga tombol dan daftar tetap jelas di atas foto background. Dipakai di Pengaturan beserta sub-halamannya,
daftar chat/kontak, arsip, panggilan, saluran, dan halaman Background & Wallpaper.

## Admin saluran & sticker di saluran
- **Admin saluran** (`ChannelAdminsPage` di `lib/channels.dart`): Info saluran → *Admin saluran*. Pemilik menekan **Tambah admin**, mencari nama/nomor (+62…), lalu orang itu
  otomatis ikut mengikuti saluran dan mendapat notifikasi. Admin boleh mengirim pesan/foto/video/sticker, menghapus pesan, dan mengubah info saluran;
  hanya pemilik yang bisa menambah/mencabut admin dan menghapus saluran. Admin bisa **Mundur** sendiri. Maksimal 10 admin.
- **Sticker di saluran**: di kolom ketik saluran (pemilik/admin) ada tombol sticker → panel yang sama dengan chat (favorit + paket). Ketuk sticker = langsung terkirim.
  Pengikut mengetuk sticker di saluran → **Tambahkan ke favorit**, lalu bisa dipakai di chat dan saluran lain.
- Backend wajib versi yang menyertakan `migrations/005_channel_admins.sql` (otomatis dijalankan saat server start).


## Grup chat (baru)

- Daftar chat kini menampilkan chat pribadi dan grup bersama. Tombol (+) di tab Chat: Chat baru, Grup baru, Gabung lewat tautan.
- File baru: `lib/groups.dart` (tautan, mention, kartu undangan, pemilih anggota, teruskan, laporan), `lib/group_pages.dart` (buat grup, info grup,
  edit, tambah anggota, media bersama, info pesan), `lib/group_chat.dart` (layar chat grup).
- Mengetuk tautan undangan di dalam chat membuka halaman "Gabung grup" di dalam aplikasi.
- Tidak ada paket baru di pubspec.yaml.

## Notifikasi push (opsional)

Agar notifikasi pesan/telepon/broadcast muncul walau aplikasi ditutup atau sedang main game:
1. Buat proyek Firebase, tambahkan app Android dengan package `com.zarr.chat`.
2. Unduh `google-services.json` dan taruh di `android/app/google-services.json`.
3. Pasang service account di backend (lihat README backend), lalu build ulang APK.
Tanpa `google-services.json` build tetap berhasil dan aplikasi berjalan normal tanpa push.

## Catatan perbaikan (v26)
- Status: foto/video dimuat dulu sebelum waktu berjalan (tidak lagi tertutup sendiri pada koneksi lambat), video mengikuti posisi putar asli, ada tombol "Coba lagi" bila gagal, dan daftar Pembaruan otomatis segar (status baru, buka tab, kembali ke aplikasi).
- Panggilan: sinyal WebRTC tertahan saat socket putus lalu dikirim ulang, mulai ulang jalur (ICE restart) otomatis, panggilan masuk tidak dobel/terlewat.
- Koneksi: banner "Menyambungkan ulang" hanya muncul bila putus > 8 detik; sambungan "mati diam-diam" dideteksi dan dibuat ulang otomatis.

## Pembaruan notifikasi & suara (v28)
- Saluran notifikasi baru `*_v2` dengan suara kustom keras: `android/app/src/main/res/raw/notif_message.ogg`, `notif_call.ogg`, `notif_broadcast.ogg`.
- Wajib: taruh `google-services.json` (app `com.zarr.chat`) di `android/app/google-services.json`, lalu build ulang APK.
- Pengaturan > Audio & Notifikasi: tombol **Tes notifikasi** dan **Izinkan berjalan di latar belakang** (pengecualian hemat baterai). Dialog izin latar belakang juga muncul sekali setelah login.
- Nada pesan/dering diperkeras (harmonik + kompresi lembut), memakai aliran notifikasi/dering HP; suara lawan bicara saat panggilan diperkuat 2,5x; rekaman pesan suara memakai auto gain.

## Notifikasi push (FCM) — WAJIB untuk notifikasi saat aplikasi ditutup
1. Firebase Console → proyek yang sama dengan `firebase-service-account.json` di backend → tambahkan app Android dengan package **`com.zarr.chat`**.
2. Unduh `google-services.json`, taruh di **`android/app/google-services.json`** (sejajar `android/app/build.gradle.kts`).
3. Build ulang APK, pasang, login, lalu buka aplikasi sekali. Panel Admin → Broadcast akan menampilkan "Push aktif • 1 HP terdaftar".
Tanpa file itu Firebase tidak aktif dan HP tidak terdaftar. Sebagai cadangan, notifikasi HP tetap muncul dari koneksi socket selama aplikasi masih hidup di latar belakang.

