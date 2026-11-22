-- ============================================================================
-- FORTOURNAL · instalación completa en UN solo paso (0001 + 0002 + 0003)
-- Pégalo ENTERO en Supabase → SQL Editor → New query → Run. Ejecútalo UNA sola vez.
-- Para volver a empezar: Database → Schema "public" → borra tablas, o crea un proyecto nuevo.
-- ============================================================================

-- ──────────────── 0001_schema.sql ────────────────
-- FORTOURNAL · 0001_schema.sql
-- Money = NUMERIC(14,2). Every private table has user_id + RLS.
-- Child rows use composite FKs (id, user_id) so a row can never point at another user's account.

create type account_type    as enum ('regular','savings');
create type txn_type        as enum ('income','expense');
create type txn_source      as enum ('manual','recurring_income','payment','debt_repayment');
create type income_freq     as enum ('weekly','every_3_weeks','monthly','once');
create type payment_freq    as enum ('weekly','monthly','every_3_months','yearly','custom');

create or replace function set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

-- ───────── identity & preferences ─────────
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table user_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  language text not null default 'en' check (language in ('en','es')),
  theme text not null default 'dark' check (theme in ('dark','light')),
  privacy_mode boolean not null default false,
  currency char(3) not null default 'MXN',
  timezone text not null default 'America/Monterrey',
  week_starts_on smallint not null default 1 check (week_starts_on between 0 and 6),
  updated_at timestamptz not null default now()
);

-- ───────── accounts & categories ─────────
create table accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  type account_type not null default 'regular',
  initial_balance numeric(14,2) not null default 0,
  is_active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id)
);
create unique index accounts_user_name_uq on accounts (user_id, lower(name)) where is_active;

create table transaction_categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind txn_type not null,
  key text,                -- system key → translated by i18n
  name text,               -- user-defined / proper-noun name (never translated)
  is_active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (key is not null or name is not null),
  unique (id, user_id)
);
create unique index categories_user_key_uq on transaction_categories (user_id, kind, key) where key is not null;

-- ───────── ledger ─────────
create table transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null,
  category_id uuid,
  type txn_type not null,
  amount numeric(14,2) not null check (amount > 0),
  occurred_on date not null,
  description text,
  notes text,
  custom_category_text text,           -- for "Other/Others"
  source txn_source not null default 'manual',
  source_id uuid,                       -- recurring_income / payment / money_owed id
  source_date date,                     -- occurrence date → idempotency key
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (account_id, user_id) references accounts (id, user_id) on delete restrict,
  foreign key (category_id, user_id) references transaction_categories (id, user_id) on delete set null (category_id),
  unique (id, user_id)
);
-- Duplicate guard: one transaction per recurring occurrence / paid bill.
create unique index txn_occurrence_uq on transactions (source, source_id, source_date)
  where source in ('recurring_income','payment') and source_id is not null;
create index txn_user_date_idx on transactions (user_id, occurred_on desc);
create index txn_account_idx on transactions (account_id);

create table transfers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  from_account_id uuid not null,
  to_account_id uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  occurred_on date not null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (from_account_id <> to_account_id),
  foreign key (from_account_id, user_id) references accounts (id, user_id) on delete restrict,
  foreign key (to_account_id, user_id)   references accounts (id, user_id) on delete restrict,
  unique (id, user_id)
);
create index transfers_user_date_idx on transfers (user_id, occurred_on desc);

-- ───────── recurring income ─────────
create table recurring_income (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  amount numeric(14,2) not null check (amount > 0),
  account_id uuid not null,
  category_id uuid,
  frequency income_freq not null,
  first_payment_date date not null,
  day_of_month smallint check (day_of_month between 1 and 31),  -- monthly only; 29-31 clamp to month end
  end_date date,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date is null or end_date >= first_payment_date),
  foreign key (account_id, user_id) references accounts (id, user_id) on delete restrict,
  unique (id, user_id)
);

-- ───────── recurring payments ─────────
create table recurring_payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  amount numeric(14,2) not null check (amount > 0),
  due_date date not null,                 -- NEXT unpaid due date; advanced when paid
  frequency payment_freq not null,
  custom_interval_days int check (custom_interval_days > 0),
  account_id uuid not null,
  notes text,
  remind_days_before int[] not null default '{7,3,1,0}',
  pay_with text not null default 'salary',   -- salary | savings | other (free text in pay_with_note)
  pay_with_note text,
  is_active boolean not null default true,
  is_paused boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (frequency <> 'custom' or custom_interval_days is not null),
  foreign key (account_id, user_id) references accounts (id, user_id) on delete restrict,
  unique (id, user_id)
);

