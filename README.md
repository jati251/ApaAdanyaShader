# ApaAdanyaShader

Shaderpack untuk Minecraft Java 26.3, Iris 1.11.7 dan Sodium 0.9.2. Mendukung Distant Horizons, material LabPBR, air dengan gelombang terfilter, awan berlapis, bayangan awan dan cahaya pantul lokal. Rendering utama memakai GLSL 330; optimasi depth dan denoiser GI memakai compute opsional.

## Preset

Empat preset menu dan ekspor memiliki pengaturan yang sama:

| Preset | Shadow map / jarak | Awan / sampel cahaya | GI / refleksi | Air / material | FSR default |
|---|---|---|---|---|---|
| Lightweight (Potato) | 256 / 48 blok, 4 tap | 2D dengan cache setengah resolusi + atlas bayangan 128² | GI, AO dan SSR mati | 4 wave band ringan, refraksi, caustics, filter 2× | Ultra Quality (77%) |
| Balanced | 1024 / 96 blok | 12 langkah, 2 lapis / 2 | AO temporal, SSR 16 | 4 oktaf, filter 4× | Ultra Quality (77%) |
| Detailed | 2048 / 144 blok | 20 langkah, 3 lapis / 4 | GI 2 ray × 24 langkah, SSR 24 | 6 oktaf, filter 4×, LabPBR | Ultra Quality (77%) |
| Extreme | 4096 / 224 blok | 32 langkah, 3 lapis / 6, resolusi penuh | GI 8 ray × 48 langkah, SSR 64 | 7 oktaf, filter 8×, LabPBR, POM 48 | Ultra Quality (77%) |

**Lightweight/Potato** mengutamakan bayangan dekat: 256 texel pada jarak 48 blok, empat perbandingan depth tetangga dengan bobot bilinear untuk tepi yang tajam dan kontinu. Iris dengan separate hardware samplers menjalankannya dalam satu lookup PCF; perangkat lain memakai empat fetch manual. Awan 2D memakai formasi kecil dengan celah lebih lebar, empat oktaf terfilter, dua sampel arah cahaya dan silver lining. Pola, coverage dan anginnya sama dengan atlas cloud shadow 128×128, sehingga terrain menerima bayangan awan tanpa raymarch per pixel. Pencahayaan atmosfer dan auto exposure aktif; metering memakai satu pixel dengan 64 sampel scene. Motion blur mati pada Potato; FXAA tetap aktif. Ambient siang pada jalur awan 2D tanpa GI dinaikkan 12% untuk sky fill dan 25% untuk ground fill, sehingga area teduh lebih terbaca tanpa menghapus shadow. Malam mempertahankan skala ambient asal. Empat lapis gelombang, clarity 2.0 dan caustics aktif memperjelas dasar air dangkal. GI, AO, SSR, bloom dan volumetric light tetap mati. Tidak memakai history TAA; FXAA menjaga tepi layar dengan biaya rendah. FPS belum diukur.

**Extreme** memaksimalkan budget kualitas yang tersedia: SSAO 12 sampel, volumetric light 16 sampel, radius GI 16 blok hingga jarak kamera 96 blok, POM hingga 64 blok, dan awan resolusi penuh dengan history temporal. GI tetap memakai rekonstruksi dan denoiser untuk menjaga stabilitas. Intensitas GI tetap 0.65, warna natural dan kekuatan gelombang 0.65; kualitas maksimal tidak berarti semua intensitas dibuat paling besar. Beban GPU dan memori bertambah; FPS belum diukur.

