# Asap environmental volumetrik

Implementasi 10 Oktober 2026: volume kepadatan 3D di koordinat dunia, dengan integrasi sepanjang ray kamera, opacity, cahaya, angin dan turbulensi yang bergerak ke atas. Kamera bisa masuk ke dalamnya. Campfire menyala, soul campfire menyala, blok api dan soul fire menjadi sumber; nyala/emisi sebelumnya dipertahankan. Efek mandiri ini tidak memerlukan Physics Mod.

## Memakai switch

**Shader Pack Settings → Partikel → Sumber Asap**:

- **Shader (3D)**: volume shader menggantikan billboard campfire yang ditandai oleh resource pack penghubung. Ini default pengaturan bawaan.
- **Minecraft / Resource Pack**: volume dan seluruh alokasi/dispatch asap dimatikan; sprite campfire tampil kembali.

`resourcepacks/AA-Volumetric-Smoke-Bridge.zip` sudah dibuat dan ditambahkan pada daftar resource pack instance. Letakkan paling atas. Jika game sudah berjalan ketika file pengaturan berubah, aktifkan pack melalui menu Resource Packs; setelah itu **R** memuat ulang shader. Pack hanya mengubah dua definisi partikel campfire ke salinan sprite bertanda. Pixel yang terlihat dipertahankan; tanda hijau murni ada pada sudut yang semula transparan, dengan alpha 1/255. Alpha ini tetap di bawah ambang fragment shader partikel dan menjaga tag dari pembersihan RGB ber-alpha nol. Vertex shader menerima upload biasa, sRGB dan alpha premultiplied, serta tag lama. Partikel lain tidak ditandai. Tanpa shader, dalam mode Minecraft, atau ketika fitur GPU tidak didukung, sprite tetap dapat tampil normal.

Setelah pembaruan sprite penanda pada pack yang sudah aktif, gunakan **F3+T** untuk reload resource, lalu **R** untuk reload shader. Reload shader saja tidak memperbarui atlas partikel Minecraft.

Bridge membaca texture dari client dan pack yang dipilih saat pembuatan. Jika mengganti pack yang mengedit sprite campfire, bangun ulang melalui `tools/build_smoke_bridge.py --client <client.jar> --enable` dengan Python/Pillow. Pack asli tidak ditulis ulang. Untuk sprite dengan sudut opak, generator menambahkan border transparan sehingga ukuran relatif billboard fallback sedikit berubah; sprite vanilla yang dipakai pada pengujian tidak memerlukan border.

| Profil | Sumber asap | Langkah per plume | Jarak sumber |
| --- | --- | --- | --- |
| Ringan | Minecraft | 8 | 8 blok |
| Seimbang | Shader | 8 | 12 blok |
| Detail | Shader | 12 | 16 blok |
| Tracing Lokal Performa | Shader | 8 | 16 blok |
| Tracing Lokal Detail | Shader | 16 | 16 blok |

Default custom: Shader, 8 langkah, jarak 16 blok, kepekatan 0.65. Opsi custom lain tidak direset. Profil Ringan tetap menggunakan billboard untuk mempertahankan jalur paling murah.

## Pemeriksaan Physics Mod yang terpasang

