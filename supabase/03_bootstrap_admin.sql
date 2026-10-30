-- OPSIONAL, jalankan setelah Anda membuat email user di Supabase > Authentication > Users.
-- GANTI alamat email di bawah dahulu. Jangan jalankan dengan placeholder.
do $$
declare v_email text := 'GANTI_EMAIL_ADMIN@PERUSAHAAN.COM'; v_id uuid;
begin
 if v_email like 'GANTI_%' then raise exception 'Ganti email admin terlebih dahulu'; end if;
 select id into v_id from auth.users where lower(email)=lower(v_email);
 if v_id is null then raise exception 'Email % tidak ditemukan di Authentication > Users',v_email; end if;
 update public.ac_profiles set display_name='GA Administrator',role='ADMIN',active=true,updated_at=now() where id=v_id;
 if not found then raise exception 'Profil admin belum ada'; end if;
 raise notice 'Admin diaktifkan: %',v_email;
end $$;