create table payment_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  payment_id uuid not null,
  due_date date not null,
  paid_on date not null,
  amount numeric(14,2) not null check (amount > 0),
  transaction_id uuid not null,
  created_at timestamptz not null default now(),
  foreign key (payment_id, user_id) references recurring_payments (id, user_id) on delete cascade,
  foreign key (transaction_id, user_id) references transactions (id, user_id) on delete cascade,
  unique (payment_id, due_date),
  unique (transaction_id)
);

-- ───────── money I'm owed ─────────
create table money_owed (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  person_name text not null,
  amount numeric(14,2) not null check (amount > 0),
  lent_on date not null,
  expected_on date,
  description text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create table debt_repayments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  money_owed_id uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  received_on date not null,
  transaction_id uuid not null,
  created_at timestamptz not null default now(),
  foreign key (money_owed_id, user_id) references money_owed (id, user_id) on delete cascade,
  foreign key (transaction_id, user_id) references transactions (id, user_id) on delete cascade,
  unique (transaction_id)
);

-- ───────── savings goals ─────────
create table savings_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  target_amount numeric(14,2) not null check (target_amount > 0),
  target_date date,
  description text,
  account_id uuid,                        -- optional savings account backing the goal
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (account_id, user_id) references accounts (id, user_id) on delete set null (account_id),
  unique (id, user_id)
);

-- OPEN DECISION D4: a contribution is an earmark; if transfer_id is set it is backed by a real transfer.
create table savings_contributions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  contributed_on date not null,
  transfer_id uuid,
  notes text,
  created_at timestamptz not null default now(),
  foreign key (goal_id, user_id) references savings_goals (id, user_id) on delete cascade,
  foreign key (transfer_id, user_id) references transfers (id, user_id) on delete set null (transfer_id)
);

-- ───────── notifications ─────────
create table notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  push_enabled boolean not null default false,
  bills boolean not null default true,
  income boolean not null default true,
  repayments boolean not null default true,
  custom boolean not null default true,
  remind_days_before int[] not null default '{7,3,1,0}',
  notify_hour smallint not null default 9 check (notify_hour between 0 and 23),
  updated_at timestamptz not null default now()
);

create table push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now()
);

create table financial_reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  notes text,
  remind_on date not null,
  is_done boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table user_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text,
  remind_on date,
  is_done boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('bill','overdue','income','repayment','custom')),
  title_key text not null,                -- i18n key, rendered in the user's language
  params jsonb not null default '{}',
  related_id uuid,
  dedupe_key text not null,               -- e.g. 'bill:<id>:<due>:3d' → scheduler is idempotent
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  unique (user_id, dedupe_key)
);
create index notifications_user_idx on notifications (user_id, created_at desc);

-- ───────── updated_at triggers ─────────
do $$ declare t text; begin
  foreach t in array array['profiles','user_preferences','accounts','transaction_categories','transactions',
    'transfers','recurring_income','recurring_payments','money_owed','savings_goals',
    'notification_preferences','financial_reminders','user_notes'] loop
    execute format('create trigger %I_upd before update on %I for each row execute function set_updated_at()', t, t);
  end loop;
end $$;

