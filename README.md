# ApaAdanyaShader

Shaderpack untuk Minecraft Java 26.3, Iris 1.11.7 dan Sodium 0.9.2. Renderer memakai GLSL 330, material LabPBR, pencahayaan langsung, efek screen-space, air, atmosfer dan history temporal. Buffer tambahan memerlukan Iris 1.10.5 atau lebih baru.

## Pemakaian

Pilih **ApaAdanyaShader** di Iris, lalu pilih profil pada Shader Pack Settings. Instance ini memakai tombol **R** untuk reload shader dan **I** untuk membuka pilihan shader. Memilih profil mengatur ulang seluruh opsi sesuai profil; sesuaikan opsi manual setelahnya. Pengaturan custom aktif ada di file `ApaAdanyaShader.txt` di sebelah folder shaderpack.

Seluruh sepuluh profil tersedia dalam menu dan sebagai file lengkap di `presets/`. File ekspor berisi nilai yang sama persis dengan profil Iris; deskripsi menu tersedia dalam bahasa Indonesia dan Inggris. Untuk penggunaan biasa, pilih Realistis. Pilih varian FSR jika ingin membandingkan resolusi internal lebih rendah.

| Profil | Bayangan | GI / SSR / awan | Exposure / history indirect | Lensa |
| --- | --- | --- | --- | --- |
| Potato | Mati | GI/SSR/awan mati | Mati / mati | Mati |
| Rendah | 512, 2 sampel PCF | GI/SSR mati, awan 2D | Mati / mati | Mati |
| Sedang | 1024, 4 sampel PCF | GI mati, SSR 16, awan 10 | Adaptif / AO temporal | Mati |
| Tinggi | 2048, 6 sampel contact-hardening | GI 3, SSR 28, awan 16 | Adaptif / GI-AO temporal | Mati |
| Ultra | 2048, 8 sampel contact-hardening | GI 5, SSR 40, awan 22 | Adaptif / GI-AO temporal | Mati |
| Extreme | 4096, 8 sampel contact-hardening | GI 6 resolusi penuh, SSR 56, awan 28 | Adaptif / indirect history mati | DOF, motion blur, grain |
| Realistis | 2048, 6 sampel contact-hardening | GI 4, SSR 32, awan 22 | Adaptif / GI-AO temporal | Mati |
| Realistis + FSR | Sama dengan Realistis | Sama, dimensi internal 77% | Adaptif / GI-AO temporal | Mati |
| Realistis + Tracing Tinggi | 2048, 8 sampel contact-hardening | GI 6, SSR 48, awan 24 | Adaptif / GI-AO temporal | Mati |
| Realistis Sinematik | 4096, 8 sampel contact-hardening | GI 5, SSR 48, awan 24 | Adaptif / GI-AO temporal | DOF f/4, motion blur |

Angka GI adalah jumlah sinar; SSR dan awan adalah jumlah langkah. AO/GI memakai setengah lebar/tinggi kecuali Extreme; awan volumetrik memakai rekonstruksi setengah resolusi. History indirect hanya bekerja ketika rekonstruksi cahaya aktif. Extreme memakai AO/GI resolusi penuh, sehingga history indirect sengaja dimatikan. Semua profil yang memakai stabilisasi temporal tetap memakai FXAA karena geometri belum memakai jitter.

Tinggi dan profil di atasnya memakai warna netral, LabPBR/POM dan bayangan kontak. Profil gameplay mematikan DOF, motion blur dan film grain; profil sinematik mengaktifkan efek lensa dengan sengaja. Realistis juga mematikan vignette dan memakai bloom 0.06. Label peta bayangan 4K berarti resolusi shadow map 4096, bukan resolusi layar.

## Material dan realisme

LabPBR membaca normal/AO/height, smoothness, F0 linear, emisi, porositas dan subsurface. Logam ID 230-237 memakai konstanta optik standar dengan tint albedo; logam lain memakai fallback F0 albedo. Porositas memengaruhi permukaan basah. Model pencahayaan memakai GGX/Smith/Schlick serta diffuse Burley; koreksi normal-variance mengurangi kedipan highlight.

GI memakai respons material linear, sehingga tidak mengalikan warna yang sudah terkena pencahayaan. AO meredupkan fraksi ambient secara pendekatan, menjaga cahaya langsung dan emisi. Refleksi menambah lobe specular, dengan cache langit tersaring untuk permukaan kasar. Exposure mengukur luminansi HDR dan beradaptasi bertahap.

Instance saat refactor memilih resource pack vanilla. Shader tidak dapat menciptakan normal, height atau detail material yang tidak ada. Untuk tekstur timbul dan detail fotoreal, gunakan resource pack LabPBR yang cocok. POM menggeser koordinat tekstur; tidak mengubah siluet atau geometri blok.

Fitur dan batas arsitektur dijelaskan di [REALISM.md](REALISM.md). Ini bukan full path tracing, hardware RTX atau renderer geometri dunia di luar layar. Tidak ada janji FPS maupun persetujuan visual fotoreal dari tes sintetis.

## Upscaling

FSR 1 EASU/RCAS tersedia pada menu Performa & Rekonstruksi. Native memakai dimensi asli; Ultra Quality sekitar 77%, Quality 67%, Balanced 59% dari lebar/tinggi layar. Resolusi rendah mengurangi pekerjaan shading dengan kompromi detail. Geometry, shadow map, sebagian alokasi buffer dan pekerjaan CPU tetap memiliki biaya. RCAS menajamkan hasil setelah upscale; nol mematikannya. FSR ini tidak menghasilkan frame tambahan.

## Validasi dan struktur

Jalankan `python -B tools/validate.py --static` untuk konsistensi profil, file preset, terjemahan, entry point dimensi dan directive Iris. Jalankan tanpa `--static` untuk kompilasi/tautan native GPU dan fixture render; `--images-only` menjalankan fixture saja. Tambahkan `--write-previews` untuk menyimpan gambar diagnostik; secara default preview tidak dibuat. Windows/Linux memerlukan GLFW; macOS menggunakan CGL. Pemeriksaan ini tidak menggantikan pemuatan shader dalam Iris.

- `shaders/`: kode renderer, menu dan terjemahan.
- `presets/`: sepuluh preset lengkap yang mengikuti profil menu.
- `tools/`: validator, fixture regresi dan pembuat resource pack efek yang dapat dipakai kembali.
- `artifacts/validation.log`: catatan validasi terakhir yang dipertahankan.
- [VALIDATION.md](VALIDATION.md): hasil dan cakupan pemeriksaan.
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md): atribusi pihak ketiga.

Preview, cache Python, log uji antara dan catatan pengembangan yang sudah digabung tidak disertakan. Backup pemulihan di `.codex-backups/` pada instance dipertahankan.
