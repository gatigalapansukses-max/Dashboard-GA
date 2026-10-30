# TIGALAPAN INDONESIA — Asset Control Center

Web app **HTML + CSS + JavaScript** (tanpa Node.js / npm) memakai **Supabase PostgreSQL + Auth + Storage** sebagai backend dan **GitHub Pages** sebagai hosting frontend. Dibuat berdasarkan dua lampiran kode Apps Script dan HTML yang diberikan pengguna. Menu dan proses lama dipertahankan, dengan penyesuaian yang diminta.

**PENTING:** Paket ini **belum terhubung dan belum di-deploy** ke akun Supabase/GitHub Anda. Anda perlu memasukkan **publishable/anon key**, menjalankan SQL, membuat pengguna ADMIN, dan mengunggah folder ini ke repo GitHub. **Jangan pernah memasukkan `service_role` atau secret key ke `config.js`.** Konfigurasi frontend (termasuk publishable key) akan terlihat publik di GitHub Pages; Row Level Security (RLS), bukan kerahasiaan key publik, melindungi data. Gunakan proyek Supabase kosong / cadangkan terlebih dahulu.

## 1 — Struktur folder

```text
index.html                   # aplikasi frontend
config.js                    # URL project + publishable/anon key Supabase
favicon.svg                  # branding 38
css/styles.css               # UI responsif oranye/gelap/putih
js/app.js                    # fungsi UI + Supabase client
supabase/01_schema.sql       # tabel, trigger, RLS, izin, storage private
supabase/02_workflows.sql    # fungsi server (approval BA, transfer, loan, SO)
supabase/03_bootstrap_admin.sql # template aktivasi akun ADMIN pertama
data/                       # arsip 2 sumber Apps Script dan HTML sebelumnya
.nojekyll                    # memastikan GitHub Pages memuat aset statis
```

## 2 — Pasang di Supabase (target proyek Anda)

Proyek yang dicantumkan: **https://toffshikvcruqejszmbs.supabase.co**. URL tersebut hanya alamat API, bukan akses ke Dashboard.