File lokal yang diperiksa: `mods/physics-mod-3.2.5-mc-26.3-fabric.jar` (id `physicsmod`, versi 3.2.5). Jar memuat domain simulasi partikel, cache tabrakan, pembentukan volume dengan compute, ray marcher, dan integrasi Iris. Namun pada bytecode build ini, `ConfigClient.areSmokePhysicsEnabled()` dan `ConfigClient.areVolumetricSmokePhysicsEnabled()` selalu mengembalikan `false`; `SmokeVolumeRenderer.prepare()` juga hanya menghapus state yang sudah disiapkan. Jadi keberadaan class/GLSL di jar tidak berarti fitur smoke bisa dijalankan. Tidak ada pengaturan JSON shader yang bisa mengubah hasil fungsi tersebut. Situs pengembang mencantumkan Smoke Physics dan Volumetric Smoke dalam [fitur Pro](https://minecraftphysicsmod.com/pro).

Jalur volumetric Iris yang ada di jar memakai `MixinFinalPassRenderer` untuk menyiapkan dan menggambar volume milik mod ke render target utama. Ini berbeda dari memasukkan density mod ke pass pencahayaan shader kita: sampler yang terlihat pada include Iris `smoke_fragment.glsl` adalah jalur mesh/partikel, bukan API density 3D untuk shader pack. Pemeriksaan ini belum menemukan kontrak sampler/uniform density volumetric yang dapat digunakan langsung oleh composite ApaAdanyaShader.

Jika nanti memakai build dengan smoke aktif, integrasi pertama yang perlu diuji adalah render volume bawaan mod bersama Iris, dengan **Sumber Asap → Minecraft / Resource Pack** pada shader untuk menonaktifkan volume shader agar tidak menumpuk. Pengaturan ini tidak menyalakan Physics Mod; smoke harus diaktifkan dari mod sendiri. Pencahayaan, urutan post-processing, depth dan Distant Horizons tetap harus diuji di game dengan build tersebut. Tidak ada klaim kompatibilitas gameplay untuk fitur yang dinonaktifkan pada jar saat ini.

Memindahkan GLSL mod saja tidak membawa simulasi: posisi/umur/kecepatan partikel dan collision cache berasal dari kode mod. Shader lokal memakai aliran prosedural yang dibatasi supaya tetap ringan. `MixinCampfireBlockEntity` milik mod memanggil `CallbackInfo.cancel()` ketika pengganti asap berhasil dibuat: ini membatalkan pembuatan partikel di sisi game. Shader menerima vertex/UV/texture tanpa tipe partikel campfire, jadi tidak dapat menjalankan pembatalan Java tersebut; bridge hanya memberi identitas sprite agar vertex shader dapat menyaringnya. Jar mod dan konfigurasi mod tidak diubah. Bukti pemeriksaan lokal disimpan dalam `artifacts/physics-smoke-inspection.txt` dan `artifacts/physics-config-inspection.txt`.

## Aliran di sekitar blok

Vertex shadow terrain mencatat sumber dan penghalang sebelum pengujian depth fragment. Karena itu satu blok yang menutup campfire dari atas tidak menghapus sumbernya. Cache aliran memiliki 16 tingkat dengan selisih tinggi setengah blok. Penghalang diperiksa dari kolom sumber yang tetap, lalu delapan arah diperiksa untuk mencari tepi terbuka. Asap melebar secara lokal di bawah penghalang dan naik melalui bagian yang tidak tertutup blok. Pusat sebaran tetap pada campfire selama melewati penghalang; kepadatan di sel solid ditolak.

Kolom tambahan di cache menyimpan origin/waktu, identitas sumber, dan deskripsi penghalang; pusat aliran sebelumnya ditransportasikan ke atas dengan langkah waktu, angin dan inersia. Kamera melompat atau melewati batas grid tidak memindahkan jalur dunia. Riwayat direset pada sumber baru, benturan hash dengan sumber lain, teleport grid besar, jeda lebih dari 0.25 detik dan wrap waktu. Penghalang diperiksa ulang setiap frame, termasuk saat baru dipasang. Riwayat dan penghalang memakai texture dan dispatch yang sama.

Pelebaran mengikuti tepi terdekat, dengan tambahan radius maksimum 1.25 blok. Balok horizontal panjang tidak memperbesar semua sisi mengikuti ujung terjauhnya. Sebaran memiliki tepi lembut dan kepadatan dikurangi saat melebar; tidak dibuat sebagai cincin kosong atau cakram opak. Atap luas tanpa tepi yang terjangkau mempertahankan asap lokal di bawahnya, tanpa membuat volume di atas penghalang.

Pembengkokan dimulai hingga 1.6 blok sebelum penghalang dan pulih bertahap hingga tiga blok di atasnya. Profil lebar dievaluasi sebagai kurva kontinu di antara node cache, sehingga sambungan setengah blok tidak membentuk sisi kerucut yang patah. Pelebaran merespons pemasangan/penghapusan blok dengan relaksasi eksponensial berbasis waktu (konstanta 0.25 detik), tanpa bergantung pada FPS. Saat blok dilepas, band integrasi lama dipertahankan sampai sebaran menghilang. Sel solid tetap langsung menolak kepadatan selama transisi.

Noise memakai koordinat relatif sumber yang tetap dan bergerak ke atas, sehingga perubahan jalur tidak mengganti fase gumpalan. Lobus besar bergerak naik tanpa menambah lookup noise. Bentuk memudar di ujung, dengan pencahayaan ambient, matahari dan nyala warm/soul. Jam animasi berputar pada periode field yang sama agar sesi panjang tidak membuat bentuk tiba-tiba berganti.

Asap memakai pencahayaan langit/matahari yang luas, dengan ambient siang hampir netral dan glow warm/soul di dekat sumber. Sampel bayangan tunggal pada dua blok di atas campfire dihapus: titik tersebut dapat berada di dalam penghalang dan membuat seluruh plume berubah kebiruan. Kepadatan menggelapkan seluruh campuran cahaya secara seragam, sehingga pelebaran tidak mengubah perbandingan warna. Cahaya tetap mengikuti waktu siang/malam dan arah pandang; bayangan blok tidak lagi menggelapkan volume asap secara lokal.

Ini adaptasi mandiri gaya environmental smoke: kolom aliran dengan riwayat gerak, noise kepadatan dan ray marching. Kode simulasi/asset Physics Mod tidak dipindahkan. Ini pendekatan aliran prosedural lokal. Roof besar tanpa jalan keluar dalam radius pencarian membatasi plume di bawahnya. Penghalang dibaca sebagai sel blok, sehingga slabs/fences/daun belum mengikuti lubang mesh secara tepat. Ini belum simulasi tekanan/fluida, pengisian ruangan, interaksi peluru/ledakan, atau smoke grenade seperti [referensi volume resmi Valve](https://www.youtube.com/watch?v=_y9MpNcAitQ).

## Menjaga biaya GPU

- Tabel sumber per frame: 128 slot R32UI + empat mask aktif, payload 528 byte. Bank utama berisi 64 slot; sumber yang tergeser disimpan di bank cadangan dengan hash berbeda. Hash memakai koordinat blok dunia; prioritas jarak tetap deterministik. Vertex duplikat tidak menggandakan sumber atau kepadatan.
- Preset tracing memakai ulang voxel occupancy yang sudah ada. Campfire dan api terdaftar tidak menghalangi volume sendiri atau plume tetangganya. Preset tanpa voxel memakai grid 32³ R32UI, payload 128 KiB, dalam shadow pass yang sama.
- Satu dispatch `shadowcomp1`, dua workgroup berisi 64 invocation, membangun maksimum satu jalur per slot. Cache RGBA32F 21×128 berukuran 42 KiB; koordinat relatif grid menjaga presisi saat kamera melompat/berpindah origin.
- Pencarian tepi dibatasi tiga jarak per arah, hingga 1.125 blok. Tidak ada pencarian tepi jauh yang tidak terjangkau oleh sebaran lokal.
- Render memakai pass `composite` setengah resolusi yang sudah ada, bersama light shaft bila aktif. Tidak ada fullscreen render pass tambahan. RGBA16F `colortex21` pada 1280×720 sekitar 7 MiB per sisi; ping-pong Iris bisa memerlukan sekitar 14 MiB.
- Mask kosong melewati bank sumber dan sampling kepadatan. Ray di luar bounds plume tidak mengambil sampel kepadatan. Maksimum delapan plume dipilih dari jarak ray ke tubuh asap; kandidat kesembilan memberi transisi kontribusi lembut. Pemilihan tidak memakai urutan masuk kotak atau depth objek di depan.
- Per sampel: dua lookup cache jalur, occupancy, serta dua lookup noise hardware. Noise 3D awan 512 KiB dipakai ulang. Kurva kontinu memakai perhitungan tambahan tanpa texture/noise fetch tambahan. Pencahayaan asap tidak lagi mengambil sampel shadow map.
- Integrasi membengkokkan posisi sampel secara kontinu ke lapisan di sekitar penghalang. Pembagian integer ke lapisan kiri/tengah/kanan dihapus karena pergantian jumlah sampel membuat patahan bidang. Depth objek memotong bin integrasi, tanpa memindahkan semua sampel di depannya. Jumlah langkah per plume tetap 8/12/16; batas delapan plume membuat beban terburuk naik dibanding batas empat sebelumnya. Asap padat tetap membutuhkan waktu GPU lebih banyak.
- Volume yang tumpang tindih digabung memakai optical depth dan warna rata-rata berbobot. Ini pendekatan tanpa urutan yang menghindari pergantian warna/opacity saat bidang AABB bertukar urutan; belum integrasi fluida bersama yang tepat per titik.
- Rekonstruksi empat tap memeriksa depth dan geometri vanilla/DH; hasil half-resolution bertransisi lembut ke ray lokal saat dukungan tap berkurang. Siluet tanpa tap valid memakai ray lokal hingga depth aktual. Efek tidak dirender pada piksel tangan atau saat kamera di dalam air.

Volume mempunyai tinggi maksimum 7.5 blok dan sumber memudar mendekati batas jarak. Kapasitas 128 slot dengan bank cadangan mengurangi benturan hash; benturan pada kedua bank atau terlalu banyak sumber masih dapat menghilangkan emitter. Delapan volume per ray adalah batas kerja, dengan transisi lembut di batas pilihan. Asap belum dimasukkan ke refleksi air/SSR. Efek volume saat ini untuk Overworld. Mode shader menyembunyikan billboard campfire bertanda; di luar jarak sumber volume, asap campfire tidak dirender sebagai volume.

## Bukti pemeriksaan

`python tools/validate.py --advanced --smoke-only --profile=MEDIUM` menjalankan kompilasi/tautan serta fixture OpenGL native:

- Vertex shader shadow asli: sumber campfire/api warm/soul, koordinat negatif, lompatan/origin kamera, non-emitter, collision hash dan penangkapan blok penghalang yang menutupi campfire.
- Integrasi kepadatan LUT 3D asli: ray miss, depth occlusion/truncation, kamera di dalam, scene kosong, gerakan kecil dan kontinuitas jam animasi.
- Rekonstruksi setengah resolusi: menolak foreground dengan depth berbeda dan mempertahankan sampel valid.
- Blok di tiga tinggi di atas campfire: sebaran di delapan sisi, pusat tetap selama 60 frame, kepadatan nol di blok solid, serta integrasi 8 langkah selama 90 frame dengan kamera bergerak kecil.
- Balok horizontal pada sumbu X/Z dengan panjang 1/5/13/21 blok: lebar sebaran tetap lokal, tidak membentuk cincin besar. Atap bertumpuk dan luas tertutup mempertahankan kepadatan di bawahnya tanpa menembus ke atas.
- Cache voxel tracing dan grid khusus menghasilkan sebaran identik, dengan exclusion sel emitter sendiri.
- Pemasangan dan penghapusan penghalang selama dua detik pada 30/60 FPS: lebar berubah bertahap, waktu respons sama, dan kepadatan tidak menembus blok. Tangen profil kontinu diuji di batas-batas node cache.
- Warna warm/soul mempertahankan perbandingan RGB saat kepadatan berubah. Integrasi produksi menghasilkan warna identik ketika shadow map diubah dari terang ke tertutup penuh.
- Capture vertex native untuk 49 sumber api padat, urutan draw terbalik, serta vertex duplikat: seluruh sumber pada fixture tersimpan dan hasil tidak bergantung pada urutan.
- Adegan 25 api menghasilkan kepadatan lebih tinggi daripada satu api. Uji 1001 jarak foreground dan 121 arah ray memeriksa kontinuitas sampling/volume overlap. Rekonstruksi melewati ambang fallback lama tanpa peralihan mendadak. Preview tambahan: `many-fires-above.png` dan `many-fires-front.png`.
- Vertex shader particle asli dengan quad indexed sesuai urutan Minecraft 26.3: mode Shader menyembunyikan sprite bertanda; mode Minecraft memulihkannya; sprite atlas di sebelahnya tetap tampil.

Preview ada di `artifacts/volumetric-smoke/`, termasuk `campfire-roof.png`. Timer `GL_TIME_ELAPSED` mengukur pass produksi setengah resolusi dengan VL mati pada 1280×720, untuk adegan kosong, satu sumber dan sembilan sumber. Median/rentang ada di `gpu-results.json`. Angka timer tidak mencakup pencatatan penghalang, dispatch jalur atau rekonstruksi fullscreen, dan bukan pengukuran FPS Minecraft; context/aplikasi GPU lain dapat mengganggu hasil.

Tambahan pemeriksaan environmental smoke: riwayat gerak GPU pada 30/60 FPS, camera-grid boundary ketika melompat, reset sesudah jeda, pergantian hash, sumber hilang, atap yang baru dipasang serta tag partikel pada atlas sRGB/premultiplied. Log terbaru: `artifacts/environmental-smoke-validation-final.log`.

Log kompilasi dan regresi seluruh renderer: `artifacts/smoke-full-advanced-validation.log` dan `artifacts/smoke-full-fallback-validation.log`. Fixture native tidak menggantikan verifikasi binding/tampilan melalui Iris dan pengukuran FPS gameplay setelah reload.

Validasi pembaruan sebaran penghalang: 510 varian program advanced + 240 fallback berhasil dikompilasi dan ditautkan, mencakup kelima profil dan DH aktif/nonaktif. Seluruh fixture GPU termasuk kamera bergerak dan balok horizontal panjang lolos. Log: `artifacts/smoke-roof-spread-validation.log` dan `artifacts/smoke-roof-spread-fallback-validation.log`. Hasil ini belum merupakan verifikasi visual gameplay melalui Iris.

Pembaruan konsistensi warna dan transisi halus: seluruh fixture GPU, 510 varian advanced dan 240 fallback pada kelima profil dengan/tanpa DH lolos. Hasil dicatat pada `artifacts/smoke-smooth-color-validation.log` dan `artifacts/smoke-smooth-color-fallback-validation.log`. Fixture GPU tidak menggantikan penilaian tampilan gameplay setelah reload shader.

Pembaruan patahan bidang dan banyak api: seluruh fixture native, 510 varian advanced dan 240 fallback pada kelima profil dengan/tanpa DH lolos. Log: `artifacts/smoke-many-seams-validation.log` serta `artifacts/smoke-many-seams-fallback-validation.log`. Timer sintetis bukan pengukuran FPS gameplay dan tidak menjamin biaya delapan volume sama dengan empat.
