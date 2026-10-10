# ApaAdanyaShader

Shaderpack untuk Minecraft Java 26.3, Iris 1.11.7 dan Sodium 0.9.2. Renderer memakai GLSL 330 dengan compute GLSL 430 opsional, material LabPBR, pencahayaan langsung, efek screen-space, air, atmosfer dan history temporal. Buffer tambahan memerlukan Iris 1.10.5 atau lebih baru.

Target pemakaian: kualitas visual yang bisa dijangkau beragam kelas GPU melalui profil bertingkat. Pengukuran saat ini memakai Windows dengan RTX 3080 Ti; performa GPU lain belum diukur. Perangkat tanpa optional image/compute tetap memakai jalur GLSL 330.

Optimasi tahap pertama, 8 Oktober: noise awan memakai lattice 3D 512 KiB, Hi-Z dibangun dalam satu pass, akses langit cache voxel dihitung per kolom, dan DDA memakai update sumbu melalui mask vektor. Jumlah sampel/bounce serta profil tidak diturunkan. Pengukuran sebelum/sesudah dan batas klaim FPS: [PERFORMANCE_OPTIMIZATION.md](PERFORMANCE_OPTIMIZATION.md).

Optimasi lanjutan: light shaft direkonstruksi berdasarkan kedalaman setelah air/DH, filter bayangan hardware memakai empat tap bilinear dengan blocker search PCSS tetap, ray contact shadow berhenti setelah jarak kontribusinya habis, dan piksel nyala obor/campfire melewati shading yang hasilnya akan diganti. Hasil dan kompromi gambar: [PERFORMANCE_OPTIMIZATION_ROUND2.md](PERFORMANCE_OPTIMIZATION_ROUND2.md).

## Pemakaian

Asap campfire dan blok api sekarang memiliki switch **Partikel → Sumber Asap**: **Shader (3D)** atau **Minecraft / Resource Pack**. Default shader memakai volume yang naik, terbawa angin dengan riwayat gerak dan membelok di sisi blok penghalang; tidak memerlukan Physics Mod. Resource pack kecil **AA-Volumetric-Smoke-Bridge** harus aktif paling atas untuk mengganti hanya billboard campfire; pack sudah dipasang pada instance ini. Ringan memakai asap Minecraft, empat profil lain memakai shader. Struktur, biaya dan batas verifikasi: [VOLUMETRIC_SMOKE.md](VOLUMETRIC_SMOKE.md).

Pilih **ApaAdanyaShader** di Iris, lalu pilih profil pada Shader Pack Settings. Instance ini memakai tombol **R** untuk reload shader dan **I** untuk membuka pilihan shader. Memilih profil mengatur ulang seluruh opsi sesuai profil; sesuaikan opsi manual setelahnya. Pengaturan custom aktif ada di file `ApaAdanyaShader.txt` di sebelah folder shaderpack.

Pengaturan air mengikuti profil aktif dan opsi custom dalam ApaAdanyaShader.txt. Saat memindahkan shader ke Windows, salin juga file `ApaAdanyaShader.txt` untuk mempertahankan pengaturan tersebut. Gelombang memakai normal prosedural pada mesh fluida; tidak mengubah simulasi atau tinggi geometri air Minecraft. Pantulan air memakai tujuh arah sampel yang tetap di koordinat dunia, tanpa pemaksaan arah ke horizon. Normal puncak gelombang difilter per harmonik, dan air melewati TAA/motion blur yang tidak memiliki gerak pantulan; antialiasing FXAA tetap berlaku. Posisi optik air kini mengikuti depth permukaan yang dirasterisasi, dengan proyeksi DH tersendiri untuk air LOD. Refraksi mengikuti gelombang dengan batas distorsi yang halus, dan refleksi kasar difilter sesuai roughness/FOV. Perubahan serta regresi gerakan kamera: [WATER_STABILITY.md](WATER_STABILITY.md). Air DH kini hanya mengisi piksel di luar coverage vanilla; pemotongan radius 24 blok yang mengikuti kamera dihapus agar kedua mesh air tidak saling menimpa saat bergerak.