1. Masuk ke [Supabase Dashboard](https://supabase.com/dashboard), pilih project ID `toffshikvcruqejszmbs`.
2. Buka **SQL Editor → New query**. Salin seluruh isi `supabase/01_schema.sql`, klik **Run**. Jika sukses, lanjutkan **New query** untuk seluruh isi `supabase/02_workflows.sql`.
3. Di **Table Editor**, verifikasi tabel dengan awalan `ac_`: `ac_branches`, `ac_profiles`, `ac_assets`, `ac_loans`, `ac_ba`, `ac_ba_approvals`, `ac_transfers`, `ac_maintenance`, `ac_maintenance_photos`, `ac_stock_opnames`, `ac_so_items`, `ac_audit`.
4. Di **Storage**, pastikan bucket **`ac-maintenance`** ada dan **Private**. Batas foto 5 MB/file, hanya JPEG/PNG/WebP. File dan metadata hanya bisa diakses akun yang memiliki akses lokasi sesuai RLS.
5. Di **Authentication → Users → Add user**, buat pengguna administrator dengan email asli dan password kuat; bila tombol tersedia, pilih email terkonfirmasi (confirmed). Proses membuat user mengisi `ac_profiles` otomatis dengan `active=false`.
6. Edit `supabase/03_bootstrap_admin.sql`: ganti teks `GANTI_EMAIL_ADMIN@PERUSAHAAN.COM` menjadi alamat email admin tersebut. Jalankan di SQL Editor. **Jangan menjalankan file sebelum mengganti placeholder.**
7. Buat lokasi/cabang setelah login pertama melalui menu **Lokasi / Cabang**. Kemudian masuk ke **Pengguna**, buat akun staf terlebih dahulu di Authentication, dan tetapkan role, cabang, status Aktif. Role yang tersedia: `ADMIN`, `GA`, `FAT`, `STORE`, `AUDITOR`.
8. Di **Project Settings → API Keys**, ambil **publishable key** (`sb_publishable_...`) atau **legacy anon key**. Bukan secret key, bukan `service_role`.
9. Edit `config.js`. URL proyek sudah terisi, ganti hanya string `ISI_PUBLISHABLE_ATAU_ANON_KEY_SUPABASE` dengan key publik tersebut.
10. Di **Authentication → URL Configuration**: untuk hosting Pages, atur **Site URL** ke `https://USERNAME.github.io/NAMA-REPO/` dan tambahkan ke redirect allow list jika Anda menggunakan tautan login/verifikasi email.

Contoh `config.js`:

```js
window.ASSET_CONFIG = {
  supabaseUrl: 'https://toffshikvcruqejszmbs.supabase.co',
  supabaseAnonKey: 'sb_publishable_xxxxxxxxx'
};
```

**Tidak ada password yang ditanam pada frontend.** Akun menggunakan Supabase Authentication via email/password. Pastikan pengaturan pendaftaran publik (sign-up) sesuai kebijakan perusahaan; standar operasional ini memakai akun yang ditambahkan Admin melalui Dashboard Auth, bukan registrasi bebas di frontend.

## 3 — Deploy di GitHub Pages tanpa install npm

1. Buat repositori GitHub, misalnya **`tigalapan-asset`**. Gunakan repositori yang boleh dipublikasikan sebagai frontend, karena source code GitHub Pages dapat diakses publik.
2. Unggah **semua isi folder** proyek ini ke **root repository**, sehingga `index.html` ada di root, bukan di dalam subfolder ZIP. Gunakan **Add file → Upload files** dan **Commit changes**, atau upload dengan Git client / GitHub Desktop.
3. Buka repo **Settings → Pages**. Di **Build and deployment → Source**, pilih **Deploy from a branch**, branch **`main`**, folder **`/(root)`**, lalu **Save**.
4. Setelah GitHub selesai menerbitkan, buka **`https://USERNAME.github.io/tigalapan-asset/`**. Halaman login akan tampil jika `config.js` benar dan scripts SQL sudah dijalankan.
5. Jika muncul halaman "Aktivasi Koneksi Supabase", berarti key publik masih placeholder; perbaiki `config.js`, commit ulang, lalu refresh GitHub Pages.
6. Jika halaman login tampil tetapi login gagal, periksa akun di Authentication → Users, status di `ac_profiles`, email/password dan RLS. Jangan menyelesaikannya dengan mematikan RLS.

Karena ini aplikasi statis biasa, **tidak perlu Build, npm, Node.js, Vite, GitHub Actions, ataupun server GitHub yang selalu aktif**. GitHub Pages hanya melayani file; seluruh data bisnis dan autentikasi ditangani oleh Supabase. Untuk akses intranet, sebaiknya pertimbangkan domain perusahaan dan kontrol akses tambahan.

## 4 — Alur kerja utama

| Fitur | Siapa / aturan |
|---|---|
| Dashboard | Semua KPI berupa tombol yang membuka data; filter cabang, status, kategori, kondisi. Ada indikator jumlah unit Terpakai/Tidak Terpakai. |
| Master Aset | GA/ADMIN tambah, edit; kategori tunggal `ASET` atau `INVENTARIS`. Aset berisi kondisi fisik serta status penggunaan berbeda. |
| History Maintenance | Tampil otomatis dalam detail dan edit master aset dari tiket Maintenance berdasarkan **ID aset + cabang saat laporan**. |
| Peminjaman | STORE/GA/ADMIN membuat/mengembalikan, kuantitas diperiksa server terhadap peminjaman dan transfer lain. |
| BA Aset Baru | GA/ADMIN membuat BA dengan aset yang sudah terdaftar → user penerima ditunjuk secara spesifik dan menyetujui. |
| BA Transfer | User cabang penerima membuat BA → **STORE cabang pengirim (approval 1)** → **GA (approval 2)** → **FAT (approval 3)**. ADMIN dapat bertindak sebagai *override* darurat; setiap aksi terlacak. |
| Transfer | Setelah 3 approval BA: cabang pengirim klik **Kirim** → cabang penerima klik **Terima** → server otomatis mengurangi qty sumber dan membuat ID aset turunan di tujuan. |
| BA Lainnya | GA/ADMIN membuat BA terkait aset atau hal lain, memilih user pengesah → user approve. |
| BA HTML | Menu Buat BA atau Transfer → **Lihat BA** → **Cetak / View HTML**, browser dapat Print / Save as PDF. Bukan signature tersertifikasi. |
| Maintenance | Tipe: perbaikan, preventif, inspeksi, penggantian, instalasi, lainnya. Prioritas, dampak, PIC, vendor, estimasi/realisasi biaya, target, tindakan, hasil dan foto. GA/ADMIN menutup. |
| Foto Maintenance | Bisa unggah 1–5 foto setiap unggahan, tersimpan di bucket privat; saat dibuka dihasilkan signed URL 120 detik. |
| Stock Opname | STORE/GA memulai dan mengisi SO → ajukan → GA/ADMIN approve → server cocokkan qty dengan master dan komitmen yang masih terbuka. |
| Pengguna | ADMIN mengatur role/cabang/aktif untuk profil yang sudah dibuat di Supabase Auth. |
| Audit Log | Trigger database mencatat perubahan tabel-tabel utama dengan waktu dan aktor (khusus role global). |
| Validasi Kondisi | **Dihapus**, perubahan kondisi fisik melalui edit master aset, Stock Opname, atau penyelesaian Maintenance. |

### Status dan ketentuan

- Status master aset hanya `TERPAKAI` atau `TIDAK TERPAKAI`.
- Kondisi tetap `BAGUS`, `LAYAK PAKAI`, `TIDAK LAYAK PAKAI`, `RUSAK`, atau `BELUM DIPERIKSA`.
- Kategori hanya `ASET` atau `INVENTARIS`, bisa diubah melalui form. Kategori bukan subkategori perabotan/elektronik lagi.
- Kolom `registration_no` disediakan untuk nomor register dari FAT; aplikasi tidak membuat nomor FAT otomatis. Prinsip inventaris tanpa nomor registrasi FAT bisa diikuti pada saat input.
- Aset per jenis/lokasi dapat memiliki QTY >1. Saat transfer parsial, server membuat baris/ID baru di cabang penerima, dan mengurangi kuantitas asal; ini adalah *batch tracking*, belum pelacakan serial per unit.
- Foto terkait maintenance disimpan privat; `photo_url` aset pada master hanya tautan HTTPS manual (bukan Storage privat).
- Tidak ada master nomor registrasi otomatis dari FAT; validasi kebijakan batas aset oleh pengguna, bukan penghitungan otomatis di backend.

## 5 — Migrasi data lama dari Apps Script / Excel

**Tidak dilakukan otomatis**, karena lampiran yang tersedia hanya kode Apps Script + HTML, bukan tabel master aset Excel/Sheet yang menjadi sumber data. Lakukan sebagai berikut:

1. Di app baru, buat seluruh cabang yang digunakan dalam data lama. Pastikan penulisannya konsisten.
2. Di Master Aset klik **Import CSV**, unduh template.
3. Siapkan CSV berkolom `name`, `brand`, `qty`, `category`, `condition`, `status`, `branch`, `position`, `owner_name`, `registration_no`, `serial_no`, `notes`.
4. Impor maksimal 3.000 baris per file. Kategori lama yang diawali kata `ASET` menjadi ASET; selain itu INVENTARIS. Status `TIDAK AKTIF`, `PERBAIKAN`, `PERLU VERIFIKASI`, `DIPINDAHKAN`, `NONAKTIF` menjadi `TIDAK TERPAKAI`; selain itu `TERPAKAI`. Lakukan pemeriksaan klasifikasi setelah import.
5. Import **menambah** data baru dan **tidak** menimpa data lama; **jangan import dua kali**. Jika proses sebagian gagal, periksa data yang sudah tercatat sebelum mencoba ulang. Data maintenance dan riwayat transfer lama tidak ikut diimpor oleh fitur ini.

## 6 — Pemeriksaan sebelum Go-Live

Lihat `TESTING.md`. Pengujian wajib mencakup login, izin RLS, pembatasan cabang, status, approval 1/2/3, penolakan, transfer parsial, stok pinjaman, penutupan maintenance, foto private, rekonsiliasi SO, serta akses user nonaktif.

## 7 — Troubleshooting singkat

- **Login “Invalid login credentials”**: email/password salah, user belum ada, atau email belum confirmed di Auth.
- **Login masuk tetapi “Akun belum diaktifkan”**: jalankan aktivasi profil user; untuk STORE, isi branch terlebih dahulu.
- **`relation ac_assets does not exist`**: `01_schema.sql` belum berhasil dijalankan.
- **`function ac_create_ba does not exist`**: `02_workflows.sql` belum dijalankan atau ada SQL error.
- **`permission denied / row-level security`**: role/cabang tidak memiliki izin; jangan mematikan RLS sebagai workaround.
- **Foto gagal upload**: periksa bucket `ac-maintenance`, tipe MIME, size <5MB, user aktif dan aset berada di cabang berizin.
- **BA stuck**: periksa akun aktif role STORE cabang pengirim, GA, dan FAT. ADMIN dapat menggantikan approver sebagai override yang terekam.
- **Github Pages 404 / blank**: pastikan `index.html` di root, `config.js` tersedia, URL repo benar, dan script dari CDN jsDelivr bisa diakses browser.

## 8 — Batasan penyelesaian

Kode telah disiapkan untuk deployment tetapi belum dieksekusi pada database Supabase asli, karena kredensial/izin dashboard proyek belum tersedia. Oleh sebab itu implementasi harus diuji pada project staging atau dicadangkan sebelum menjadi sumber data produksi. SQL menghindari nama tabel lama dengan prefix `ac_`, namun `01_schema.sql` membuat trigger pada `auth.users` dan bucket storage baru. Jika Anda memiliki trigger auth yang kustom, tinjau dampaknya terlebih dahulu.

### Rujukan teknis

- [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase Database Functions](https://supabase.com/docs/guides/database/functions)
- [Supabase Storage Private Buckets](https://supabase.com/docs/guides/storage/buckets/fundamentals)
- [GitHub Pages source](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)

## 9 — Pratinjau tampilan

Folder `preview/` berisi screenshot tampilan dashboard desktop, dashboard mobile, dan detail master aset. **Gambar tersebut memakai data contoh buatan untuk uji UI, bukan data aktual perusahaan** dan tidak membuktikan koneksi Supabase aktif.
