-- ============================================================================
-- FORTOURNAL · 3_supabase_comparar_esquema.sql      (SOLO LECTURA: no modifica nada)
-- Compara tu base REAL con lo que esperan las migraciones corregidas 0001 + 0002 + 0003
-- y con lo que usará la app. Pégalo en Supabase → SQL Editor → Run.
-- Resultado: una tabla. La primera fila es el resumen; después, cada comprobación (❌ primero).
-- Reconstruido a partir del registro técnico de la sesión anterior.
-- ============================================================================
with tablas(n) as (values
  ('profiles'),('user_preferences'),('accounts'),('transaction_categories'),('transactions'),('transfers'),
  ('recurring_income'),('recurring_payments'),('payment_history'),('money_owed'),('debt_repayments'),('savings_goals'),
  ('savings_contributions'),('notification_preferences'),('push_subscriptions'),('financial_reminders'),('user_notes'),
  ('notifications'),('budgets'),('groups'),('group_members'),('group_invites'),('group_expenses'),('group_expense_splits'),
  ('group_settlements')),
columnas(t, c) as (values
  ('recurring_payments','anchor_day'),('recurring_payments','due_date'),('recurring_payments','is_paused'),
  ('group_members','left_at'),('group_settlements','status'),('group_settlements','confirmed_at'),
  ('group_invites','email'),('group_invites','status'),('group_expenses','updated_at'),('group_expense_splits','share'),
  ('budgets','monthly_amount'),('money_owed','person_name'),('money_owed','expected_on'),
  ('recurring_income','first_payment_date'),('recurring_income','day_of_month'),('recurring_income','end_date'),
  ('savings_contributions','transfer_id'),('savings_goals','account_id'),('user_notes','is_done'),('financial_reminders','remind_on')),
funciones(n) as (values
  ('create_group'),('invite_to_group'),('my_pending_invites'),('accept_invite'),('decline_invite'),
  ('leave_group'),('save_group_expense'),('create_group_settlement'),('confirm_group_settlement'),('check_expense_split_total'),
  ('is_group_member'),('add_months_anchored'),('advance_payment_date'),('revert_payment_due_date'),('recurring_payments_anchor'),
  ('mark_payment_paid'),('confirm_recurring_income'),('record_debt_repayment'),('category_id_by_key'),('handle_new_user')),
triggers(n) as (values
  ('on_auth_user_created'),('payment_history_revert'),('payment_history_del'),('debt_repayments_del'),
  ('recurring_payments_anchor'),('ge_split_total'),('gs_split_total'),('group_expenses_upd')),
vistas(n) as (values ('account_balances'),('balance_summary'),('money_owed_status'),('group_balances')),
indices(n) as (values
  ('transfers_from_idx'),('transfers_to_idx'),('debt_repayments_owed_idx'),('savings_contrib_goal_idx'),('recurring_payments_due_idx')),
chk as (
  select 'tabla: ' || n as comprobacion,
         exists (select 1 from pg_tables where schemaname='public' and tablename = n) as ok from tablas
  union all select 'RLS activo: ' || n,
         coalesce((select rowsecurity from pg_tables where schemaname='public' and tablename = n), false) from tablas
  union all select 'columna: ' || t || '.' || c,
         exists (select 1 from information_schema.columns where table_schema='public' and table_name=t and column_name=c) from columnas
  union all select 'función: ' || n,
         exists (select 1 from pg_proc p join pg_namespace s on s.oid=p.pronamespace where s.nspname='public' and p.proname=n) from funciones
  union all select 'trigger: ' || n,
         exists (select 1 from pg_trigger g where not g.tgisinternal and g.tgname = n) from triggers
  union all select 'vista respeta RLS (security_invoker): ' || n,
         coalesce((select 'security_invoker=true' = any(c.reloptions) from pg_class c join pg_namespace s on s.oid=c.relnamespace
                   where s.nspname='public' and c.relname = n and c.relkind='v'), false) from vistas
  union all select 'índice: ' || n,
         exists (select 1 from pg_indexes where schemaname='public' and indexname = n) from indices
  -- ── versión exacta de 0003 / 0002 v2 ──
  union all select 'advance_payment_date tiene 4 argumentos (0003)',
         exists (select 1 from pg_proc p join pg_namespace s on s.oid=p.pronamespace
                 where s.nspname='public' and p.proname='advance_payment_date' and p.pronargs = 4)
  union all select 'NO existe la advance_payment_date vieja de 3 argumentos',
         not exists (select 1 from pg_proc p join pg_namespace s on s.oid=p.pronamespace
                 where s.nspname='public' and p.proname='advance_payment_date' and p.pronargs = 3)
  union all select 'save_group_expense tiene 7 argumentos (0002 v2)',
         exists (select 1 from pg_proc p join pg_namespace s on s.oid=p.pronamespace
                 where s.nspname='public' and p.proname='save_group_expense' and p.pronargs = 7)
  union all select 'política de gastos de grupo: SOLO lectura/borrar del creador (0002 v2)',
         exists (select 1 from pg_policies where schemaname='public' and tablename='group_expenses' and policyname='ge_delete')
         and not exists (select 1 from pg_policies where schemaname='public' and tablename='group_expenses' and policyname='ge_all')
  union all select 'NO existen políticas de escritura abiertas en grupos (0002 v1 las tenía)',
         not exists (select 1 from pg_policies where schemaname='public'
                     and policyname in ('gs_all','gst_all','gi_insert','gm_leave','g_insert'))
  union all select 'las funciones de grupos NO son ejecutables por anónimos',
         not exists (select 1 from pg_proc p join pg_namespace s on s.oid=p.pronamespace
                     where s.nspname='public'
                     and p.proname in ('create_group','invite_to_group','save_group_expense','create_group_settlement','confirm_group_settlement','leave_group')
                     and has_function_privilege('anon', p.oid, 'execute'))
  union all select 'las FK hacia group_members son diferidas (borrar grupos funciona)',
         (select count(*) from pg_constraint
           where contype='f' and confrelid = 'public.group_members'::regclass
             and conrelid in ('public.group_expenses'::regclass,'public.group_expense_splits'::regclass,'public.group_settlements'::regclass)
             and condeferrable and condeferred) = 4
  union all select 'ancla de pagos: anchor_day es obligatoria (NOT NULL, 0003)',
         exists (select 1 from information_schema.columns where table_schema='public' and table_name='recurring_payments'
                 and column_name='anchor_day' and is_nullable='NO')
  union all select 'número de tablas en public = 25',
         (select count(*) from pg_tables where schemaname='public') = 25
)
select * from (
  select 0 as orden,
         case when bool_and(ok) then '✅ TU ESQUEMA COINCIDE con 0001+0002+0003 (no hace falta migración)'
              else '❌ HAY DIFERENCIAS: ' || count(*) filter (where not ok) || ' de ' || count(*) || ' comprobaciones fallan (mira abajo)' end as comprobacion,
         bool_and(ok) as ok
  from chk
  union all
  select 1, comprobacion, ok from chk where not ok
  union all
  select 2, comprobacion, ok from chk where ok
) r order by orden, comprobacion;
