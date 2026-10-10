# Peninjauan tracing — 11 Oktober 2026

Kesimpulan dari kode: tracing voxel sebelumnya mempunyai kontribusi render nyata, tetapi tidak membuktikan perubahan visual besar pada scene pengguna. Tidak ada perbandingan render A/B atau benchmark baru; pengguna meminta tes dilewati.

| Jalur sebelumnya | Pemakaian dalam renderer | Batas visual |
|---|---|---|
| Voxel 64³ | Shadow vertex pass merekam occupancy/albedo/emisi; compute membentuk cache cahaya. `traceVoxelWorldRange` melakukan DDA pada sel aktual. | Sekitar ±32 blok, bentuk full-block kasar, hanya terrain yang dikirim ke shadow pass; tanpa entity/DH. |
| GI voxel | `traceSceneIndirect` menambahkan radiansi pada miss screen; reservoir mencari/reuse hit voxel dengan validasi visibility. Bounce kedua hanya pada kandidat reservoir. | Lokal, bergantung kualitas capture dan sumber cahaya aproksimasi. Panorama jauh berada di luar cakupan. |
| Refleksi voxel | Deferred dan air memakai `traceSceneFallback` saat coverage SSR kurang. VNDF/history khusus voxel dipakai di material opaque. | Dapat membantu geometri di luar layar dekat kamera; representasi kasar bukan refleksi mesh seluruh dunia. |
| Bayangan kontak voxel | `shadeMaterial` menelusuri blocker lokal sebelum cahaya langsung ditambahkan. | Receiver dekat dan ray pendek, bukan pengganti shadow map panorama. |
| Hi-Z | `hizAdvance` melewati tile kosong menurut min/max depth. | Optimasi screen-ray, bukan sumber cahaya atau perluasan scene coverage. |

Kode ini aktif di dua preset Local Tracing, sedangkan Detailed tidak mengaktifkan voxel/ReSTIR. Nama tracing tidak berarti hardware RTX atau full-world path tracing. Memori voxel, compute cache, capture shadow dan reservoir menambah pekerjaan; FPS atau besarnya dampak visual tidak diukur dalam review ini.

Sumber sebelum dihapus tersimpan pada `../../.codex-backups/renderer-cleanup-20261011/shaders/`: `program/shadow.vsh`, `program/voxel_light.csh`, `lib/voxel_trace.glsl`, `lib/scene_trace.glsl`, `lib/reservoir.glsl`, `lib/lighting.glsl`, `program/deferred.fsh` dan `program/water.fsh`. Backup juga menyimpan deklarasi profil asli.

Sesuai permintaan pengguna, scene voxel, cache, DDA, ReSTIR dan dua preset Local Tracing dihapus. Extreme memakai kualitas tertinggi pada renderer utama. GI lokal berbasis screen depth, refleksi SSR, shadow-view fallback terbatas, Hi-Z dan denoiser dipertahankan sebagai fitur preset utama. Metode ray pada GI/SSR tetap ada secara matematis; menu/preset tidak lagi memakai tingkat tracing terpisah.