-- ───────── RLS (all private tables) ─────────
do $$ declare t text; begin
  foreach t in array array['user_preferences','accounts','transaction_categories','transactions','transfers',
    'recurring_income','recurring_payments','payment_history','money_owed','debt_repayments','savings_goals',
    'savings_contributions','notification_preferences','push_subscriptions','financial_reminders','user_notes','notifications'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy own_rows on %I for all to authenticated
                    using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
  end loop;
end $$;
alter table profiles enable row level security;
create policy own_profile on profiles for all to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- ───────── derived data (never stored → can't drift) ─────────
create view account_balances with (security_invoker = true) as
select a.id as account_id, a.user_id, a.name, a.type, a.is_active,
  a.initial_balance
  + coalesce((select sum(amount) from transactions t where t.account_id = a.id and t.type = 'income'), 0)
  - coalesce((select sum(amount) from transactions t where t.account_id = a.id and t.type = 'expense'), 0)
  + coalesce((select sum(amount) from transfers f where f.to_account_id = a.id), 0)
  - coalesce((select sum(amount) from transfers f where f.from_account_id = a.id), 0) as balance
from accounts a;

create view balance_summary with (security_invoker = true) as
select user_id,
  sum(balance) as total_balance,
  sum(balance) filter (where type = 'regular') as available_balance,
  sum(balance) filter (where type = 'savings') as savings_balance
from account_balances where is_active group by user_id;

create view money_owed_status with (security_invoker = true) as
select m.*, coalesce(r.repaid, 0) as repaid, m.amount - coalesce(r.repaid, 0) as remaining,
  case when m.amount - coalesce(r.repaid, 0) <= 0 then 'paid'
       when m.expected_on < current_date then 'overdue'
       when coalesce(r.repaid, 0) > 0 then 'partially_paid'
       else 'pending' end as status
from money_owed m
left join (select money_owed_id, sum(amount) repaid from debt_repayments group by 1) r on r.money_owed_id = m.id;
-- NOTE: current_date is UTC on the server; the app recomputes overdue in the user's timezone for display.

-- ───────── helpers & transactional functions (SECURITY INVOKER → RLS still applies) ─────────
create or replace function category_id_by_key(p_kind txn_type, p_key text) returns uuid
language sql stable as $$
  select id from transaction_categories where user_id = auth.uid() and kind = p_kind and key = p_key limit 1 $$;

create or replace function advance_payment_date(d date, f payment_freq, custom_days int) returns date
language sql immutable as $$
  select case f when 'weekly' then d + 7 when 'monthly' then (d + interval '1 month')::date
    when 'every_3_months' then (d + interval '3 months')::date when 'yearly' then (d + interval '1 year')::date
    else d + custom_days end $$;

-- Mark a bill paid: one expense, one history row, next due date advanced. Idempotent per due date.
create or replace function mark_payment_paid(p_payment_id uuid, p_amount numeric, p_account_id uuid, p_paid_on date)
returns uuid language plpgsql as $$
declare p recurring_payments; v_txn uuid;
begin
  select * into p from recurring_payments where id = p_payment_id and user_id = auth.uid() for update;
  if not found then raise exception 'payment_not_found'; end if;
  if p_amount <= 0 then raise exception 'invalid_amount'; end if;
  insert into transactions (user_id, account_id, category_id, type, amount, occurred_on, description, source, source_id, source_date)
  values (auth.uid(), p_account_id, category_id_by_key('expense','monthly_bills'), 'expense', p_amount, p_paid_on, p.name, 'payment', p.id, p.due_date)
  returning id into v_txn;                                  -- unique index rejects a second payment of the same due date
  insert into payment_history (user_id, payment_id, due_date, paid_on, amount, transaction_id)
  values (auth.uid(), p.id, p.due_date, p_paid_on, p_amount, v_txn);
  update recurring_payments set due_date = advance_payment_date(p.due_date, p.frequency, p.custom_interval_days) where id = p.id;
  return v_txn;
end $$;

-- Confirm an expected income occurrence as received.
create or replace function confirm_recurring_income(p_id uuid, p_expected_date date, p_amount numeric, p_account_id uuid, p_received_on date)
returns uuid language plpgsql as $$
declare r recurring_income; v_txn uuid;
begin
  select * into r from recurring_income where id = p_id and user_id = auth.uid() for update;
  if not found then raise exception 'income_not_found'; end if;
  insert into transactions (user_id, account_id, category_id, type, amount, occurred_on, description, source, source_id, source_date)
  values (auth.uid(), p_account_id, r.category_id, 'income', p_amount, p_received_on, r.name, 'recurring_income', r.id, p_expected_date)
  returning id into v_txn;
  return v_txn;
end $$;

-- Register a (partial) repayment: real income transaction + repayment row, atomically.
create or replace function record_debt_repayment(p_owed_id uuid, p_amount numeric, p_account_id uuid, p_received_on date)
returns uuid language plpgsql as $$
declare m money_owed_status; v_txn uuid;
begin
  select * into m from money_owed_status where id = p_owed_id;
  if not found then raise exception 'debt_not_found'; end if;
  if p_amount <= 0 or p_amount > m.remaining then raise exception 'invalid_amount'; end if;
  insert into transactions (user_id, account_id, category_id, type, amount, occurred_on, description, source, source_id)
  values (auth.uid(), p_account_id, category_id_by_key('income','debt_repayment'), 'income', p_amount, p_received_on, m.person_name, 'debt_repayment', m.id)
  returning id into v_txn;
  insert into debt_repayments (user_id, money_owed_id, amount, received_on, transaction_id)
  values (auth.uid(), m.id, p_amount, p_received_on, v_txn);
  return v_txn;
end $$;

-- Deleting a repayment / payment-history row also removes its linked transaction (keeps ledger consistent).
create or replace function delete_linked_transaction() returns trigger language plpgsql as $$
begin delete from transactions where id = old.transaction_id; return old; end $$;
create trigger debt_repayments_del after delete on debt_repayments for each row execute function delete_linked_transaction();
create trigger payment_history_del after delete on payment_history for each row execute function delete_linked_transaction();
-- (the cascade back from transactions is a no-op once the row is gone)

-- ───────── new-user bootstrap: profile, preferences, default categories ─────────
create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name) values (new.id, coalesce(new.raw_user_meta_data->>'display_name',''));
  insert into user_preferences (user_id) values (new.id);
  insert into notification_preferences (user_id) values (new.id);
  insert into transaction_categories (user_id, kind, key, name, sort_order) values
    (new.id,'income','salary',null,1), (new.id,'income',null,'Mami Monthly',2), (new.id,'income',null,'Elchizetla Weekly',3),
    (new.id,'income','other',null,4), (new.id,'income','debt_repayment',null,99),
    (new.id,'expense','food',null,1), (new.id,'expense','transportation',null,2), (new.id,'expense','groceries',null,3),
    (new.id,'expense','laundry',null,4), (new.id,'expense','monthly_bills',null,5), (new.id,'expense','family',null,6),
    (new.id,'expense','amorcito',null,7), (new.id,'expense','pokemon_go',null,8),
    (new.id,'expense','personal_outings',null,9), (new.id,'expense','others',null,10);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

-- ──────────────── 0002_groups_budgets.sql ────────────────
-- FORTOURNAL · 0002_groups_budgets.sql  (v2: corregida; correr después de 0001)
-- Gastos compartidos + presupuestos. Las finanzas personales NUNCA se exponen al grupo.
--
-- Principios de esta versión:
--   1. Los clientes SOLO LEEN las tablas del grupo. Toda escritura pasa por funciones
--      (security definer) que validan quién eres y que los números cuadren.
--   2. Un gasto y sus splits se guardan juntos; la suma de splits = monto, siempre.
--   3. Solo el creador edita/borra su gasto. Una liquidación la confirma la OTRA persona.
--   4. Salir de un grupo conserva el historial (left_at), no borra filas.

-- ───────── presupuestos (sin cambios; pendiente: validar que la categoría sea de gasto) ─────────
create table budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category_id uuid not null,
  monthly_amount numeric(14,2) not null check (monthly_amount > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (category_id, user_id) references transaction_categories (id, user_id) on delete cascade,
  unique (user_id, category_id)
);
alter table budgets enable row level security;
create policy own_rows on budgets for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create trigger budgets_upd before update on budgets for each row execute function set_updated_at();

-- ───────── tablas de grupos ─────────
-- Nota: las FK hacia group_members son DEFERRABLE INITIALLY DEFERRED para que borrar un grupo
-- (cascade a integrantes, gastos, splits y liquidaciones) se valide al final, no a mitad del borrado.
create table groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table group_members (
  group_id uuid not null references groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','member')),
  joined_at timestamptz not null default now(),
  left_at timestamptz,                       -- null = integrante activo; con fecha = salió (historial intacto)
  primary key (group_id, user_id)
);
create index group_members_user_idx on group_members (user_id);

create table group_invites (                 -- invitación por correo; la acepta o rechaza la persona invitada
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups(id) on delete cascade,
  email text not null check (email = lower(email)),
  invited_by uuid not null references auth.users(id),
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  unique (group_id, email)
);
create index group_invites_email_idx on group_invites (email);

create table group_expenses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups(id) on delete cascade,
  paid_by uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  description text,
  occurred_on date not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (group_id, paid_by) references group_members (group_id, user_id) deferrable initially deferred,
  unique (id, group_id)
);
create index group_expenses_group_idx on group_expenses (group_id, occurred_on desc);
create trigger group_expenses_upd before update on group_expenses for each row execute function set_updated_at();

