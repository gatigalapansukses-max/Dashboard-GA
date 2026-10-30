-- Jalankan setelah 01_schema.sql.
begin;

-- Ketersediaan di luar stok yang telah dikomit untuk pinjam / mutasi.
create or replace function public.ac_available(p_asset uuid) returns integer
language sql stable security definer set search_path = '' as $$
 select greatest(0,a.qty -
  coalesce((select sum(l.qty) from public.ac_loans l where l.asset_id=a.id and l.status='DIPINJAM'),0) -
  coalesce((select sum(t.qty) from public.ac_transfers t where t.asset_id=a.id and t.status in ('MENUNGGU_BA','DISETUJUI','DALAM_PENGIRIMAN')),0))::integer
 from public.ac_assets a where a.id=p_asset and public.ac_can_view(a.branch_id)
$$;

-- Katalog terbatas untuk STORE yang ingin meminta transfer dari toko lain.
create or replace function public.ac_transfer_catalog()
returns table(id uuid,asset_code text,name text,branch_id uuid,qty integer,available integer,category text,status text)
language plpgsql stable security definer set search_path = '' as $$
begin
 if not coalesce(public.ac_role() in ('ADMIN','GA','STORE'),false) then raise exception 'Tidak berwenang'; end if;
 return query select a.id,a.asset_code,a.name,a.branch_id,a.qty,
  greatest(0,a.qty-coalesce((select sum(l.qty) from public.ac_loans l where l.asset_id=a.id and l.status='DIPINJAM'),0)
   -coalesce((select sum(t.qty) from public.ac_transfers t where t.asset_id=a.id and t.status in ('MENUNGGU_BA','DISETUJUI','DALAM_PENGIRIMAN')),0))::integer,
   a.category,a.status from public.ac_assets a where a.qty>0 and a.status='TERPAKAI';
end;$$;

create or replace function public.ac_create_loan(p_asset uuid,p_qty integer,p_borrower text,p_start date,p_due date,p_notes text default '')
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_asset public.ac_assets%rowtype; v_id uuid;
begin
 if not coalesce(public.ac_role() in ('STORE','GA','ADMIN'),false) then raise exception 'Tidak berwenang'; end if;
 select * into v_asset from public.ac_assets where id=p_asset for update;
 if not found or not public.ac_can_view(v_asset.branch_id) then raise exception 'Aset/lokasi tidak ditemukan'; end if;
 if v_asset.status<>'TERPAKAI' or p_qty is null or p_qty<=0 or p_qty>coalesce(public.ac_available(p_asset),0)
 then raise exception 'Jumlah tersedia tidak cukup atau aset tidak terpakai'; end if;
 if nullif(trim(p_borrower),'') is null or p_start is null or p_due<p_start or p_due is null then raise exception 'Form peminjaman tidak valid'; end if;
 insert into public.ac_loans(asset_id,branch_id,qty,borrower,borrow_date,due_date,notes,created_by)
 values(p_asset,v_asset.branch_id,p_qty,trim(p_borrower),p_start,p_due,coalesce(p_notes,''),auth.uid()) returning id into v_id;
 return v_id;
end;$$;
create or replace function public.ac_return_loan(p_id uuid,p_note text default '') returns void
language plpgsql security definer set search_path = '' as $$
declare r public.ac_loans%rowtype;
begin
 if not coalesce(public.ac_role() in ('STORE','GA','ADMIN'),false) then raise exception 'Tidak berwenang'; end if;
 select * into r from public.ac_loans where id=p_id for update;
 if not found or not public.ac_can_view(r.branch_id) or r.status <> 'DIPINJAM' then raise exception 'Peminjaman tidak dapat dikembalikan'; end if;
 update public.ac_loans set status='DIKEMBALIKAN',return_date=current_date,notes=concat_ws(' | ',nullif(notes,''),nullif(p_note,'')) where id=p_id;
end;$$;

