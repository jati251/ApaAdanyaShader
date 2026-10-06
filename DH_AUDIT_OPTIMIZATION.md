# DH audit â€” implementasi 6 Oktober 2026

Audit ini sudah diterjemahkan menjadi perubahan kode. Dokumen usulan awal disimpan bersama snapshot sumber sebelum perubahan di `.codex-backups/dh-audit-20261006/` pada instance. Angka FPS dan klaim visual identik dalam usulan awal merupakan estimasi tanpa pengukuran; tidak digunakan sebagai hasil validasi.

## Perubahan yang diterapkan

- **Air DH:** filter environment tujuh arah menjadi empat arah tetrahedral tetap di ruang dunia. Rata-rata offset nol dan momen kedua sesuai cone sebelumnya. Ini mengurangi pemanggilan environment tujuh menjadi empat, atau pembacaan cache langit empat belas menjadi delapan per fragmen reflektif. Fresnel, penghalangan facet, roughness, penyerapan dan normal gelombang tetap digunakan. Hasil filter merupakan pendekatan baru, bukan gambar yang identik. Satu sampel tajam dari usulan tidak dipakai karena jarak LOD saja tidak membuktikan bahwa cone menjadi sub-texel; cache langit dapat memuat batas awan dan kontras tinggi.
- **Terrain DH:** spesialisasi `AA_DH_TERRAIN` pada shading bersama meniadakan lampu tangan; semua fragmen DH sudah ditolak dalam radius 24 blok, di luar jangkauan lampu 15 blok. Roughness matte 0.78 tidak lagi menghitung derivatif normal. Burley diffuse beralih halus menjadi Lambert pada 96â€“128 blok. Specular matahari berkurang halus pada 64â€“128 blok dan dilewati setelahnya. Warna ambient, lampu blok, petir, logika dimensi, bayangan peta, faktor skylight dan bayangan awan menggunakan jalur bersama. Near LOD mempertahankan Burley/GGX dasar; hilangnya specular AA dan lobus specular jauh adalah kompromi visual yang disengaja.
- **Penelusuran depth:** ukuran aktif depth vanilla dan DH masing-masing dihitung sebelum loop ray/refinement/contact shadow. Ukuran vanilla tidak diteruskan sebagai ukuran DH. `projectedViewDepth` menghitung hanya baris z/w dari matriks invers; suku x/y tetap ada untuk proyeksi asimetris atau oblique. Tidak diasumsikan bahwa matriks selalu memiliki suku tersebut nol.
- **DOF:** depth DH memakai helper z/w yang sama. TAA dan motion blur tetap merekonstruksi posisi lengkap karena reproyeksi membutuhkan xyz. Pass terpisah tidak digabung hanya untuk mengurangi pembacaan depth; masing-masing memiliki kebutuhan dan waktu rendering sendiri.
- **Ketebalan air DH:** rekonstruksi xyz dasar air menjadi selisih z dikalikan panjang ray kamera. Ini mempertahankan panjang lintasan untuk permukaan dan dasar yang berbagi ray perspektif. Clamp 80 blok tetap dipertahankan. Tidak digunakan asumsi bahwa semua kanal sudah opak pada 15 blok: transmisi hijau bergantung pada WATER_CLARITY. Di bawah air transmisi unity melewati pembacaan dasar; facet dengan Fresnel penuh melewati seluruh body/background yang kontribusinya nol.

Vanilla water mempertahankan filter tujuh arah. Profil, pilihan efek lensa dan konfigurasi aktif tidak diubah oleh patch DH ini. Refleksi SSR/SSGI DH tetap memakai proyeksi sendiri; aturan live depth sebelum translucency dan opaque copy sebelum water dipertahankan.

## Pemeriksaan

`python -B tools/validate.py --dh-benchmark` menjalankan kompilasi/tautan seluruh pipeline, semua profil, tiga dimensi, DH aktif/mati, serta fixture GPU lama dan fixture DH baru. Rekaman khusus patch disimpan di `artifacts/dh-validation.log`.

Fixture DH baru memeriksa z/w terhadap perkalian matriks penuh termasuk suku asimetris, sampler DH dengan ukuran berbeda dari vanilla, panjang lintasan air terhadap rekonstruksi xyz, near shading, pengabaian lampu tangan, transisi 64/96/128 blok, nilai finite, konservasi energi cache konstan dan filtering langit berkontras tinggi.

Pengukuran opsional memakai timer GPU native, 960Ã—540, pemanasan 16 draw lalu 100 draw per varian. Dua fixture mengisolasi shading terrain jauh dan filter environment air. Bayangan dinonaktifkan dan geometri/cache dikontrol, sehingga hasil ini tidak mewakili seluruh pass DH, alokasi Iris, CPU chunk loading atau FPS gameplay. Sumber pembanding berasal dari snapshot sebelum patch.

Fixture GPU awal lolos untuk proyeksi z/w, buffer DH berukuran berbeda, ketebalan air, near shading, transisi LOD dan filter environment empat arah. Setelah itu pengguna meminta "skip test"; proses validasi penuh/benchmark dihentikan. Varian lengkap, fixture tambahan FSR dan timer GPU patch ini belum dinyatakan lulus. Reload Minecraft dan pemeriksaan transisi LOD, cuaca, shoreline, pergerakan kamera serta frame time dalam scene sebenarnya masih diperlukan untuk signoff visual dan gameplay.
