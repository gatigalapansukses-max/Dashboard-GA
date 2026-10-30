-- TIGALAPAN ASSET CONTROL | Supabase PostgreSQL | v1.0
-- Jalankan SATU KALI di SQL Editor proyek tujuan. Backup sebelum migrasi.
-- Tidak menghapus tabel/data yang sudah ada. Nama tabel menggunakan prefix ac_.
begin;

create table if not exists public.ac_branches (
 id uuid primary key default gen_random_uuid(), name text not null unique, active boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists public.ac_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null default '', role text not null default 'STORE' check (role in ('ADMIN','GA','FAT','STORE','AUDITOR')),
 branch_id uuid references public.ac_branches(id), active boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint ac_store_branch check (role <> 'STORE' or branch_id is not null or active = false)
);

create or replace function public.ac_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.ac_profiles(id,display_name,role,active) values
  (new.id,coalesce(new.raw_user_meta_data->>'display_name',split_part(coalesce(new.email,''),'@',1)),'STORE',false)
  on conflict(id) do nothing;
  return new;
end;$$;
drop trigger if exists trg_ac_new_user on auth.users;
create trigger trg_ac_new_user after insert on auth.users for each row execute function public.ac_new_user();
-- Rekonsiliasi akun Auth yang sudah dibuat sebelum instalasi
insert into public.ac_profiles(id,display_name)
select id,coalesce(raw_user_meta_data->>'display_name',split_part(coalesce(email,''),'@',1)) from auth.users
on conflict(id) do nothing;

-- Helper SECURITY DEFINER hanya untuk baca identitas user login, bukan membocorkan tabel.
create or replace function public.ac_role() returns text language sql stable security definer set search_path = '' as $$
 select role from public.ac_profiles where id = (select auth.uid()) and active = true limit 1
$$;
create or replace function public.ac_branch() returns uuid language sql stable security definer set search_path = '' as $$
 select branch_id from public.ac_profiles where id = (select auth.uid()) and active = true limit 1
$$;
create or replace function public.ac_global() returns boolean language sql stable security definer set search_path = '' as $$
 select coalesce((select role in ('ADMIN','GA','FAT','AUDITOR') from public.ac_profiles where id=(select auth.uid()) and active=true),false)
$$;
create or replace function public.ac_manager() returns boolean language sql stable security definer set search_path = '' as $$
 select coalesce((select role in ('ADMIN','GA') from public.ac_profiles where id=(select auth.uid()) and active=true),false)
