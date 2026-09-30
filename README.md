# VERITAS

Prototipe Flutter untuk alur tata kelola pengakuan bersalah berdasarkan briefing VERITAS. Mottonya: *Veritas ante Confessionem* — Kebenaran di Atas Pengakuan.

## Alur bisnis end-to-end

1. **Registrasi perkara** menyimpan nomor perkara, kategori, dasar hukum, dan terdakwa. Perkara dan posisi tahapnya disimpan lokal dan dipisahkan per perkara.
2. **SARING** mensyaratkan konfirmasi hukum, status pelaku pertama, kesiapan pemulihan, dan advokat. Alasan serta dasar dokumen wajib dicatat.
3. **SINAR** meminta nilai dan alasan/sumber bukti untuk setiap parameter tertimbang. Skor <50 menghentikan jalur; 50–87 meminta referensi tinjauan Kasi Pidum; 88–100 tetap merupakan dukungan keputusan manusia.
4. **JANGKAR** meminta pemetaan tiap unsur yang dimasukkan ke dua berkas bukti berbeda. Bukti yang diunggah diberi checksum SHA-256 dan dikaitkan ke perkara.
5. **NURANI** memerlukan konfirmasi advokat, status sukarela yang affirmative, alasan, dan referensi sesi. Status tidak sukarela menghentikan jalur.
6. **SUARA KORBAN** mencatat dampak, perlindungan, dan preferensi korban.
7. **TIMBANG** memeriksa batas bawah/atas dan usulan; usulan di luar rentang memerlukan referensi persetujuan Kasi Pidum dan Kajari/pejabat berwenang.
8. **GERBANG** membutuhkan konfirmasi lima gerbang, lalu **FORUM VERITAS** memerlukan checklist sembilan langkah.
9. **AKTA** tidak bisa lanjut tanpa pengakuan perbuatan, konsekuensi dengan alasan hukum, dan pemulihan korban.
10. **SAMBUNG** mencatat nomor paket; **PUTUSAN** memerlukan hasil dan referensi penetapan. Penolakan atau pencabutan mengembalikan perkara ke proses biasa dan mencatat penerapan Firewall Pengakuan.
11. **PULIH** mencatat cicilan, bukti transaksi, dan konfirmasi korban. Nilai yang terverifikasi harus memenuhi jumlah akta sebelum perkara masuk CAKRAWALA.
12. **CAKRAWALA** menyelesaikan alur setelah alasan tinjauan mutu dicatat. Keputusan tahap dan alasannya masuk dossier.

Transisi tahap hanya tersedia setelah alasan umum (minimal 20 karakter) dan prasyarat tahap selesai. Perkara dapat dihentikan dari setiap tahap dengan alasan tertulis. Tahap, hasil terstruktur, dan audit disimpan sehingga pengguna dapat memilih perkara lagi dan melanjutkan alurnya.

## Keputusan desain yang disengaja

- Bukti dinilai sebelum pengakuan. Nilai SINAR tidak menimpa kegagalan bukti atau kesukarelaan.
- Tidak ada nilai SINAR yang terpilih otomatis; semua delapan rating dan alasan sumbernya harus diisi.
- Pembayaran restitusi boleh dicatat bertahap, tetapi tahap tidak selesai sebelum total terverifikasi sesuai akta.
- Hasil pengadilan selain pengesahan memutus jalur plea; catatan tidak mengubah proses biasa menjadi jalur yang memakai pengakuan.
- Setiap berkas bukti menyimpan checksum SHA-256; setiap keputusan tahap mempunyai hash, dan peristiwa audit membentuk rantai hash. Perubahan lokal yang tak cocok akan mengunci transisi tahap.

## Preview web publik

Preview tersedia di [https://campusinnovate.github.io/VERITAS/](https://campusinnovate.github.io/VERITAS/). Setiap push ke branch `main` menjalankan analisis Flutter, membangun web dengan base path GitHub Pages, lalu menerbitkan preview secara otomatis. Workflow dapat dijalankan ulang lewat tab **Actions**.

Login demo: `andi.demo` / `veritas123`; OTP: `246810`. Seluruh data adalah simulasi lokal. Jangan masukkan data perkara atau informasi pribadi yang nyata.

## Menjalankan

```bash
flutter pub get
flutter run
```

Build web:

```bash
flutter build web --release
```

## Login dan SSO demo

Layar masuk menerima akun uji `andi.demo` dengan kata sandi `veritas123` (tersedia tombol isi otomatis). Tekan **Lanjut melalui SSO demo**, pilih profil peran, lalu masukkan OTP `246810`. Pemulihan kata sandi dan pengajuan akun juga bisa dicoba sebagai simulasi. Tidak ada kredensial yang disimpan atau dikirim; pilihan peran hanya mengganti konteks tampilan demo dan belum menerapkan RBAC.

## Android APK

Build APK universal untuk instalasi lokal dengan:

```bash
flutter build apk --release
```

Hasilnya berada di `build/app/outputs/flutter-apk/app-release.apk`. APK hasil build tidak disimpan di Git; salin sendiri ke folder `release/` jika diperlukan. Pada Android, pindahkan APK ke perangkat, buka berkasnya, lalu izinkan pemasangan dari sumber tersebut jika diminta. Build prototipe ini memakai signing debug untuk sideload; untuk distribusi resmi perlu kunci signing rilis dan konfigurasi keamanan organisasi.

## Batas prototipe

Ini belum sistem operasional atau penilaian hukum. Login dan peran hanyalah simulasi; identitas, referensi persetujuan, dan checklist belum dibuktikan oleh akun/layanan pejabat yang berbeda. Data hanya disimpan lokal tanpa enkripsi. Rantai hash lokal mendeteksi perubahan yang tidak konsisten, tetapi bukan ledger append-only dengan timestamp tepercaya atau salinan eksternal; administrator perangkat dapat mengganti manifest dan rantainya sekaligus.

SARING, ambang SINAR, aturan TIMBANG, dan daftar formil adalah parameter rancangan dari briefing, bukan interpretasi hukum yang telah disahkan. Sebelum pilot, Kejaksaan perlu mengunci policy version serta aturan resmi, peran dan pemisahan tugas, sumber verifikasi, retensi dan privasi data, serta format audit.

Integrasi CMS/SPPT-TI, SIPP/e-Court, SSO/MFA, RBAC server, tanda tangan elektronik, rekaman NURANI, portal korban, notifikasi SUAR, AI PELITA, enkripsi, penyimpanan privat, dan ledger JEJAK terpisah belum terhubung. Label “referensi simulasi” menandai aktivitas eksternal yang belum dilakukan aplikasi. Jangan gunakan data atau perkara nyata.
