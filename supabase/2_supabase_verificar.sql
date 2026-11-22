-- Solo lectura. Córrelo después de instalar. Cada bloque dice qué resultado esperar.

-- (a) Tablas SIN RLS  → ESPERADO: 0 filas
select tablename as tabla_sin_rls from pg_tables where schemaname = 'public' and not rowsecurity;

-- (b) Cuántas tablas y funciones se crearon → ESPERADO: 25 tablas y funciones_clave_de_6 = 6
select (select count(*) from pg_tables where schemaname='public') as tablas,
       (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname in ('create_group','save_group_expense','mark_payment_paid',
         'confirm_group_settlement','advance_payment_date','revert_payment_due_date')) as funciones_clave_de_6;

-- (c) Después de crear tus 2 usuarios → ESPERADO: usuarios = perfiles = 2 y 15 categorías por usuario (30)
select (select count(*) from auth.users) as usuarios,
       (select count(*) from profiles) as perfiles,
       (select count(*) from transaction_categories) as categorias;