$$;
create or replace function public.ac_can_view(p_branch uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select coalesce(public.ac_global() or (public.ac_role()='STORE' and p_branch=public.ac_branch()),false)
$$;

create table if not exists public.ac_assets (
 id uuid primary key default gen_random_uuid(),
 asset_code text not null unique default ('AS-' || upper(substr(gen_random_uuid()::text,1,8))),
 name text not null check (length(trim(name))>0), brand text not null default '',
 qty integer not null default 1 check (qty>=0),
 category text not null default 'INVENTARIS' check (category in ('ASET','INVENTARIS')),
 condition text not null default 'BELUM DIPERIKSA' check (condition in ('BAGUS','LAYAK PAKAI','TIDAK LAYAK PAKAI','RUSAK','BELUM DIPERIKSA')),
 status text not null default 'TERPAKAI' check (status in ('TERPAKAI','TIDAK TERPAKAI')),
 branch_id uuid not null references public.ac_branches(id), position text not null default '',
 owner_name text not null default '', notes text not null default '',
 purchase_date date, purchase_price numeric(15,2) check (purchase_price>=0),
 registration_no text not null default '', serial_no text not null default '',
 photo_url text not null default '', source text not null default 'INPUT MANUAL',
 origin_asset_id uuid references public.ac_assets(id),
 created_by uuid references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists idx_ac_assets_branch on public.ac_assets(branch_id);
create index if not exists idx_ac_assets_category on public.ac_assets(category,status);

create table if not exists public.ac_loans (
 id uuid primary key default gen_random_uuid(), asset_id uuid not null references public.ac_assets(id),
 branch_id uuid not null references public.ac_branches(id), qty integer not null check(qty>0),
 borrower text not null, borrow_date date not null, due_date date not null, return_date date,
 status text not null default 'DIPINJAM' check (status in ('DIPINJAM','DIKEMBALIKAN')),
 notes text not null default '', created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 constraint ac_loan_dates check(due_date>=borrow_date)
);
create index if not exists idx_ac_loans_asset on public.ac_loans(asset_id,status);

create table if not exists public.ac_ba (
 id uuid primary key default gen_random_uuid(), ba_number text not null unique default ('BA-' || to_char(now(),'YYMMDD') || '-' || upper(substr(gen_random_uuid()::text,1,7))),
 ba_type text not null check (ba_type in ('ASET_BARU','TRANSFER','LAINNYA')),
 title text not null, description text not null default '', asset_id uuid references public.ac_assets(id),
 qty integer not null default 1 check(qty>0), from_branch_id uuid references public.ac_branches(id),
 to_branch_id uuid references public.ac_branches(id), recipient_id uuid references public.ac_profiles(id),
 status text not null default 'MENUNGGU' check(status in ('MENUNGGU','DISETUJUI','DITOLAK','DIBATALKAN')),
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 finished_at timestamptz, other_details jsonb not null default '{}'::jsonb
);
create table if not exists public.ac_ba_approvals (
 id uuid primary key default gen_random_uuid(), ba_id uuid not null references public.ac_ba(id) on delete cascade,
 step_no integer not null check(step_no>0), label text not null,
 role_required text not null check(role_required in ('ADMIN','GA','FAT','STORE','USER')),
 branch_id uuid references public.ac_branches(id), user_id uuid references public.ac_profiles(id),
 decision text not null default 'MENUNGGU' check(decision in ('MENUNGGU','DISETUJUI','DITOLAK')),
 decided_by uuid references public.ac_profiles(id), decided_at timestamptz,
 note text not null default '', unique(ba_id,step_no)
);
create index if not exists idx_ac_ba_approvals_ba on public.ac_ba_approvals(ba_id,step_no);

create table if not exists public.ac_transfers (
 id uuid primary key default gen_random_uuid(), ba_id uuid not null unique references public.ac_ba(id),
 asset_id uuid not null references public.ac_assets(id), from_branch_id uuid not null references public.ac_branches(id),
 to_branch_id uuid not null references public.ac_branches(id), qty integer not null check(qty>0),
 status text not null default 'MENUNGGU_BA' check(status in ('MENUNGGU_BA','DISETUJUI','DALAM_PENGIRIMAN','DITERIMA','DITOLAK','DIBATALKAN')),
 notes text not null default '', requested_by uuid not null references auth.users(id),
 shipped_by uuid references auth.users(id), shipped_at timestamptz,
 received_by uuid references auth.users(id), received_at timestamptz,
 destination_asset_id uuid references public.ac_assets(id), created_at timestamptz not null default now()
);
create index if not exists idx_ac_transfers_asset on public.ac_transfers(asset_id,status);

create table if not exists public.ac_maintenance (
 id uuid primary key default gen_random_uuid(), ticket_code text not null unique default ('MT-' || upper(substr(gen_random_uuid()::text,1,8))),
 asset_id uuid not null references public.ac_assets(id), branch_id uuid not null references public.ac_branches(id),
 maintenance_type text not null default 'PERBAIKAN' check(maintenance_type in ('PERBAIKAN','PREVENTIF','INSPEKSI','PENGGANTIAN','INSTALASI','LAINNYA')),
 issue text not null check(length(trim(issue))>0), priority text not null default 'SEDANG' check(priority in ('RENDAH','SEDANG','TINGGI','KRITIS')),
 impact text not null default '', location_detail text not null default '',
 vendor text not null default '', pic text not null default '',
 estimated_cost numeric(15,2) not null default 0 check(estimated_cost>=0),
 actual_cost numeric(15,2) not null default 0 check(actual_cost>=0),
 due_date date, started_at timestamptz, closed_at timestamptz,
 status text not null default 'DILAPORKAN' check(status in ('DILAPORKAN','DIJADWALKAN','DIPROSES','MENUNGGU_PART','SELESAI','DIBATALKAN')),
 action text not null default '', result_notes text not null default '', condition_after text,
 reported_by uuid not null references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists idx_ac_maintenance_asset_branch on public.ac_maintenance(asset_id,branch_id,created_at desc);
create table if not exists public.ac_maintenance_photos (
 id uuid primary key default gen_random_uuid(), maintenance_id uuid not null references public.ac_maintenance(id) on delete cascade,
 storage_key text not null unique, caption text not null default '', photo_type text not null default 'SEBELUM'
 check(photo_type in ('SEBELUM','PROSES','SESUDAH','LAINNYA')),
 uploaded_by uuid not null references auth.users(id), created_at timestamptz not null default now()
);

create table if not exists public.ac_stock_opnames (
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.ac_branches(id),
 status text not null default 'DRAFT' check (status in ('DRAFT','DIAJUKAN','DISETUJUI')),
 notes text not null default '', created_by uuid not null references auth.users(id),
 submitted_by uuid references auth.users(id), approved_by uuid references auth.users(id),
 created_at timestamptz not null default now(), submitted_at timestamptz, approved_at timestamptz
);
create unique index if not exists idx_ac_so_open_branch on public.ac_stock_opnames(branch_id) where status in ('DRAFT','DIAJUKAN');
create table if not exists public.ac_so_items (
 id uuid primary key default gen_random_uuid(), so_id uuid not null references public.ac_stock_opnames(id) on delete cascade,
 asset_id uuid not null references public.ac_assets(id), qty_system integer not null check(qty_system>=0),
 qty_counted integer check(qty_counted>=0), condition text not null,
 notes text not null default '', counted_by uuid references auth.users(id), counted_at timestamptz,
 unique (so_id,asset_id)
);
create table if not exists public.ac_audit (
 id bigint generated always as identity primary key, at timestamptz not null default now(),
 actor uuid, action text not null, entity text not null, entity_id text not null,
 branch_id uuid, details jsonb not null default '{}'::jsonb
);
create index if not exists idx_ac_audit_at on public.ac_audit(at desc);

create or replace function public.ac_touch() returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at=now(); return new; end;$$;
drop trigger if exists trg_ac_assets_touch on public.ac_assets;
create trigger trg_ac_assets_touch before update on public.ac_assets for each row execute function public.ac_touch();
drop trigger if exists trg_ac_maintenance_touch on public.ac_maintenance;
create trigger trg_ac_maintenance_touch before update on public.ac_maintenance for each row execute function public.ac_touch();

create or replace function public.ac_audit_change() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_branch uuid; v_id text;
begin
  v_id=coalesce((case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end)->>'id','');
  v_branch=nullif(coalesce((case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end)->>'branch_id',''),'')::uuid;
  insert into public.ac_audit(actor,action,entity,entity_id,branch_id,details)
  values (auth.uid(),tg_op,tg_table_name,v_id,v_branch,
    jsonb_build_object('before',case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
                       'after',case when tg_op in ('UPDATE','INSERT') then to_jsonb(new) else null end));
  return null;
end;$$;
-- old/new record referencing inside CASE expressions is safe for row triggers.
do $$ declare t text; begin
 foreach t in array array['ac_assets','ac_loans','ac_ba','ac_ba_approvals','ac_transfers','ac_maintenance','ac_maintenance_photos','ac_stock_opnames','ac_so_items'] loop
  execute format('drop trigger if exists %I on public.%I','trg_' || t || '_audit',t);
  execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.ac_audit_change()','trg_' || t || '_audit',t);
 end loop;
end$$;

-- RLS semua tabel berisi data internal; anon tidak memiliki policy.
alter table public.ac_branches enable row level security;
alter table public.ac_profiles enable row level security;
alter table public.ac_assets enable row level security;
alter table public.ac_loans enable row level security;
alter table public.ac_ba enable row level security;
alter table public.ac_ba_approvals enable row level security;
alter table public.ac_transfers enable row level security;
alter table public.ac_maintenance enable row level security;
alter table public.ac_maintenance_photos enable row level security;
alter table public.ac_stock_opnames enable row level security;
alter table public.ac_so_items enable row level security;
alter table public.ac_audit enable row level security;

create policy "ac branches read" on public.ac_branches for select to authenticated using(public.ac_role() is not null);
create policy "ac branches manage" on public.ac_branches for all to authenticated using(public.ac_role()='ADMIN') with check(public.ac_role()='ADMIN');
create policy "ac profiles read" on public.ac_profiles for select to authenticated using(id=auth.uid() or public.ac_global() or (public.ac_role()='STORE' and branch_id=public.ac_branch()));
create policy "ac profiles admin update" on public.ac_profiles for update to authenticated using(public.ac_role()='ADMIN') with check(public.ac_role()='ADMIN');
create policy "ac assets read" on public.ac_assets for select to authenticated using(public.ac_can_view(branch_id));
create policy "ac assets ga insert" on public.ac_assets for insert to authenticated with check(public.ac_manager() and created_by=auth.uid());
-- Jangan beri hak DELETE aset; mutasi wajib melalui fungsi RPC.
-- Kolom sensitif qty/lokasi TIDAK diberikan izin update langsung (grant terbatas di bawah).
create policy "ac assets ga edit" on public.ac_assets for update to authenticated using(public.ac_manager()) with check(public.ac_manager());
create policy "ac loans read" on public.ac_loans for select to authenticated using(public.ac_can_view(branch_id));
create policy "ac ba read" on public.ac_ba for select to authenticated using(
 public.ac_global() or created_by=auth.uid() or recipient_id=auth.uid() or
 (public.ac_role()='STORE' and (from_branch_id=public.ac_branch() or to_branch_id=public.ac_branch()))
);
create policy "ac approvals read" on public.ac_ba_approvals for select to authenticated using(
 exists(select 1 from public.ac_ba b where b.id=ba_id and
 (public.ac_global() or b.created_by=auth.uid() or b.recipient_id=auth.uid() or b.from_branch_id=public.ac_branch() or b.to_branch_id=public.ac_branch()))
);
create policy "ac transfer read" on public.ac_transfers for select to authenticated using(public.ac_global() or from_branch_id=public.ac_branch() or to_branch_id=public.ac_branch());
create policy "ac maintenance read" on public.ac_maintenance for select to authenticated using(public.ac_can_view(branch_id));
create policy "ac maintenance insert" on public.ac_maintenance for insert to authenticated with check(
 public.ac_role() in ('ADMIN','GA','STORE') and reported_by=auth.uid() and public.ac_can_view(branch_id)
 and exists(select 1 from public.ac_assets a where a.id=asset_id and a.branch_id=branch_id)
);
create policy "ac maintenance update" on public.ac_maintenance for update to authenticated using(public.ac_manager()) with check(public.ac_manager());
create policy "ac photos read" on public.ac_maintenance_photos for select to authenticated using(
 exists(select 1 from public.ac_maintenance m where m.id=maintenance_id and public.ac_can_view(m.branch_id))
);
create policy "ac photos write" on public.ac_maintenance_photos for insert to authenticated with check(
 uploaded_by=auth.uid() and public.ac_role() in ('ADMIN','GA','STORE')
 and exists(select 1 from public.ac_maintenance m where m.id=maintenance_id and public.ac_can_view(m.branch_id))
);
create policy "ac so read" on public.ac_stock_opnames for select to authenticated using(public.ac_can_view(branch_id));
create policy "ac so items read" on public.ac_so_items for select to authenticated using(
 exists(select 1 from public.ac_stock_opnames s where s.id=so_id and public.ac_can_view(s.branch_id))
);
create policy "ac audit read" on public.ac_audit for select to authenticated using(public.ac_global());

-- Permissions: RPC menjalankan perubahan yang harus atomik; pembaruan langsung dibatasi per kolom.
revoke all on public.ac_assets,public.ac_loans,public.ac_ba,public.ac_ba_approvals,
 public.ac_transfers,public.ac_maintenance,public.ac_maintenance_photos,
 public.ac_stock_opnames,public.ac_so_items,public.ac_audit,public.ac_profiles,
 public.ac_branches from anon, authenticated;
grant select on public.ac_assets,public.ac_loans,public.ac_ba,public.ac_ba_approvals,
 public.ac_transfers,public.ac_maintenance,public.ac_maintenance_photos,
 public.ac_stock_opnames,public.ac_so_items,public.ac_audit,public.ac_profiles,
 public.ac_branches to authenticated;
grant insert on public.ac_assets,public.ac_maintenance,public.ac_maintenance_photos,public.ac_branches to authenticated;
grant update (name,brand,category,condition,status,position,owner_name,notes,purchase_date,purchase_price,registration_no,serial_no,photo_url) on public.ac_assets to authenticated;
grant update (display_name,role,branch_id,active) on public.ac_profiles to authenticated;
grant update (name,active) on public.ac_branches to authenticated;
grant update (maintenance_type,issue,priority,impact,location_detail,vendor,pic,estimated_cost,actual_cost,due_date,started_at,closed_at,status,action,result_notes,condition_after) on public.ac_maintenance to authenticated;

-- Private bucket, upload maks. 5MB untuk foto. File di path <maintenance-id>/<uuid>.jpg
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('ac-maintenance','ac-maintenance',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
create policy "ac storage insert" on storage.objects for insert to authenticated with check(
 bucket_id='ac-maintenance' and public.ac_role() in ('ADMIN','GA','STORE')
 and exists(select 1 from public.ac_maintenance m
   where m.id=(storage.foldername(name))[1]::uuid and public.ac_can_view(m.branch_id))
);
create policy "ac storage read" on storage.objects for select to authenticated using(
 bucket_id='ac-maintenance' and exists(
  select 1 from public.ac_maintenance_photos p join public.ac_maintenance m on m.id=p.maintenance_id
  where p.storage_key=name and public.ac_can_view(m.branch_id))
);
create policy "ac storage cleanup" on storage.objects for delete to authenticated using(
 bucket_id='ac-maintenance' and public.ac_manager()
);

-- Keamanan fungsi helper: hanya pengguna login yang boleh menggunakan helper.
revoke all on function public.ac_role(),public.ac_branch(),public.ac_global(),public.ac_manager(),public.ac_can_view(uuid) from public,anon;
grant execute on function public.ac_role(),public.ac_branch(),public.ac_global(),public.ac_manager(),public.ac_can_view(uuid) to authenticated;

commit;
