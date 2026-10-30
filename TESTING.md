# UJI PENERIMAAN / USER ACCEPTANCE TEST (UAT)

> Checklist dijalankan di staging Supabase, bukan di produksi yang sedang digunakan.

| No | Skenario | Hasil yang diharapkan |
|---|---|---|
| 1 | Login pengguna belum aktif | Tidak dapat melihat dashboard/tabel |
| 2 | STORE cabang A membuka data master cabang B dari REST API | Ditolak RLS; katalog transfer hanya expose field terbatas |
| 3 | STORE mencoba langsung ubah qty atau cabang aset melalui REST | Gagal: hak UPDATE kolom tidak diberikan |
| 4 | STORE mengubah role dirinya sendiri | Gagal: hanya ADMIN boleh ubah role |
| 5 | STORE cabang penerima membuat BA transfer dari cabang pengirim | Tercipta BA + transfer MENUNGGU_BA + 3 tahap approval |
| 6 | STORE yang bukan cabang pengirim approve tahap 1 | Ditolak server |
| 7 | STORE pengirim menyetujui tahap 1 | Lanjut tahap GA, tidak bisa langsung kirim |
| 8 | User bukan GA mencoba approval tahap 2 | Ditolak server, kecuali ADMIN override |
| 9 | GA approve tahap 2, FAT approve tahap 3 | BA DISETUJUI, transfer DISETUJUI |
| 10 | Klik Kirim → Terima transfer parsial | Qty asal turun, ID aset baru terbentuk di tujuan; audit tercatat |
| 11 | Tolak BA tahap mana pun | BA dan transfer DITOLAK; stok kembali tersedia |
| 12 | Peminjaman 2 unit dari aset 3 unit, lalu request transfer 2 unit | Ditolak: stok tersedia hanya 1 |
| 13 | Membuat BA Aset Baru oleh GA, penerima ditunjuk | Hanya penerima (atau ADMIN override) dapat setuju |
| 14 | Lihat BA dari menu Transfer | HTML berisi nomor BA, aset, cabang, approval, catatan |
| 15 | Edit kategori menjadi kategori selain ASET/INVENTARIS melalui API | Ditolak CHECK SQL |
| 16 | Unggah foto maintenance JPG/PNG/WebP <5 MB | Tersimpan di bucket privat, tautan sementara dapat dibuka |
| 17 | STORE cabang lain mengakses foto yang bukan cabangnya | Gagal akibat policy Storage + tabel metadata |
| 18 | Tutup tiket maintenance tanpa tindakan dan hasil | Ditolak SQL |
| 19 | Tutup tiket maintenance, isi kondisi akhir | Kondisi master aset di lokasi sama otomatis terbarui |
| 20 | Buka detail master aset yang dimaintenance | History otomatis berisi tiket & biaya pada lokasi sama |
| 21 | SO diajukan dengan salah satu qty kosong | Ditolak |
| 22 | Master berubah setelah snapshot SO | Approval SO ditolak; harus rekonsiliasi ulang |
| 23 | SO turun lebih kecil dari qty dipinjam/transit | Approval ditolak |
| 24 | Export CSV | Excel/Sheets dapat membuka, kolom status kategori sesuai |
| 25 | UI mobile 375px + desktop 1440px | Menu, modal, tabel, halaman login dapat digunakan |

## Pemeriksaan keamanan penting

- Tidak ada `service_role` / `sb_secret_` di repo atau `config.js`.
- Tidak ada policy RLS yang mengizinkan `anon` membaca aset/BA/tiket.
- Pengguna nonaktif tidak lolos `ac_role()`.
- Status persetujuan BA/transfer tidak dapat diubah via update langsung.
- Tanggal, aktor, dan jejak perubahan benar di Audit Log.
- Photo signed URL berlaku singkat dan Storage bucket Private.

## Catatan pengujian build lokal

Aplikasi ini file statis; jalankan server lokal misalnya `python -m http.server 8080`, lalu buka `http://localhost:8080/` (jangan mengandalkan `file://`). Tanpa publishable key, yang terlihat adalah halaman konfigurasi, bukan login/fitur data.
