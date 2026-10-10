# ApaAdanyaShader

Shaderpack untuk Minecraft Java 26.3, Iris 1.11.7 dan Sodium 0.9.2. Mendukung Distant Horizons, material LabPBR, air dengan gelombang terfilter, awan berlapis, bayangan awan dan cahaya pantul lokal. Rendering utama memakai GLSL 330; optimasi depth dan denoiser GI memakai compute opsional.

## Preset

Empat preset menu dan ekspor memiliki pengaturan yang sama:

| Preset | Shadow map / jarak | Awan / sampel cahaya | GI / refleksi | Air / material | FSR default |
|---|---|---|---|---|---|
| Lightweight (Potato) | 1024 / 48 blok, 4 tap | 2D dengan shading + atlas bayangan 128² | GI, AO dan SSR mati | 4 wave band ringan, refraksi tipis, filter 2× | Balanced (59%) |
| Balanced | 1024 / 96 blok | 12 langkah, 2 lapis / 2 | AO temporal, SSR 16 | 4 oktaf, filter 4× | Quality (67%) |
| Detailed | 2048 / 144 blok | 20 langkah, 3 lapis / 4 | GI 2 ray × 24 langkah, SSR 24 | 6 oktaf, filter 4×, LabPBR | Ultra Quality (77%) |
| Extreme | 4096 / 224 blok | 32 langkah, 3 lapis / 6, resolusi penuh | GI 8 ray × 48 langkah, SSR 64 | 7 oktaf, filter 8×, LabPBR, POM 48 | Ultra Quality (77%) |

**Lightweight/Potato** mengutamakan bayangan dekat: 1024 texel pada jarak 48 blok, empat perbandingan depth tetangga dengan bobot bilinear untuk tepi yang tajam dan kontinu. Awan 2D memakai formasi kecil dengan celah lebih lebar, empat oktaf terfilter, dua sampel arah cahaya dan silver lining. Pola, coverage dan anginnya sama dengan atlas cloud shadow 128×128, sehingga terrain menerima bayangan awan tanpa raymarch per pixel. Pencahayaan atmosfer dan auto exposure aktif; metering memakai satu pixel dengan 64 sampel scene. Ambient siang pada jalur awan 2D tanpa GI dinaikkan 12% untuk sky fill dan 25% untuk ground fill, sehingga area teduh lebih terbaca tanpa menghapus shadow. Malam mempertahankan skala ambient asal. GI, AO, SSR, bloom dan volumetric light tetap mati. Tidak memakai history TAA; FXAA menjaga tepi layar dengan biaya rendah. FPS belum diukur.

**Extreme** memaksimalkan budget kualitas yang tersedia: SSAO 12 sampel, volumetric light 16 sampel, radius GI 16 blok hingga jarak kamera 96 blok, POM hingga 64 blok, dan awan resolusi penuh dengan history temporal. GI tetap memakai rekonstruksi dan denoiser untuk menjaga stabilitas. Intensitas GI tetap 0.65, warna natural dan kekuatan gelombang 0.65; kualitas maksimal tidak berarti semua intensitas dibuat paling besar. Beban GPU dan memori bertambah; FPS belum diukur.

**FSR 1 aktif secara default di semua preset**, dengan RCAS 0.20. Lightweight memakai Balanced, Balanced memakai Quality, Detailed/Extreme memakai Ultra Quality. Mode ini merender sekitar 59%, 67% dan 77% dari lebar/tinggi layar, lalu memakai EASU/RCAS. Mode Native dan ketajaman manual tetap tersedia pada **Performa & FSR**. FSR tidak membuat frame tambahan. Atribusi AMD ada di [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Pilih ulang preset di menu setelah perubahan susunan ini, lalu reload dengan **R**. Memilih preset menerapkan seluruh opsi preset dan mereset tuning custom. Iris yang sedang berjalan dapat menyimpan opsi di memori; ubah FSR atau tuning lain lewat menu untuk sesi aktif. File opsi aktif berada di sebelah folder shaderpack: `../ApaAdanyaShader.txt`. File `presets/*.txt` merupakan ekspor lengkap pilihan yang sama.

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

**Air Potato** memakai empat wave band dengan dua harmonik terfilter dan gradien analitik yang lebih sederhana. Riak tetap melengkung dan bersilang; satu lapis riak hujan menggantikan dua. Refleksi langit/awan memakai empat tap cache stabil yang sama dengan air DH, dibanding tujuh tap jalur utama. Refraksi memakai offset normal kecil (maksimal 0.8% tinggi layar), dengan validasi sisi bidang air, depth dan kontinuitas dasar untuk menjaga tepi terrain. Kejernihan 1.5, roughness 0.10, serta absorption dan warna hamburan biru-hijau menjaga dasar dangkal terlihat. SSR dan caustics tetap mati. Jalur ini dipilih otomatis untuk budget hingga empat band tanpa SSR; preset lain mempertahankan jalur utama. Belum ada pengukuran FPS atau tes GPU.

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