-- BA langsung terbentuk dalam status MENUNGGU dan satu permohonan transfer terkait.
create or replace function public.ac_create_ba(p_type text,p_title text,p_description text,
 p_asset uuid,p_qty integer,p_to_branch uuid default null,p_recipient uuid default null,p_other jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_asset public.ac_assets%rowtype; v_id uuid; v_role text; v_recipient public.ac_profiles%rowtype;
begin
 v_role=public.ac_role();
 if v_role is null then raise exception 'Akun belum aktif'; end if;
 if p_type not in ('ASET_BARU','TRANSFER','LAINNYA') then raise exception 'Jenis BA tidak valid'; end if;
 if nullif(trim(p_title),'') is null or p_qty is null or p_qty<1 then raise exception 'Judul dan qty wajib'; end if;
 if p_type in ('ASET_BARU','LAINNYA') and v_role not in ('GA','ADMIN') then raise exception 'BA ini hanya dapat dibuat GA'; end if;
 if p_asset is not null then
  select * into v_asset from public.ac_assets where id=p_asset for update;
  if not found or (p_type <> 'TRANSFER' and not public.ac_can_view(v_asset.branch_id)) then raise exception 'Aset tidak ditemukan/tidak berwenang'; end if;
 end if;
 if p_type in ('ASET_BARU','TRANSFER') and p_asset is null then raise exception 'Pilih aset'; end if;
 if p_type='ASET_BARU' and p_qty>v_asset.qty then raise exception 'Qty BA melebihi qty master'; end if;
 if p_type='TRANSFER' then
  if v_role not in ('STORE','GA','ADMIN') then raise exception 'Tidak berwenang membuat permohonan transfer'; end if;
  if p_to_branch is null or p_to_branch=v_asset.branch_id or not exists(select 1 from public.ac_branches where id=p_to_branch and active) then raise exception 'Lokasi tujuan salah'; end if;
  if v_role='STORE' and p_to_branch<>public.ac_branch() then raise exception 'Permohonan transfer harus dibuat user lokasi penerima'; end if;
  if v_asset.status<>'TERPAKAI' or p_qty > (v_asset.qty - coalesce((select sum(qty) from public.ac_loans where asset_id=p_asset and status='DIPINJAM'),0) - coalesce((select sum(qty) from public.ac_transfers where asset_id=p_asset and status in ('MENUNGGU_BA','DISETUJUI','DALAM_PENGIRIMAN')),0)) then raise exception 'Qty tidak cukup / status aset tidak terpakai'; end if;
 else
  if p_recipient is null then raise exception 'User penerima/pengesah BA wajib dipilih'; end if;
  select * into v_recipient from public.ac_profiles where id=p_recipient and active=true;
  if not found then raise exception 'Penerima tidak aktif atau tidak terdaftar'; end if;
  if p_type='ASET_BARU' and (v_asset.branch_id is distinct from v_recipient.branch_id)
   and v_recipient.role='STORE' then raise exception 'Penerima aset baru harus berada di lokasi aset'; end if;
 end if;
 insert into public.ac_ba(ba_type,title,description,asset_id,qty,from_branch_id,to_branch_id,recipient_id,created_by,other_details)
 values(p_type,trim(p_title),coalesce(p_description,''),p_asset,p_qty,
  case when p_type='TRANSFER' then v_asset.branch_id else null end,
  case when p_type='TRANSFER' then p_to_branch else null end,p_recipient,auth.uid(),coalesce(p_other,'{}'::jsonb)) returning id into v_id;
 if p_type='TRANSFER' then
  insert into public.ac_ba_approvals(ba_id,step_no,label,role_required,branch_id)
  values(v_id,1,'Toko pengirim','STORE',v_asset.branch_id),
        (v_id,2,'General Affairs','GA',null),
        (v_id,3,'Finance & Accounting','FAT',null);
  insert into public.ac_transfers(ba_id,asset_id,from_branch_id,to_branch_id,qty,notes,requested_by)
  values(v_id,p_asset,v_asset.branch_id,p_to_branch,p_qty,coalesce(p_description,''),auth.uid());
 else
  insert into public.ac_ba_approvals(ba_id,step_no,label,role_required,user_id)
  values(v_id,1,'Penerima / pihak terkait','USER',p_recipient);
 end if;
 return v_id;
end;$$;

create or replace function public.ac_decide_ba(p_ba uuid,p_approve boolean,p_note text default '')
returns text language plpgsql security definer set search_path = '' as $$
declare b public.ac_ba%rowtype; a public.ac_ba_approvals%rowtype; v_role text; v_pending integer;
begin
 v_role=public.ac_role(); if v_role is null then raise exception 'Akun tidak aktif'; end if;
 select * into b from public.ac_ba where id=p_ba for update;
 if not found or b.status<>'MENUNGGU' then raise exception 'BA tidak sedang menunggu approval'; end if;
 select * into a from public.ac_ba_approvals where ba_id=p_ba and decision='MENUNGGU' order by step_no limit 1 for update;
 if not found then raise exception 'Tahapan tidak ditemukan'; end if;
 if not (
  (a.role_required='USER' and a.user_id=auth.uid()) or
  (a.role_required='STORE' and v_role='STORE' and a.branch_id=public.ac_branch()) or
  (a.role_required in ('GA','FAT') and v_role=a.role_required) or
  (v_role='ADMIN')
 ) then raise exception 'Approval tahap % memerlukan % / pengguna yang ditugaskan',a.step_no,a.label; end if;
 update public.ac_ba_approvals set decision=case when p_approve then 'DISETUJUI' else 'DITOLAK' end,
  decided_by=auth.uid(),decided_at=now(),note=coalesce(p_note,'') where id=a.id;
 if not p_approve then
  update public.ac_ba set status='DITOLAK',finished_at=now() where id=b.id;
  update public.ac_transfers set status='DITOLAK' where ba_id=b.id;
  return 'DITOLAK';
 end if;
 select count(*) into v_pending from public.ac_ba_approvals where ba_id=p_ba and decision='MENUNGGU';
 if v_pending=0 then
  update public.ac_ba set status='DISETUJUI',finished_at=now() where id=b.id;
  update public.ac_transfers set status='DISETUJUI' where ba_id=b.id;
  return 'DISETUJUI';
 end if;
 return 'MENUNGGU';
end;$$;

create or replace function public.ac_advance_transfer(p_transfer uuid,p_action text)
returns text language plpgsql security definer set search_path = '' as $$
declare t public.ac_transfers%rowtype; a public.ac_assets%rowtype; v_new uuid; v_role text;
begin
 v_role=public.ac_role(); if not coalesce(v_role in ('ADMIN','GA','STORE'),false) then raise exception 'Akses ditolak'; end if;
 select * into t from public.ac_transfers where id=p_transfer for update;
 if not found then raise exception 'Transfer tidak ditemukan'; end if;
 if p_action='CANCEL' then
  if t.status<>'MENUNGGU_BA' or not (t.requested_by=auth.uid() or public.ac_manager()) then raise exception 'Tidak dapat dibatalkan'; end if;
  update public.ac_transfers set status='DIBATALKAN' where id=t.id;
  update public.ac_ba set status='DIBATALKAN',finished_at=now() where id=t.ba_id;
 elsif p_action='SHIP' then
  if t.status<>'DISETUJUI' or not (public.ac_manager() or (v_role='STORE' and public.ac_branch()=t.from_branch_id)) then raise exception 'Belum disetujui atau bukan toko pengirim'; end if;
  update public.ac_transfers set status='DALAM_PENGIRIMAN',shipped_by=auth.uid(),shipped_at=now() where id=t.id;
 elsif p_action='RECEIVE' then
  if t.status<>'DALAM_PENGIRIMAN' or not (public.ac_manager() or (v_role='STORE' and public.ac_branch()=t.to_branch_id)) then raise exception 'Transfer belum dikirim / bukan toko penerima'; end if;
  select * into a from public.ac_assets where id=t.asset_id for update;
  if not found or a.branch_id<>t.from_branch_id or a.qty<t.qty then raise exception 'Jumlah/lokasi asal tidak valid'; end if;
  if (a.qty-t.qty) < (
   coalesce((select sum(qty) from public.ac_loans where asset_id=a.id and status='DIPINJAM'),0)
   +coalesce((select sum(qty) from public.ac_transfers where asset_id=a.id and id<>t.id and status in ('MENUNGGU_BA','DISETUJUI','DALAM_PENGIRIMAN')),0)) then
   raise exception 'Qty sumber dibutuhkan untuk peminjaman/transfer lain'; end if;
  update public.ac_assets set qty=qty-t.qty,status=case when qty=t.qty then 'TIDAK TERPAKAI' else status end where id=a.id;
  insert into public.ac_assets(name,brand,qty,category,condition,status,branch_id,position,owner_name,notes,
    purchase_date,purchase_price,registration_no,serial_no,photo_url,source,origin_asset_id,created_by)
  values(a.name,a.brand,t.qty,a.category,a.condition,'TERPAKAI',t.to_branch_id,'','',a.notes,
    a.purchase_date,a.purchase_price,a.registration_no,a.serial_no,a.photo_url,'TRANSFER '||t.id,
    coalesce(a.origin_asset_id,a.id),auth.uid()) returning id into v_new;
  update public.ac_transfers set status='DITERIMA',received_by=auth.uid(),received_at=now(),destination_asset_id=v_new where id=t.id;
 else raise exception 'Aksi transfer tidak dikenal'; end if;
 return p_action;
end;$$;

create or replace function public.ac_start_so(p_branch uuid,p_notes text default '') returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_so uuid; v_n integer;
begin
 if not coalesce(public.ac_role() in ('ADMIN','GA','STORE'),false) or not public.ac_can_view(p_branch) then raise exception 'Tidak berwenang'; end if;
 if exists(select 1 from public.ac_stock_opnames where branch_id=p_branch and status in ('DRAFT','DIAJUKAN')) then raise exception 'Masih ada SO yang belum selesai'; end if;
 select count(*) into v_n from public.ac_assets where branch_id=p_branch and qty>0;
 if v_n=0 then raise exception 'Belum ada aset dengan qty di lokasi ini'; end if;
 insert into public.ac_stock_opnames(branch_id,notes,created_by) values(p_branch,coalesce(p_notes,''),auth.uid()) returning id into v_so;
 insert into public.ac_so_items(so_id,asset_id,qty_system,condition)
 select v_so,id,qty,condition from public.ac_assets where branch_id=p_branch and qty>0;
 return v_so;
end;$$;
create or replace function public.ac_save_so_line(p_id uuid,p_qty integer,p_condition text,p_notes text default '') returns void
language plpgsql security definer set search_path = '' as $$
declare v_branch uuid; v_status text;
begin
 if not coalesce(public.ac_role() in ('ADMIN','GA','STORE'),false) then raise exception 'Tidak berwenang'; end if;
 select s.branch_id,s.status into v_branch,v_status from public.ac_so_items i join public.ac_stock_opnames s on s.id=i.so_id where i.id=p_id;
 if not found or v_status<>'DRAFT' or not public.ac_can_view(v_branch) then raise exception 'SO sudah terkunci / lokasi tidak cocok'; end if;
 if p_qty is not null and p_qty<0 then raise exception 'Qty harus >=0'; end if;
 if p_condition not in ('BAGUS','LAYAK PAKAI','TIDAK LAYAK PAKAI','RUSAK','BELUM DIPERIKSA') then raise exception 'Kondisi salah'; end if;
 update public.ac_so_items set qty_counted=p_qty,condition=p_condition,notes=coalesce(p_notes,''),counted_by=auth.uid(),counted_at=now() where id=p_id;
end;$$;
create or replace function public.ac_submit_so(p_so uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare s public.ac_stock_opnames%rowtype;
begin
 if not coalesce(public.ac_role() in ('ADMIN','GA','STORE'),false) then raise exception 'Tidak berwenang'; end if;
 select * into s from public.ac_stock_opnames where id=p_so for update;
 if not found or s.status<>'DRAFT' or not public.ac_can_view(s.branch_id) then raise exception 'SO tidak dapat diajukan'; end if;
 if exists(select 1 from public.ac_so_items where so_id=p_so and qty_counted is null) then raise exception 'Masih ada qty yang belum dihitung'; end if;
 update public.ac_stock_opnames set status='DIAJUKAN',submitted_by=auth.uid(),submitted_at=now() where id=p_so;
end;$$;
create or replace function public.ac_approve_so(p_so uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare s public.ac_stock_opnames%rowtype; r record; v_reserved integer;
begin
 if not public.ac_manager() then raise exception 'Hanya GA/Admin yang dapat menyetujui SO'; end if;
 select * into s from public.ac_stock_opnames where id=p_so for update;
 if not found or s.status<>'DIAJUKAN' then raise exception 'SO belum diajukan'; end if;
 -- Lock semua baris aset sebelum pemeriksaan rekonsiliasi.
 perform 1 from public.ac_assets a join public.ac_so_items i on i.asset_id=a.id where i.so_id=p_so order by a.id for update of a;
 for r in select i.*,a.qty as current_qty from public.ac_so_items i join public.ac_assets a on a.id=i.asset_id where i.so_id=p_so loop
  if r.current_qty<>r.qty_system then raise exception 'Master qty berubah untuk aset %; buat SO baru',r.asset_id; end if;
  select coalesce(sum(q),0)::integer into v_reserved from (
    select qty as q from public.ac_loans where asset_id=r.asset_id and status='DIPINJAM'
    union all select qty as q from public.ac_transfers where asset_id=r.asset_id and status in ('MENUNGGU_BA','DISETUJUI','DALAM_PENGIRIMAN')) reserved;
  if r.qty_counted < v_reserved then raise exception 'Qty SO lebih kecil dari komitmen pada aset %',r.asset_id; end if;
 end loop;
 update public.ac_assets a set qty=i.qty_counted,condition=i.condition
 from public.ac_so_items i where i.so_id=p_so and i.asset_id=a.id;
 update public.ac_stock_opnames set status='DISETUJUI',approved_by=auth.uid(),approved_at=now() where id=p_so;
end;$$;

-- Cegah status tidak terpakai pada unit yang masih memiliki komitmen.
create or replace function public.ac_guard_asset_status() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_reserved integer;
begin
 if new.status='TIDAK TERPAKAI' and old.status is distinct from new.status and new.qty>0 then
  select coalesce(sum(qty),0)::integer into v_reserved from (
   select qty from public.ac_loans where asset_id=new.id and status='DIPINJAM'
   union all select qty from public.ac_transfers where asset_id=new.id and status in ('MENUNGGU_BA','DISETUJUI','DALAM_PENGIRIMAN')) x;
  if v_reserved>0 then raise exception 'Tidak bisa mengubah status: aset masih dipinjam/dalam transfer'; end if;
 end if;
 return new;
end;$$;
drop trigger if exists trg_ac_asset_guard on public.ac_assets;
create trigger trg_ac_asset_guard before update on public.ac_assets
 for each row execute function public.ac_guard_asset_status();

-- Simpan banyak baris SO secara atomik (menghindari request satu-per-satu).
create or replace function public.ac_save_so_counts(p_so uuid,p_items jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare s public.ac_stock_opnames%rowtype; e jsonb; v_id uuid; v_qty integer; v_cond text; v_count integer:=0;
begin
 if not coalesce(public.ac_role() in ('ADMIN','GA','STORE'),false) then raise exception 'Tidak berwenang'; end if;
 select * into s from public.ac_stock_opnames where id=p_so for update;
 if not found or s.status<>'DRAFT' or not public.ac_can_view(s.branch_id) then raise exception 'SO tidak lagi dapat diubah'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>2500 then raise exception 'Data hitungan SO tidak valid'; end if;
 for e in select value from jsonb_array_elements(p_items) loop
  v_id=(e->>'id')::uuid;
  v_qty=case when e->>'qty' is null or e->>'qty'='' then null else (e->>'qty')::integer end;
  v_cond=e->>'condition';
  if v_qty<0 or v_cond not in ('BAGUS','LAYAK PAKAI','TIDAK LAYAK PAKAI','RUSAK','BELUM DIPERIKSA') then raise exception 'Qty/kondisi tidak valid'; end if;
  update public.ac_so_items set qty_counted=v_qty,condition=v_cond,notes=coalesce(e->>'notes',''),counted_by=auth.uid(),counted_at=now()
    where id=v_id and so_id=p_so;
  if not found then raise exception 'Baris SO tidak valid'; end if;
  v_count=v_count+1;
 end loop;
 return v_count;
end;$$;

-- Saat maintenance SELESAI, kondisi master ikut diperbarui jika aset masih di cabang tersebut.
create or replace function public.ac_close_maintenance() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 if new.status='SELESAI' and old.status<>'SELESAI' then
  if nullif(trim(new.action),'') is null or nullif(trim(new.result_notes),'') is null then
   raise exception 'Tindakan dan hasil maintenance wajib diisi sebelum status SELESAI';
  end if;
  if new.condition_after is not null and new.condition_after<>'' then
   if new.condition_after not in ('BAGUS','LAYAK PAKAI','TIDAK LAYAK PAKAI','RUSAK','BELUM DIPERIKSA') then
    raise exception 'Kondisi akhir tidak valid'; end if;
   update public.ac_assets set condition=new.condition_after
   where id=new.asset_id and branch_id=new.branch_id;
  end if;
 end if;
 return new;
end;$$;
drop trigger if exists trg_ac_maintenance_close on public.ac_maintenance;
create trigger trg_ac_maintenance_close before update on public.ac_maintenance
 for each row execute function public.ac_close_maintenance();

revoke all on function public.ac_transfer_catalog(),public.ac_available(uuid),public.ac_create_loan(uuid,integer,text,date,date,text),
 public.ac_return_loan(uuid,text),public.ac_create_ba(text,text,text,uuid,integer,uuid,uuid,jsonb),
 public.ac_decide_ba(uuid,boolean,text),public.ac_advance_transfer(uuid,text),
 public.ac_start_so(uuid,text),public.ac_save_so_line(uuid,integer,text,text),
 public.ac_submit_so(uuid),public.ac_approve_so(uuid),public.ac_save_so_counts(uuid,jsonb) from public,anon;
grant execute on function public.ac_transfer_catalog(),public.ac_available(uuid),public.ac_create_loan(uuid,integer,text,date,date,text),
 public.ac_return_loan(uuid,text),public.ac_create_ba(text,text,text,uuid,integer,uuid,uuid,jsonb),
 public.ac_decide_ba(uuid,boolean,text),public.ac_advance_transfer(uuid,text),
 public.ac_start_so(uuid,text),public.ac_save_so_line(uuid,integer,text,text),
 public.ac_submit_so(uuid),public.ac_approve_so(uuid),public.ac_save_so_counts(uuid,jsonb) to authenticated;
commit;