create table group_expense_splits (          -- parte de cada integrante (exacta al centavo)
  expense_id uuid not null,
  group_id uuid not null,
  user_id uuid not null,
  share numeric(14,2) not null check (share >= 0),
  primary key (expense_id, user_id),
  foreign key (expense_id, group_id) references group_expenses (id, group_id) on delete cascade,
  foreign key (group_id, user_id) references group_members (group_id, user_id) deferrable initially deferred
);
create index group_splits_member_idx on group_expense_splits (group_id, user_id);

create table group_settlements (             -- "X le pagó a Y": pendiente hasta que la otra persona confirma
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups(id) on delete cascade,
  from_user uuid not null,
  to_user uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  occurred_on date not null,
  status text not null default 'pending' check (status in ('pending','confirmed')),
  created_by uuid not null references auth.users(id),
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  check (from_user <> to_user),
  check (created_by in (from_user, to_user)),
  foreign key (group_id, from_user) references group_members (group_id, user_id) deferrable initially deferred,
  foreign key (group_id, to_user) references group_members (group_id, user_id) deferrable initially deferred
);
create index group_settlements_group_idx on group_settlements (group_id, occurred_on desc);

-- ───────── membresía (security definer evita RLS recursivo) ─────────
create or replace function is_group_member(gid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_members
                 where group_id = gid and user_id = auth.uid() and left_at is null) $$;