Lima profil tersedia dalam menu dan sebagai lima file lengkap di `presets/`. Pilih **Tracing Lokal Performa** untuk mempertahankan tuning gameplay yang sudah dipakai pada instance ini. Setiap profil menuliskan semua opsi sehingga berpindah tingkat tidak meninggalkan fitur mahal dari profil sebelumnya.

| Profil | Resolusi internal | Bayangan | GI / SSR / awan |
| --- | --- | --- | --- |
| Ringan | Native (100%) | 512, PCF 2 | GI/SSR mati, awan 2D |
| Seimbang | Native (100%) | 1024, PCF 4 | GI mati, AO temporal, SSR 16, awan volumetrik 12 |
| Detail | Native (100%) | 2048, hardware PCF/PCSS | GI screen-space 2 ray, SSR 24, awan 12 |
| Tracing Lokal Performa | Native (100%) | 2048, hardware PCF/PCSS | Voxel/reservoir GI 2 ray satu bounce, SSR 24, awan 12 |
| Tracing Lokal Detail | Native (100%) | 2048, hardware PCF/PCSS | Voxel/reservoir GI 3 ray dua bounce, SSR 32, awan 16 |

Semua profil mematikan DOF, motion blur, film grain, vignette, chromatic aberration dan POM secara default. Efek tetap bisa diatur manual. Profil tracing mempertahankan denoiser/history untuk membatasi noise. Ringan mengurangi efek pencahayaan dan geometri bayangan; tingkat lain mempertahankan warna natural, air serta bayangan lembut. Angka FPS bergantung scene dan perangkat.

FSR mati secara default pada kelima profil dan konfigurasi bawaan; rendering memakai resolusi Native (100%). FSR 1 tetap bisa dinyalakan manual di menu Performa untuk mengurangi beban shading, dengan kompromi detail halus. Rendering native dapat menurunkan FPS dibanding preset sebelumnya yang memakai FSR. AO/GI, awan dan light shaft memakai rekonstruksi masing-masing bila aktif. Perangkat tanpa image/compute memakai fallback; tracing lokal hanya tersedia ketika fitur GPU didukung.

Filter bayangan hardware memakai empat tap bilinear dan mempertahankan blocker search PCSS pada setting 8 sampel. Setting 1/2/4/6 serta perangkat tanpa sampler terpisah memakai jalur manual. Warna api/lava dan struktur optimasi sebelumnya tetap dipertahankan. Detail tuning: [PERFORMANCE_PRESET.md](PERFORMANCE_PRESET.md).

## Material dan realisme

Untuk resource pack dengan relief LabPBR seperti ModernArch, aktifkan **Tekstur Timbul (POM)** dan **Normal Map Resource Pack** dari menu **Dunia & Tumbuhan**; aktifkan juga specular PBR untuk karakter material. Kelima profil mematikan POM secara default untuk gameplay ringan. Pengaturan dekat yang hemat: 16 langkah, kedalaman 0.25 dan jarak 16 blok. Memilih profil kembali mereset override ini. POM mengubah tampilan permukaan pada sudut miring, tidak mengubah siluet/geometri blok; bentuk paling mudah diperiksa dekat permukaan batu/bata.

Pembaruan tracing 7 Oktober: Hi-Z konservatif dan denoiser variance/a-trous aktif pada Tinggi ke atas. Ultra, Realistis + Tracing Tinggi dan Sinematik menambahkan voxel lokal 64 kubik, reservoir GI temporal/spatial dan refleksi GGX. Extreme memakai voxel dengan GI penuh tanpa reservoir/denoiser indirect. Perangkat tanpa optional image/compute tetap memakai screen tracing dan LIGHT_SPACE_FALLBACK. Voxel menangkap terrain yang dikirim ke shadow vertex pass sebelum raster/depth test, dengan bentuk blok kasar, radius sekitar 32 blok dan tanpa entity/DH. Warna cahaya matahari/bulan dipisahkan untuk memperbaiki jingga sunset yang berpindah ke bulan. Detail budget, memori dan batas: [RAY_TRACING_AUDIT.md](RAY_TRACING_AUDIT.md).