**FSR 1 aktif secara default di semua preset**, dengan RCAS 1.0 di semua preset. RCAS memakai limiter kontras dan pengurangan noise bawaan; 1.0 adalah kekuatan maksimal pada skala opsi ini. Penajaman mempertegas detail yang sudah ada, bukan memulihkan informasi subpixel yang hilang. Jika detail dedaunan terlihat terlalu keras saat bergerak, ketajaman dapat diturunkan manual ke 0.60. Semua preset memakai Ultra Quality, mode FSR tertinggi yang tersedia: render sekitar 77% dari lebar/tinggi layar, lalu memakai EASU/RCAS. Quality (67%) dan Balanced (59%) tetap bisa dipilih manual untuk mengurangi beban GPU. Mode Native dan ketajaman manual tetap tersedia pada **Performa & FSR**. FSR tidak membuat frame tambahan. Atribusi AMD ada di [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Pilih ulang preset di menu setelah perubahan susunan ini, lalu reload dengan **R**. Memilih preset menerapkan seluruh opsi preset dan mereset tuning custom. Iris yang sedang berjalan dapat menyimpan opsi di memori; ubah FSR atau tuning lain lewat menu untuk sesi aktif. File opsi aktif berada di sebelah folder shaderpack: `../ApaAdanyaShader.txt`. File `presets/*.txt` merupakan ekspor lengkap pilihan yang sama.

## Optimasi Potato untuk M1 — 11 Oktober 2026

Target pengembangan: sekitar 80 FPS pada scene pengguna. Setelah pengguna mengizinkan pengurangan visual ringan, revisi berikutnya memakai shadow map 512 (sebelumnya 1024), tiga wave band air (sebelumnya empat), dan motion blur mati. Jarak shadow 48 blok, filtering shadow 4 sampel, material filter 2×, warna, pencahayaan atmosfer, refraksi dan bentuk awan tetap. FSR sekarang Ultra Quality/77% di semua preset sesuai permintaan pengguna; lebih tajam, dengan beban GPU lebih tinggi dibanding Balanced/59%. Detail shadow dan riak halus berkurang; kamera bergerak tampil lebih tajam. Target 80 FPS **belum terverifikasi**: pengguna melaporkan sekitar 50–60 FPS pada revisi pertama dan tidak ada peningkatan berarti setelah revisi kedua. Pengguna kemudian mengonfirmasi FPS Potato aktif naik setelah revisi budget, tetapi belum memberi angka FPS. FPS setelah perubahan FSR ke Ultra Quality belum diukur. Perbandingan FPS dengan shader OFF masih diperlukan untuk membedakan batas shader/GPU dari batas renderer/CPU.

Revisi berikutnya atas permintaan pengguna menurunkan shadow map lagi dari 512 ke 256 dan meningkatkan air: empat wave band, clarity 2.0, caustics aktif. Filtering PCF dan jarak shadow 48 blok tetap. Caustics mengikuti kedalaman, pencahayaan dan footprint pixel agar detail jauh memudar. Refraksi dan refleksi environment tetap memakai jalur ringan. Detail shadow berkurang, sedangkan air mendapat riak lebih halus dan pola cahaya di dasar. Kombinasi terbaru lolos 720 pasangan compile/link native di Apple M1 dan fixture normal gelombang saat cerah/hujan menghasilkan nilai finite. Ini belum memverifikasi rendering akhir di Iris atau FPS Minecraft; beban/FPS kombinasi terbaru belum diukur.

- Fog dan color grading digabung saat bloom/TAA mati, menghapus satu pass scene dan traffic buffer di antaranya. Urutan efek tetap sama; pembulatan intermediate HDR dapat berbeda sedikit.
- Cache awan 2D memakai setengah lebar/tinggi scene: evaluasi noise dan shading berjalan pada seperempat jumlah pixel sebelum rekonstruksi bilinear premultiplied. Sky, matahari dan bulan tetap dihitung pada resolusi scene. Footprint noise tetap memakai resolusi scene asal; tidak memakai history temporal. Lubang sky yang tidak terwakili cache memakai fallback analitik.
- Awan di luar batas fade 3600 blok langsung dilewati sebelum noise/shading, dengan hasil transparan yang sama.
- Referensi `#ifdef` eksplisit dipertahankan untuk `CLOUD_SHADOWS` dan `TEMPORAL_CLOUDS`: parser opsi Iris tidak mengenali keduanya jika seluruh pemakaian hanya lewat `#if defined(...)`. Ini memperbaiki toggle/menu yang dilaporkan tidak valid di log pengguna. Semua 40 opsi Boolean preset sekarang memiliki referensi directive yang dikenali Iris.
- Filter shadow 4 sampel memakai satu lookup hardware PCF jika Iris menyediakan sampler terpisah. Fallback manual dan jalur PCSS 8 sampel tetap tersedia.

720 pasangan shader dikompilasi/link native pada Apple M1, OpenGL 4.1 Metal: semua pasangan vertex/fragment Potato di tiga dimensi, dengan/tanpa DH dan hardware sampler, serta jalur terkait pada tiga preset lain. Harness mengganti built-in compatibility dengan input tes dan memberi stub helper tekstur DH; ini tidak menguji patcher Iris atau rendering DH sebenarnya. Jalur compute Windows tidak dijalankan. Revisi budget terbaru kembali lolos 720 pasangan compile/link di M1 dan sudah termuat oleh Iris dalam log game tanpa error compile atau peringatan opsi tidak valid. Fixture normal air 4 versus 3 band memberi galat rata-rata encoded RGB sekitar 0.00294 saat cerah dan 0.00450 saat hujan; ini tidak mengukur perubahan warna/refleksi akhir atau FPS.

Fixture GPU membandingkan awan analitik lama/baru (galat maksimum RGB sekitar 6e-8), hardware PCF/manual (maksimum sekitar 0.0031), dan cloud cache pada scene sintetis (galat rata-rata RGB sekitar 0.00095; maksimum 0.0903 di sebagian tepi). Cache dapat membuat tepi awan sedikit lebih lembut. Angka ini **bukan pengukuran FPS Minecraft**. Hasil dan gambar perbandingan tersimpan di `../../.codex-validation/potato-m1/`.

Pilih preset lain lalu **Lightweight/Potato** untuk menerapkan `CLOUD_RECONSTRUCTION=true` pada Iris yang sedang berjalan. Default dan seluruh preset kini memakai FSR Ultra Quality/77%, sehingga opsi FSR yang tidak tercantum di file aktif mengikuti kualitas tertinggi. Ketajaman custom tetap dapat diatur terpisah. Backup sebelum optimasi tersimpan di `../../.codex-backups/potato-m1-20261011-010245/`.

## Pembersihan 11 Oktober 2026

Asap volumetrik custom, penangkap sumber api, obstacle/path cache, compute dan buffer asap, serta AA Smoke Bridge dihapus. Asap kembali memakai partikel Minecraft/resource pack yang aktif. Partikel tetap menerima pencahayaan dan soft intersections. Tidak perlu bridge atau mod asap tambahan.

Dua preset tracing diganti satu Extreme. Scene voxel lokal, DDA voxel, cache cahaya voxel, reservoir/ReSTIR, bounce kedua voxel dan history refleksi stokastik khusus voxel dihapus dari renderer, alokasi GPU dan menu. [Catatan peninjauan tracing](TRACING_REVIEW.md) menjelaskan kontribusi dan batas jalur sebelumnya.

Fitur yang mati di seluruh preset lama dibersihkan: DOF, vignette, chromatic aberration, film grain, penajaman TAA terpisah dan varian color-look. Motion blur ringan, FXAA, TAA, pengaturan warna dasar dan FSR tetap tersedia. POM dipertahankan dan diaktifkan di Extreme. Fixture, benchmark, preview dan generator lama dipindahkan keluar dari shaderpack ke backup instance karena merujuk renderer yang sudah dihapus.

Backup sumber sebelum pembersihan: `../../.codex-backups/renderer-cleanup-20261011/`. Backup mencakup shader, preset, artefak pengembangan, opsi Iris aktif dan bridge asap. Perubahan ini **belum dikompilasi, diuji dalam game atau diukur FPS-nya**, sesuai permintaan pengguna.

## Cahaya pantul dan bayangan

GI mengambil radiansi permukaan opaque sebelum GI/SSR, memvalidasi depth, normal, hemisphere, radius dan batas layar, lalu menambahkannya melalui respons diffuse penerima. Sumber scene merupakan pendekatan radiansi yang sudah dirender, termasuk komponen specular; ini bukan buffer diffuse terpisah atau full path tracing. Emisi memakai pembatas luminansi yang mempertahankan hue.

GI Detailed beradius 8 blok hingga jarak kamera 64 blok. Extreme memperbesar radius dan budget ray. History GI/AO memakai validasi depth/normal dan denoiser variance/a-trous jika compute didukung. Ambient occlusion memengaruhi fraksi ambient; cahaya langsung dan emisi dipertahankan secara pendekatan.

**Fallback Pantulan Shadow-View** memakai permukaan pertama yang terlihat matahari ketika coverage layar kurang. GI dibatasi radius yang sama dan maksimal 24 langkah fallback. Jalur ini 2.5D, memiliki keterbatasan geometri dan tidak dipakai untuk refleksi air. Hi-Z sekarang bernama **Optimasi Hierarki Kedalaman**: mempercepat ray depth, bukan efek pencahayaan tambahan. Perangkat tanpa image/compute opsional tetap memakai jalur screen depth dan smoothing dasarnya.

GI tidak mencakup receiver DH jauh atau seluruh dunia. Refleksi SSR dibatasi geometri yang tersedia di layar; cache langit mengisi coverage yang hilang. Material kasar memakai lobe langit yang lebih lebar. Bayangan matahari memakai alpha cutout dan PCSS/hardware PCF pada preset tinggi.

## Awan dan atmosfer

Cumulus volumetrik memiliki dasar/puncak bervariasi dan ketebalan maksimum 240 blok. Lapisan tengah berada +310 blok dan cirrus +720 blok dari ketinggian dasar. Lapisan atas memakai opacity analitik dan angin yang sama. Cahaya awan memakai 2/4/6 sampel self-shadow dan pendekatan multiple scattering. Bayangan awan berbagi atlas 4096 blok dengan terrain, air dan volumetric light.

Fix pola garis/bintik berlaku di kode semua preset. Efek debu buatan dengan tiga sampel IGN dihapus. Dither awan memakai hash tanpa pola diagonal IGN. Pada budget 12 langkah ke atas, ray cumulus jauh beradaptasi hingga 80 langkah dengan interval target 32 blok; noise subpiksel memudar menuju rata-ratanya. History menerima anchor sampai 22 km dan menangani wrap waktu delapan detik. Cache refleksi delapan langkah tetap memakai budget terpisah.

Detailed/Balanced memakai cache awan setengah lebar/tinggi scene. Extreme memakai ukuran scene penuh dan history yang sama; aktif-region FSR mengikuti ukuran cache. Pencahayaan atmosfer mengubah sky/ground fill menurut waktu, cuaca dan bayangan awan. Tidak ada klaim visual atau FPS baru dari tes sintetis lama.

## Air dan material

**Air Potato** memakai tiga wave band dengan dua harmonik terfilter dan gradien analitik yang lebih sederhana. Riak tetap melengkung dan bersilang; satu lapis riak hujan menggantikan dua. Refleksi langit/awan memakai empat tap cache stabil yang sama dengan air DH, dibanding tujuh tap jalur utama. Refraksi memakai offset normal kecil (maksimal 0.8% tinggi layar), dengan validasi sisi bidang air, depth dan kontinuitas dasar untuk menjaga tepi terrain. Kejernihan 1.5, roughness 0.10, serta absorption dan warna hamburan biru-hijau menjaga dasar dangkal terlihat. SSR dan caustics tetap mati. Jalur ini dipilih otomatis untuk budget hingga empat band tanpa SSR; preset lain mempertahankan jalur utama. Belum ada pengukuran FPS atau tes GPU.

Spektrum air terdiri dari swell silang, wavelet dan riak kapiler hingga tujuh oktaf. Turunan analitik dan filter per harmonik mengurangi aliasing; energi normal yang tidak teresolusi menjadi lebar highlight. Vanilla dan DH memakai spektrum yang sama. Mesh dan simulasi fluida Minecraft mengikuti engine.

Refraksi memvalidasi depth dan memudar di batas geometri. Absorpsi mempertahankan dasar air dangkal dan transmisi biru-hijau di air dalam. Kaustik dibatasi ke dasar yang menghadap atas dan kontinu; buih memakai patch tipis tanpa pita kontur pada dinding. Refleksi air memakai SSR dan cache langit terfilter, dengan pemeriksaan shoreline dan kontak permukaan.

Kaustik memakai gambar grayscale hasil generasi dengan dua lapisan animasi, mirror continuation dan filtering footprint. Asset tidak memerlukan resource pack tambahan; sumber dan prompt ada di [catatan asset](shaders/textures/water-caustics-asset.md). Ini mask artistik, bukan simulasi penuh fokus cahaya.

Filter albedo menjaga texel dekat tetap tajam lalu beralih ke anisotropic bilinear/trilinear pada detail subpiksel. Normal/AO dan specular memakai maksimum dua tap anisotropic; POM menggunakan interpolasi height yang kontinu. Batas sprite per mip mencegah kebocoran atlas.

LabPBR membaca normal/AO/height, smoothness, F0, emisi, porositas dan subsurface. **POM memerlukan height map resource pack**; Extreme tidak menciptakan relief yang tidak ada dalam tekstur. POM menggeser koordinat tekstur tanpa mengubah siluet/geometri blok. Perubahan pada vanilla/Ashen_16x dapat lebih kecil daripada pack dengan data PBR lengkap.

## Struktur

- `shaders/`: renderer, menu, terjemahan, tekstur awan dan asset kaustik.
- `presets/`: empat ekspor yang sesuai profil menu.
- `tools/export_presets.py`: regenerasi ekspor jika deklarasi profil diubah; bukan compiler atau tes GPU.
- `TRACING_REVIEW.md`: peninjauan kode tracing sebelum pembersihan.

Jalankan `python tools/export_presets.py` ketika perlu memperbarui ekspor preset. Fixture pengembangan sebelumnya tersedia di backup dan merujuk renderer sebelumnya; hasilnya tidak membuktikan versi baru ini.