-- ───────── RLS: los clientes solo leen; lo demás va por funciones ─────────
alter table groups enable row level security;
alter table group_members enable row level security;
alter table group_invites enable row level security;
alter table group_expenses enable row level security;
alter table group_expense_splits enable row level security;
alter table group_settlements enable row level security;

create policy g_select on groups for select to authenticated using (is_group_member(id));
create policy g_update on groups for update to authenticated
  using (created_by = (select auth.uid()) and is_group_member(id))
  with check (created_by = (select auth.uid()));          -- no se puede reasignar created_by
create policy g_delete on groups for delete to authenticated
  using (created_by = (select auth.uid()));
-- (sin policy de INSERT: se crea con create_group())

create policy gm_select on group_members for select to authenticated using (is_group_member(group_id));
-- (sin INSERT/UPDATE/DELETE: invitar, aceptar y salir van por funciones)

create policy gi_select on group_invites for select to authenticated
  using (is_group_member(group_id) or lower(email) = lower((select auth.jwt() ->> 'email')));
-- (sin escritura directa: invite_to_group / accept_invite / decline_invite)

create policy ge_select on group_expenses for select to authenticated using (is_group_member(group_id));
create policy ge_delete on group_expenses for delete to authenticated
  using (is_group_member(group_id) and created_by = (select auth.uid()));   -- solo el creador borra
-- (crear/editar: save_group_expense())

create policy gs_select on group_expense_splits for select to authenticated using (is_group_member(group_id));
-- (los splits solo cambian vía save_group_expense())

create policy gst_select on group_settlements for select to authenticated using (is_group_member(group_id));
create policy gst_delete on group_settlements for delete to authenticated
  using (is_group_member(group_id) and status = 'pending'
         and (from_user = (select auth.uid()) or to_user = (select auth.uid())));  -- cancelar/rechazar mientras está pendiente
-- (confirmadas son inmutables)