LabPBR membaca normal/AO/height, smoothness, F0 linear, emisi, porositas dan subsurface. Logam ID 230-237 memakai konstanta optik standar dengan tint albedo; logam lain memakai fallback F0 albedo. Porositas memengaruhi permukaan basah. Model pencahayaan memakai GGX/Smith/Schlick serta diffuse Burley; koreksi normal-variance mengurangi kedipan highlight.

GI memakai respons material linear, sehingga tidak mengalikan warna yang sudah terkena pencahayaan. AO meredupkan fraksi ambient secara pendekatan, menjaga cahaya langsung dan emisi. Refleksi menambah lobe specular, dengan cache langit tersaring untuk permukaan kasar. Exposure mengukur luminansi HDR dan beradaptasi bertahap.

Instance saat refactor memilih resource pack vanilla. Shader tidak dapat menciptakan normal, height atau detail material yang tidak ada. Untuk tekstur timbul dan detail fotoreal, gunakan resource pack LabPBR yang cocok. POM menggeser koordinat tekstur; tidak mengubah siluet atau geometri blok.

Batas arsitektur: renderer dapat menelusuri voxel lokal di luar layar; cakupannya belum seluruh dunia dan bukan hardware RTX/full path tracing. Tidak ada janji FPS maupun persetujuan visual fotoreal dari tes sintetis.

## Upscaling

FSR 1 EASU/RCAS tersedia pada menu Performa & Rekonstruksi. Native memakai dimensi asli; Ultra Quality sekitar 77%, Quality 67%, Balanced 59% dari lebar/tinggi layar. Resolusi rendah mengurangi pekerjaan shading dengan kompromi detail. Geometry, shadow map, sebagian alokasi buffer dan pekerjaan CPU tetap memiliki biaya. RCAS menajamkan hasil setelah upscale; nol mematikannya. FSR ini tidak menghasilkan frame tambahan.

Gunakan **Video Settings → Quality → Texel Interpolation: Nearest** untuk mempertahankan piksel tekstur yang tajam, terutama pada vanilla dan pack 16×. Linear merupakan pilihan tambahan untuk pack resolusi tinggi yang ingin tampilan lebih halus; pengaturan ini juga mengaburkan piksel dekat, sehingga jangan diterapkan secara umum untuk mengatasi kedipan. Mipmap Levels: 4 tetap membantu detail jauh; Texture Filtering: Anisotropic dan Max Anisotropy: 4× dapat dicoba untuk permukaan miring. FSR kini mati secara default. Jika menyalakannya manual, gunakan **Performa & Rekonstruksi → Ketajaman FSR RCAS: 0.20** untuk membatasi penguatan detail kecil. Game yang masih berjalan menyimpan pengaturan di memori, jadi terapkan Texel Interpolation lewat menu untuk sesi aktif. Memilih profil shader kembali mereset ketajaman custom.

## Validasi dan struktur

Jalankan `python -B tools/validate.py --static` untuk konsistensi profil, file preset, terjemahan, entry point dimensi dan directive Iris. Jalankan tanpa `--static` untuk kompilasi/tautan native GPU dan fixture render; `--images-only` menjalankan fixture saja. Tambahkan `--advanced` untuk kompilasi image/compute dan fixture tracing advanced. Tambahkan `--write-previews` untuk menyimpan gambar diagnostik; secara default preview tidak dibuat. Windows/Linux memerlukan GLFW; macOS menggunakan CGL. Pemeriksaan ini tidak menggantikan pemuatan shader dalam Iris.

- `shaders/`: kode renderer, menu dan terjemahan.
- `presets/`: lima preset lengkap yang mengikuti profil menu.
- `tools/`: validator, fixture regresi dan pembuat resource pack efek yang dapat dipakai kembali.
- `artifacts/validation.log`: catatan validasi terakhir yang dipertahankan.
- [VOLUMETRIC_SMOKE.md](VOLUMETRIC_SMOKE.md): arsitektur asap environmental volumetrik 3D dan bridge partikel.
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md): atribusi pihak ketiga.

Preview, cache Python, log uji antara dan catatan pengembangan yang sudah digabung tidak disertakan. Backup pemulihan di `.codex-backups/` pada instance dipertahankan.
