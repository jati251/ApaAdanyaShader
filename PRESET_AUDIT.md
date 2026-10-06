# Profile and Preset Audit - Motion Blur & Depth of Field Update

Audit status untuk seluruh 10 profil/preset setelah pembaruan konfigurasi kamera:
- **Motion Blur & Low Latency Motion Blur (Performance Mode)**: Aktif di **seluruh 10 preset** (Potato s/d Realism-Cinema).
- **Depth of Field (DOF & Half-Res DOF)**: Aktif di **seluruh preset High-End** (High, Ultra, Extreme, Realism, Realism-FSR, Realism-RT, Realism-Cinema).

---

## 1. Tabel Konfigurasi Seluruh Preset

| Profile | Motion Blur | Low Latency MB | Depth of Field | Half-Res DOF | SSR | Water Octaves | GI |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **POTATO** | **True** | **True** | False | False | False | 2 | False |
| **LOW** | **True** | **True** | False | False | False | 3 | False |
| **MEDIUM** | **True** | **True** | False | False | True | 4 | False |
| **HIGH** | **True** | **True** | **True** | **True** | True | 5 | True |
| **ULTRA** | **True** | **True** | **True** | **True** | True | 5 | True |
| **EXTREME** | **True** | **True** | **True** | **True** | True | 7 | True |
| **REALISM** | **True** | **True** | **True** | **True** | True | 5 | True |
| **REALISM_FSR** | **True** | **True** | **True** | **True** | True | 5 | True |
| **REALISM_RT** | **True** | **True** | **True** | **True** | True | 5 | True |
| **REALISM_CINEMA** | **True** | **True** | **True** | **True** | True | 6 | True |

---

## 2. Detail Karakteristik Efek

### Motion Blur (Low Latency / Performance Mode)
- Menggunakan mode 5-sample (`MOTION_BLUR_LOW_LATENCY`) dengan radius *tighter clamp* yang responsif.
- Memiliki latency gate: saat kamera diam atau perpindahan pixel $< 0.0004$, shader langsung melakukan *early exit* dengan **0 texture lookup**.
- Mengabaikan first-person hand agar item di tangan pemain tidak kabur saat bergerak.
- Menggunakan temporal dither Interleaved Gradient Noise (IGN) untuk transisi blur yang mulus tanpa garis-garis banding.

### Depth of Field (High-End Presets)
- Menggunakan **`HALF_RES_DOF`** (rekonstruksi bilateral pada buffer resolusi setengah) sehingga menghemat ~75% beban pemrosesan DoF dibanding native resolution.
- Dilengkapi **`DOF_AUTOFOCUS`** cerdas yang mengunci fokus pada target bidikan crosshair, terintegrasi baik dengan geometri vanilla maupun kedalaman Distant Horizons.

---

## 3. Status Validasi

- Seluruh 10 file preset di `presets/*.txt` telah disinkronkan secara presisi dengan konfigurasi `shaders.properties`.
- Lolos validasi `tools/validate.py --static` dengan status **PASS** (10 complete profiles, legal option values, synchronized exports).