-- ───────── funciones ─────────
create or replace function create_group(p_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  insert into groups (name, created_by) values (p_name, auth.uid()) returning id into v;
  insert into group_members (group_id, user_id, role) values (v, auth.uid(), 'owner');
  return v;
end $$;

-- Solo el owner invita. Re-invitar a alguien que rechazó vuelve a dejar la invitación en pending.
create or replace function invite_to_group(p_group uuid, p_email text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_email text := lower(trim(p_email)); v uuid;
begin
  if not exists (select 1 from group_members where group_id = p_group and user_id = auth.uid()
                 and role = 'owner' and left_at is null) then raise exception 'not_group_owner'; end if;
  if v_email = '' or v_email not like '%_@_%._%' then raise exception 'invalid_email'; end if;
  if exists (select 1 from group_members m join auth.users u on u.id = m.user_id
             where m.group_id = p_group and m.left_at is null and lower(u.email) = v_email) then
    raise exception 'already_member'; end if;
  insert into group_invites (group_id, email, invited_by) values (p_group, v_email, auth.uid())
  on conflict (group_id, email) do update set status = 'pending', invited_by = auth.uid(), created_at = now()
  returning id into v;
  return v;
end $$;

-- La persona invitada necesita ver el nombre del grupo sin ser miembro todavía.
create or replace function my_pending_invites()
returns table (invite_id uuid, group_id uuid, group_name text, invited_by_name text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select i.id, i.group_id, g.name, p.display_name, i.created_at
  from group_invites i
  join groups g on g.id = i.group_id
  left join profiles p on p.id = i.invited_by
  where i.status = 'pending' and i.email = lower(auth.jwt() ->> 'email')
  order by i.created_at desc $$;

create or replace function accept_invite(p_invite uuid) returns void
language plpgsql security definer set search_path = public as $$
declare i group_invites;
begin
  select * into i from group_invites where id = p_invite and status = 'pending'
    and email = lower(auth.jwt() ->> 'email');
  if not found then raise exception 'invite_not_found'; end if;
  insert into group_members (group_id, user_id) values (i.group_id, auth.uid())
  on conflict (group_id, user_id) do update set left_at = null, joined_at = now();   -- también reingresa a quien salió
  update group_invites set status = 'accepted' where id = i.id;
end $$;

create or replace function decline_invite(p_invite uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update group_invites set status = 'declined'
   where id = p_invite and status = 'pending' and email = lower(auth.jwt() ->> 'email');
  if not found then raise exception 'invite_not_found'; end if;
end $$;

-- Saldo neto por integrante: positivo = le deben, negativo = debe. La suma del grupo es siempre 0.
-- Solo cuentan liquidaciones CONFIRMADAS.
create view group_balances with (security_invoker = true) as
select m.group_id, m.user_id,
  coalesce((select sum(amount) from group_expenses e where e.group_id = m.group_id and e.paid_by = m.user_id), 0)
  - coalesce((select sum(share) from group_expense_splits s where s.group_id = m.group_id and s.user_id = m.user_id), 0)
  + coalesce((select sum(amount) from group_settlements t where t.group_id = m.group_id and t.status = 'confirmed' and t.from_user = m.user_id), 0)
  - coalesce((select sum(amount) from group_settlements t where t.group_id = m.group_id and t.status = 'confirmed' and t.to_user = m.user_id), 0) as net
from group_members m;

-- Salir conserva el historial. Requiere estar a mano (saldo 0) y sin liquidaciones pendientes.
create or replace function leave_group(p_group uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_role text; v_net numeric;
begin
  select role into v_role from group_members where group_id = p_group and user_id = auth.uid() and left_at is null;
  if not found then raise exception 'not_a_member'; end if;
  if v_role = 'owner' and exists (select 1 from group_members where group_id = p_group
                                  and user_id <> auth.uid() and left_at is null) then
    raise exception 'owner_cannot_leave'; end if;           -- el owner borra el grupo, no lo abandona
  select net into v_net from group_balances where group_id = p_group and user_id = auth.uid();
  if coalesce(v_net, 0) <> 0 then raise exception 'balance_not_settled'; end if;
  if exists (select 1 from group_settlements where group_id = p_group and status = 'pending'
             and auth.uid() in (from_user, to_user)) then raise exception 'pending_settlement'; end if;
  update group_members set left_at = now() where group_id = p_group and user_id = auth.uid();
end $$;

-- ───────── gastos: crear / editar con sus splits, atómico y validado ─────────
-- p_splits = [{"user_id":"<uuid>","share":123.45}, ...]; la suma debe ser EXACTAMENTE p_amount.
-- p_expense null = crear; con id = editar (solo el creador).
create or replace function save_group_expense(
  p_group uuid, p_paid_by uuid, p_amount numeric, p_description text, p_occurred_on date,
  p_splits jsonb, p_expense uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_n int; v_distinct int; v_sum numeric; v_bad int;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if not is_group_member(p_group) then raise exception 'not_a_member'; end if;
  if not exists (select 1 from group_members where group_id = p_group and user_id = p_paid_by and left_at is null)
    then raise exception 'payer_not_member'; end if;
  if p_amount is null or p_amount <= 0 or p_amount <> round(p_amount, 2) then raise exception 'invalid_amount'; end if;
  if p_splits is null or jsonb_typeof(p_splits) <> 'array' or jsonb_array_length(p_splits) = 0
    then raise exception 'invalid_splits'; end if;

  with s as (select (e->>'user_id')::uuid as uid, (e->>'share')::numeric as share from jsonb_array_elements(p_splits) e)
  select count(*), count(distinct uid), coalesce(sum(share), 0),
         count(*) filter (where share is null or share < 0 or share <> round(share, 2)
                          or not exists (select 1 from group_members m
                                         where m.group_id = p_group and m.user_id = s.uid and m.left_at is null))
    into v_n, v_distinct, v_sum, v_bad from s;
  if v_bad > 0 or v_n <> v_distinct then raise exception 'invalid_splits'; end if;
  if v_sum <> p_amount then raise exception 'splits_must_equal_amount'; end if;

  if p_expense is null then
    insert into group_expenses (group_id, paid_by, amount, description, occurred_on, created_by)
    values (p_group, p_paid_by, p_amount, p_description, p_occurred_on, auth.uid())
    returning id into v_id;
  else
    update group_expenses set paid_by = p_paid_by, amount = p_amount,
           description = p_description, occurred_on = p_occurred_on
     where id = p_expense and group_id = p_group and created_by = auth.uid()
     returning id into v_id;
    if v_id is null then raise exception 'expense_not_found_or_not_yours'; end if;
    delete from group_expense_splits where expense_id = v_id;
  end if;

  insert into group_expense_splits (expense_id, group_id, user_id, share)
  select v_id, p_group, (e->>'user_id')::uuid, (e->>'share')::numeric from jsonb_array_elements(p_splits) e;
  return v_id;
end $$;

-- Cinturón y tirantes: aunque alguien tocara las tablas por otra vía, al COMMIT la suma debe cuadrar.
create or replace function check_expense_split_total() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_amount numeric; v_sum numeric;
begin
  if tg_table_name = 'group_expenses' then
    v_id := new.id;                                        -- solo dispara en insert/update
  elsif tg_op = 'DELETE' then
    v_id := old.expense_id;
  else
    v_id := new.expense_id;
  end if;
  select amount into v_amount from group_expenses where id = v_id;
  if not found then return null; end if;                    -- el gasto ya no existe (borrado en cascada)
  select coalesce(sum(share), 0) into v_sum from group_expense_splits where expense_id = v_id;
  if v_sum <> v_amount then raise exception 'splits_must_equal_amount'; end if;
  return null;
end $$;
create constraint trigger ge_split_total after insert or update on group_expenses
  deferrable initially deferred for each row execute function check_expense_split_total();
create constraint trigger gs_split_total after insert or update or delete on group_expense_splits
  deferrable initially deferred for each row execute function check_expense_split_total();

-- ───────── liquidaciones: la crea una de las dos partes, la confirma la OTRA ─────────
create or replace function create_group_settlement(
  p_group uuid, p_from uuid, p_to uuid, p_amount numeric, p_occurred_on date)
returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if not is_group_member(p_group) then raise exception 'not_a_member'; end if;
  if auth.uid() not in (p_from, p_to) then raise exception 'must_be_party'; end if;
  if p_from = p_to then raise exception 'same_person'; end if;
  if p_amount is null or p_amount <= 0 or p_amount <> round(p_amount, 2) then raise exception 'invalid_amount'; end if;
  if (select count(*) from group_members where group_id = p_group and left_at is null
      and user_id in (p_from, p_to)) <> 2 then raise exception 'party_not_member'; end if;
  insert into group_settlements (group_id, from_user, to_user, amount, occurred_on, created_by)
  values (p_group, p_from, p_to, p_amount, p_occurred_on, auth.uid()) returning id into v;
  return v;
end $$;

create or replace function confirm_group_settlement(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update group_settlements set status = 'confirmed', confirmed_at = now()
   where id = p_id and status = 'pending' and is_group_member(group_id)
     and created_by <> auth.uid() and auth.uid() in (from_user, to_user);   -- confirma quien NO la creó
  if not found then raise exception 'settlement_not_found_or_not_confirmable'; end if;
end $$;

-- ───────── perfiles: ver solo el nombre de quienes comparten grupo contigo ─────────
create policy profiles_group_read on profiles for select to authenticated
  using (exists (select 1 from group_members a join group_members b on a.group_id = b.group_id
                 where a.user_id = (select auth.uid()) and a.left_at is null and b.user_id = profiles.id));

-- ───────── permisos de ejecución: solo usuarios autenticados ─────────
revoke all on function create_group(text), invite_to_group(uuid, text), my_pending_invites(),
  accept_invite(uuid), decline_invite(uuid), leave_group(uuid),
  save_group_expense(uuid, uuid, numeric, text, date, jsonb, uuid),
  create_group_settlement(uuid, uuid, uuid, numeric, date), confirm_group_settlement(uuid),
  check_expense_split_total()
  from public, anon;
grant execute on function create_group(text), invite_to_group(uuid, text), my_pending_invites(),
  accept_invite(uuid), decline_invite(uuid), leave_group(uuid),
  save_group_expense(uuid, uuid, numeric, text, date, jsonb, uuid),
  create_group_settlement(uuid, uuid, uuid, numeric, date), confirm_group_settlement(uuid)
  to authenticated;

-- ──────────────── 0003_payments_fixes.sql ────────────────
-- FORTOURNAL · 0003_payments_fixes.sql  (correr después de 0001 y 0002)
-- Paso 2 de correcciones:
--   1. Los pagos mensuales/trimestrales/anuales ya no se "desplazan" (31 ene → 28 feb → 28 mar...).
--      Cada pago recuerda su día ancla y cada vencimiento se calcula contra él.
--   2. Borrar un pago (o su gasto) devuelve el vencimiento: el pago vuelve a "no pagado".
--   3. Pagar fuera de orden no choca con vencimientos que ya estaban pagados.
--   4. Índices que faltaban (transfers, abonos, ahorros, recordatorios).

-- ───────── 1. día ancla ─────────
alter table recurring_payments add column anchor_day int check (anchor_day between 1 and 31);
update recurring_payments set anchor_day = extract(day from due_date)::int;
alter table recurring_payments alter column anchor_day set not null;

-- Primer día del mes destino + min(ancla, último día de ese mes). Ej.: ancla 31 → feb 28/29, mar 31, abr 30.
create or replace function add_months_anchored(d date, n int, anchor int) returns date
language sql immutable as $$
  with m as (select (date_trunc('month', d) + make_interval(months => n))::date as first_day)
  select first_day + (least(anchor, extract(day from (first_day + interval '1 month' - interval '1 day'))::int) - 1)
  from m $$;

drop function if exists advance_payment_date(date, payment_freq, int);
create or replace function advance_payment_date(d date, f payment_freq, custom_days int, anchor int default null)
returns date language sql immutable as $$
  select case f
    when 'weekly'         then d + 7
    when 'monthly'        then add_months_anchored(d, 1,  coalesce(anchor, extract(day from d)::int))
    when 'every_3_months' then add_months_anchored(d, 3,  coalesce(anchor, extract(day from d)::int))
    when 'yearly'         then add_months_anchored(d, 12, coalesce(anchor, extract(day from d)::int))
    else d + custom_days end $$;

-- El ancla se fija al crear el pago y cambia solo cuando LA PERSONA mueve el vencimiento a mano
-- (p. ej. de "día 31" a "día 15"). Los avances/reversas automáticos no la tocan.
create or replace function recurring_payments_anchor() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.anchor_day := coalesce(new.anchor_day, extract(day from new.due_date)::int);
  elsif new.due_date is distinct from old.due_date
        and coalesce(current_setting('fortournal.moving_due_date', true), '') <> 'on' then
    new.anchor_day := extract(day from new.due_date)::int;
  end if;
  return new;
end $$;
create trigger recurring_payments_anchor before insert or update of due_date on recurring_payments
  for each row execute function recurring_payments_anchor();

-- ───────── 3. pagar (reescrita): salta vencimientos ya pagados y valida el monto ─────────
create or replace function mark_payment_paid(p_payment_id uuid, p_amount numeric, p_account_id uuid, p_paid_on date)
returns uuid language plpgsql as $$
declare p recurring_payments; v_txn uuid; v_next date;
begin
  select * into p from recurring_payments where id = p_payment_id and user_id = auth.uid() for update;
  if not found then raise exception 'payment_not_found'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'invalid_amount'; end if;
  insert into transactions (user_id, account_id, category_id, type, amount, occurred_on, description, source, source_id, source_date)
  values (auth.uid(), p_account_id, category_id_by_key('expense','monthly_bills'), 'expense', p_amount, p_paid_on, p.name, 'payment', p.id, p.due_date)
  returning id into v_txn;                                  -- el índice único rechaza pagar dos veces el mismo vencimiento
  insert into payment_history (user_id, payment_id, due_date, paid_on, amount, transaction_id)
  values (auth.uid(), p.id, p.due_date, p_paid_on, p_amount, v_txn);

  v_next := advance_payment_date(p.due_date, p.frequency, p.custom_interval_days, p.anchor_day);
  while exists (select 1 from payment_history h where h.payment_id = p.id and h.due_date = v_next) loop
    v_next := advance_payment_date(v_next, p.frequency, p.custom_interval_days, p.anchor_day);   -- ya estaba pagado: sigue
  end loop;
  perform set_config('fortournal.moving_due_date', 'on', true);
  update recurring_payments set due_date = v_next where id = p.id;
  perform set_config('fortournal.moving_due_date', 'off', true);
  return v_txn;
end $$;

-- ───────── 2. reversa: borrar el pago (o su gasto) devuelve el vencimiento ─────────
-- Se dispara al borrar la fila de historial, ya sea directo o porque se borró el gasto vinculado (cascade).
-- Solo retrocede, nunca adelanta: si quedan pagos posteriores, el vencimiento más antiguo sin pagar manda.
create or replace function revert_payment_due_date() returns trigger language plpgsql as $$
begin
  perform set_config('fortournal.moving_due_date', 'on', true);
  update recurring_payments set due_date = old.due_date
   where id = old.payment_id and user_id = old.user_id and due_date > old.due_date;
  perform set_config('fortournal.moving_due_date', 'off', true);
  return null;
end $$;
create trigger payment_history_revert after delete on payment_history
  for each row execute function revert_payment_due_date();

-- ───────── 4. índices que faltaban ─────────
create index transfers_from_idx on transfers (from_account_id);              -- account_balances suma por cuenta
create index transfers_to_idx on transfers (to_account_id);
create index debt_repayments_owed_idx on debt_repayments (money_owed_id);    -- money_owed_status agrupa por deuda
create index savings_contrib_goal_idx on savings_contributions (goal_id);    -- progreso de cada meta
create index recurring_payments_due_idx on recurring_payments (due_date)
  where is_active and not is_paused;                                          -- recordatorios diarios
