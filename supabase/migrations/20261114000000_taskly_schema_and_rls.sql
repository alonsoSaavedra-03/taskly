-- ============================================================================
-- TASKLY 1.0 — ESQUEMA POSTGRESQL NORMALIZADO Y POLÍTICAS RLS (SUPABASE FREE)
-- Migración segura, idempotente y reproducible (sin pérdida de datos)
-- Entidades: profiles, user_preferences, categories, projects, project_members,
--            tasks, subtasks, reminders, task_assignments + Storage + Realtime
-- ============================================================================

create extension if not exists "pgcrypto";

-- Función utilitaria para actualizar automáticamente updated_at
create or replace function public.handle_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

-- ============================================================================
-- 1. TABLA: profiles (Información pública y editable del perfil del usuario)
-- ============================================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text not null default 'Usuario Taskly',
  role text not null default 'Miembro Personal',
  avatar_initials text not null default 'UT',
  avatar_url text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint profiles_full_name_len check (char_length(trim(full_name)) >= 1)
);

create index if not exists idx_profiles_email on public.profiles(email);

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.handle_updated_at();

-- ============================================================================
-- 2. TABLA: user_preferences (Tema, colores, tipografía, densidad, navegación y tutorial)
-- ============================================================================
create table if not exists public.user_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  theme text not null default 'dark' check (theme in ('dark', 'amoled', 'light', 'auto')),
  accent_color text not null default '#A5B4FC',
  border_radius text not null default 'standard' check (border_radius in ('sharp', 'standard', 'rounded')),
  card_density text not null default 'comfortable' check (card_density in ('compact', 'comfortable', 'spacious')),
  font_family text not null default 'Inter' check (font_family in ('Inter', 'Plus Jakarta Sans', 'JetBrains Mono')),
  font_scale text not null default 'normal' check (font_scale in ('small', 'normal', 'large')),
  nav_style text not null default 'classic' check (nav_style in ('classic', 'floating')),
  notifications_enabled boolean not null default true,
  sound_enabled boolean not null default true,
  default_reminder text not null default '30 min antes',
  tutorial_status text not null default 'not_started' check (tutorial_status in ('not_started', 'in_progress', 'completed', 'skipped')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

drop trigger if exists trg_user_preferences_updated_at on public.user_preferences;
create trigger trg_user_preferences_updated_at
  before update on public.user_preferences
  for each row execute function public.handle_updated_at();

-- ============================================================================
-- 3. TABLA: categories (Categorías personalizadas con nombre, color e icono Lucide)
-- ============================================================================
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  color text not null default '#818CF8',
  icon text not null default 'briefcase',
  is_default boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint categories_name_len check (char_length(trim(name)) between 1 and 60)
);

create index if not exists idx_categories_user_id on public.categories(user_id);

drop trigger if exists trg_categories_updated_at on public.categories;
create trigger trg_categories_updated_at
  before update on public.categories
  for each row execute function public.handle_updated_at();

-- ============================================================================
-- 4. TABLA: projects (Proyectos personales o compartidos)
-- ============================================================================
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  name text not null,
  description text not null default '',
  color text not null default '#A5B4FC',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint projects_name_len check (char_length(trim(name)) between 1 and 120)
);

create index if not exists idx_projects_owner_id on public.projects(owner_id);

drop trigger if exists trg_projects_updated_at on public.projects;
create trigger trg_projects_updated_at
  before update on public.projects
  for each row execute function public.handle_updated_at();

-- ============================================================================
-- 5. TABLA: project_members (Miembros, propietarios y permisos de proyectos)
-- ============================================================================
create table if not exists public.project_members (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'editor' check (role in ('owner', 'editor', 'viewer')),
  created_at timestamptz not null default timezone('utc', now()),
  unique (project_id, user_id)
);

create index if not exists idx_project_members_project_id on public.project_members(project_id);
create index if not exists idx_project_members_user_id on public.project_members(user_id);

-- ============================================================================
-- 6. TABLA: tasks (Tareas del usuario con estado, prioridad, fechas y recurrencia)
-- ============================================================================
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  project_id uuid references public.projects(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  title text not null,
  description text not null default '',
  status text not null default 'pendiente' check (status in ('pendiente', 'en_progreso', 'completada')),
  priority text not null default 'media' check (priority in ('baja', 'media', 'alta')),
  due_date date not null default current_date,
  due_time text not null default '12:00',
  recurrence text not null default 'Nunca' check (recurrence in ('Nunca', 'Diario', 'Semanal', 'Mensual')),
  reminder_label text not null default '30 min antes',
  assigned_to text[] not null default '{}',
  completed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint tasks_title_len check (char_length(trim(title)) between 1 and 240)
);

create index if not exists idx_tasks_user_due on public.tasks(user_id, due_date, status);
create index if not exists idx_tasks_category_id on public.tasks(category_id);
create index if not exists idx_tasks_project_id on public.tasks(project_id);

drop trigger if exists trg_tasks_updated_at on public.tasks;
create trigger trg_tasks_updated_at
  before update on public.tasks
  for each row execute function public.handle_updated_at();

-- ============================================================================
-- 7. TABLA: subtasks (Subtareas asociadas a tareas principales)
-- ============================================================================
create table if not exists public.subtasks (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  title text not null,
  is_completed boolean not null default false,
  position integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint subtasks_title_len check (char_length(trim(title)) between 1 and 200)
);

create index if not exists idx_subtasks_task_id on public.subtasks(task_id, position);

drop trigger if exists trg_subtasks_updated_at on public.subtasks;
create trigger trg_subtasks_updated_at
  before update on public.subtasks
  for each row execute function public.handle_updated_at();

-- ============================================================================
-- 8. TABLA: reminders (Recordatorios y notificaciones configurados por el usuario)
-- ============================================================================
create table if not exists public.reminders (
  id uuid primary key default gen_random_uuid(),
  task_id uuid references public.tasks(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null default 'reminder' check (type in ('reminder', 'overdue', 'shared', 'completed')),
  title text not null,
  message text not null,
  offset_label text not null default '30 min antes',
  remind_at timestamptz not null default timezone('utc', now()),
  is_sent boolean not null default false,
  is_read boolean not null default false,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_reminders_user_read on public.reminders(user_id, is_read, remind_at desc);
create index if not exists idx_reminders_task_id on public.reminders(task_id);

-- ============================================================================
-- 9. TABLA: task_assignments (Asignaciones de tareas a usuarios)
-- ============================================================================
create table if not exists public.task_assignments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  assignee_name text not null,
  assigned_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  unique (task_id, assignee_name)
);

create index if not exists idx_task_assignments_task_id on public.task_assignments(task_id);
create index if not exists idx_task_assignments_user_id on public.task_assignments(user_id);

-- ============================================================================
-- FUNCIONES SECURITY DEFINER (Evitan recursión en RLS y autoprovisionan cuentas)
-- ============================================================================
create or replace function public.is_project_owner(p_project_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.projects p
    where p.id = p_project_id
      and p.owner_id = auth.uid()
  );
$$;

create or replace function public.has_project_read_access(p_project_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.projects p
    where p.id = p_project_id
      and p.owner_id = auth.uid()
  ) or exists (
    select 1 from public.project_members pm
    where pm.project_id = p_project_id
      and pm.user_id = auth.uid()
      and pm.role in ('owner', 'editor', 'viewer')
  );
$$;

create or replace function public.has_project_write_access(p_project_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.projects p
    where p.id = p_project_id
      and p.owner_id = auth.uid()
  ) or exists (
    select 1 from public.project_members pm
    where pm.project_id = p_project_id
      and pm.user_id = auth.uid()
      and pm.role in ('owner', 'editor')
  );
$$;

create or replace function public.has_project_access(p_project_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select public.has_project_read_access(p_project_id);
$$;

create or replace function public.has_task_read_access(p_task_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.tasks t
    where t.id = p_task_id
      and (
        (t.project_id is null and t.user_id = auth.uid())
        or (t.project_id is not null and public.has_project_read_access(t.project_id))
      )
  );
$$;

create or replace function public.has_task_write_access(p_task_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.tasks t
    where t.id = p_task_id
      and (
        (t.project_id is null and t.user_id = auth.uid())
        or (t.project_id is not null and public.has_project_write_access(t.project_id))
      )
  );
$$;

create or replace function public.has_task_access(p_task_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select public.has_task_read_access(p_task_id);
$$;

create or replace function public.is_valid_category_for_owner(p_category_id uuid, p_owner_id uuid, p_project_id uuid default null)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select p_category_id is null or exists (
    select 1 from public.categories c
    where c.id = p_category_id
      and (
        c.user_id = p_owner_id
        or (
          p_project_id is not null and exists (
            select 1 from public.projects p
            where p.id = p_project_id
              and p.owner_id = c.user_id
          )
        )
      )
  );
$$;

create or replace function public.shares_project_with(p_other_user_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1
    from public.projects p
    left join public.project_members pm_me on pm_me.project_id = p.id and pm_me.user_id = auth.uid()
    left join public.project_members pm_other on pm_other.project_id = p.id and pm_other.user_id = p_other_user_id
    where (p.owner_id = auth.uid() or pm_me.user_id is not null)
      and (p.owner_id = p_other_user_id or pm_other.user_id is not null)
  );
$$;

-- Trigger automático al registrarse un usuario en Supabase Auth:
-- Crea su perfil, sus preferencias por defecto y sus 5 categorías base (0 tareas ficticias)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_initials text;
begin
  v_name := coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), split_part(new.email, '@', 1), 'Usuario Taskly');
  v_initials := upper(
    left(split_part(v_name, ' ', 1), 1) ||
    coalesce(nullif(left(split_part(v_name, ' ', 2), 1), ''), substring(split_part(v_name, ' ', 1) from 2 for 1), 'T')
  );

  insert into public.profiles (id, email, full_name, role, avatar_initials)
  values (
    new.id,
    coalesce(new.email, ''),
    v_name,
    coalesce(nullif(trim(new.raw_user_meta_data->>'role'), ''), 'Miembro Personal'),
    left(v_initials, 2)
  )
  on conflict (id) do nothing;

  insert into public.user_preferences (user_id, tutorial_status)
  values (new.id, 'not_started')
  on conflict (user_id) do nothing;

  if not exists (select 1 from public.categories c where c.user_id = new.id) then
    insert into public.categories (user_id, name, color, icon, is_default)
    values
      (new.id, 'Trabajo', '#818CF8', 'briefcase', true),
      (new.id, 'Personal', '#38BDF8', 'user', true),
      (new.id, 'Estudios', '#C084FC', 'book-open', true),
      (new.id, 'Salud', '#34D399', 'heart-pulse', true),
      (new.id, 'Proyectos', '#FBBF24', 'folder-kanban', true);
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Función RPC para que un usuario autenticado pueda eliminar su propia cuenta y todos sus datos personales
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'No autenticado';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

grant execute on function public.delete_own_account() to authenticated;
grant execute on function public.is_project_owner(uuid) to authenticated;
grant execute on function public.has_project_access(uuid) to authenticated;
grant execute on function public.has_task_access(uuid) to authenticated;

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) ESTRICTO E IDEMPOTENTE EN LAS 9 TABLAS
-- ============================================================================
alter table public.profiles enable row level security;
alter table public.user_preferences enable row level security;
alter table public.categories enable row level security;
alter table public.projects enable row level security;
alter table public.project_members enable row level security;
alter table public.tasks enable row level security;
alter table public.subtasks enable row level security;
alter table public.reminders enable row level security;
alter table public.task_assignments enable row level security;

-- 1. Políticas para profiles
drop policy if exists "profiles_select_own_or_shared" on public.profiles;
create policy "profiles_select_own_or_shared"
  on public.profiles for select
  to authenticated
  using (id = auth.uid());

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check (id = auth.uid());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists "profiles_delete_own" on public.profiles;
create policy "profiles_delete_own"
  on public.profiles for delete
  to authenticated
  using (id = auth.uid());

-- 2. Políticas para user_preferences
drop policy if exists "user_preferences_all_own" on public.user_preferences;
create policy "user_preferences_all_own"
  on public.user_preferences for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 3. Políticas para categories
drop policy if exists "categories_all_own" on public.categories;
create policy "categories_all_own"
  on public.categories for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 4. Políticas para projects
drop policy if exists "projects_select_member_or_owner" on public.projects;
create policy "projects_select_member_or_owner"
  on public.projects for select
  to authenticated
  using (owner_id = auth.uid() or public.has_project_read_access(id));

drop policy if exists "projects_insert_owner" on public.projects;
create policy "projects_insert_owner"
  on public.projects for insert
  to authenticated
  with check (
    owner_id = auth.uid()
    and public.is_valid_category_for_owner(category_id, auth.uid(), null)
  );

drop policy if exists "projects_update_owner" on public.projects;
create policy "projects_update_owner"
  on public.projects for update
  to authenticated
  using (owner_id = auth.uid())
  with check (
    owner_id = auth.uid()
    and public.is_valid_category_for_owner(category_id, auth.uid(), null)
  );

drop policy if exists "projects_delete_owner" on public.projects;
create policy "projects_delete_owner"
  on public.projects for delete
  to authenticated
  using (owner_id = auth.uid());

-- 5. Políticas para project_members (usa is_project_owner para evitar recursión)
drop policy if exists "project_members_select_accessible" on public.project_members;
create policy "project_members_select_accessible"
  on public.project_members for select
  to authenticated
  using (user_id = auth.uid() or public.has_project_read_access(project_id));

drop policy if exists "project_members_manage_owner" on public.project_members;
drop policy if exists "project_members_insert_owner" on public.project_members;
drop policy if exists "project_members_update_owner" on public.project_members;
drop policy if exists "project_members_delete_owner_or_self" on public.project_members;

create policy "project_members_insert_owner"
  on public.project_members for insert
  to authenticated
  with check (public.is_project_owner(project_id));

create policy "project_members_update_owner"
  on public.project_members for update
  to authenticated
  using (public.is_project_owner(project_id))
  with check (public.is_project_owner(project_id));

create policy "project_members_delete_owner_or_self"
  on public.project_members for delete
  to authenticated
  using (public.is_project_owner(project_id) or user_id = auth.uid());

-- 6. Políticas para tasks (diferencia estrictamente viewer de editor/owner)
drop policy if exists "tasks_select_own_or_project" on public.tasks;
create policy "tasks_select_own_or_project"
  on public.tasks for select
  to authenticated
  using (
    (project_id is null and user_id = auth.uid())
    or (project_id is not null and public.has_project_read_access(project_id))
  );

drop policy if exists "tasks_insert_own" on public.tasks;
create policy "tasks_insert_own"
  on public.tasks for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and (project_id is null or public.has_project_write_access(project_id))
    and public.is_valid_category_for_owner(category_id, user_id, project_id)
  );

drop policy if exists "tasks_update_own_or_project" on public.tasks;
create policy "tasks_update_own_or_project"
  on public.tasks for update
  to authenticated
  using (
    (project_id is null and user_id = auth.uid())
    or (project_id is not null and public.has_project_write_access(project_id))
  )
  with check (
    (
      (project_id is null and user_id = auth.uid())
      or (project_id is not null and public.has_project_write_access(project_id))
    )
    and public.is_valid_category_for_owner(category_id, user_id, project_id)
  );

drop policy if exists "tasks_delete_own" on public.tasks;
create policy "tasks_delete_own"
  on public.tasks for delete
  to authenticated
  using (
    (project_id is null and user_id = auth.uid())
    or (
      project_id is not null
      and (
        public.is_project_owner(project_id)
        or (user_id = auth.uid() and public.has_project_write_access(project_id))
      )
    )
  );

-- 7. Políticas para subtasks (SELECT con has_task_read_access, escritura con has_task_write_access)
drop policy if exists "subtasks_all_accessible_task" on public.subtasks;
drop policy if exists "subtasks_select_accessible" on public.subtasks;
drop policy if exists "subtasks_insert_writable" on public.subtasks;
drop policy if exists "subtasks_update_writable" on public.subtasks;
drop policy if exists "subtasks_delete_writable" on public.subtasks;

create policy "subtasks_select_accessible"
  on public.subtasks for select
  to authenticated
  using (public.has_task_read_access(task_id));

create policy "subtasks_insert_writable"
  on public.subtasks for insert
  to authenticated
  with check (public.has_task_write_access(task_id));

create policy "subtasks_update_writable"
  on public.subtasks for update
  to authenticated
  using (public.has_task_write_access(task_id))
  with check (public.has_task_write_access(task_id));

create policy "subtasks_delete_writable"
  on public.subtasks for delete
  to authenticated
  using (public.has_task_write_access(task_id));

-- 8. Políticas para reminders (valida propiedad y acceso real a task_id)
drop policy if exists "reminders_all_own" on public.reminders;
drop policy if exists "reminders_select_own" on public.reminders;
drop policy if exists "reminders_insert_own" on public.reminders;
drop policy if exists "reminders_update_own" on public.reminders;
drop policy if exists "reminders_delete_own" on public.reminders;

create policy "reminders_select_own"
  on public.reminders for select
  to authenticated
  using (user_id = auth.uid());

create policy "reminders_insert_own"
  on public.reminders for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and (task_id is null or public.has_task_read_access(task_id))
  );

create policy "reminders_update_own"
  on public.reminders for update
  to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and (task_id is null or public.has_task_read_access(task_id))
  );

create policy "reminders_delete_own"
  on public.reminders for delete
  to authenticated
  using (user_id = auth.uid());

-- 9. Políticas para task_assignments (SELECT lectura, INSERT/UPDATE/DELETE solo con permiso de escritura)
drop policy if exists "task_assignments_all_accessible_task" on public.task_assignments;
drop policy if exists "task_assignments_select_accessible" on public.task_assignments;
drop policy if exists "task_assignments_insert_writable" on public.task_assignments;
drop policy if exists "task_assignments_update_writable" on public.task_assignments;
drop policy if exists "task_assignments_delete_writable" on public.task_assignments;

create policy "task_assignments_select_accessible"
  on public.task_assignments for select
  to authenticated
  using (
    public.has_task_read_access(task_id)
    or user_id = auth.uid()
  );

create policy "task_assignments_insert_writable"
  on public.task_assignments for insert
  to authenticated
  with check (
    public.has_task_write_access(task_id)
    and (assigned_by is null or assigned_by = auth.uid())
  );

create policy "task_assignments_update_writable"
  on public.task_assignments for update
  to authenticated
  using (public.has_task_write_access(task_id))
  with check (
    public.has_task_write_access(task_id)
    and (assigned_by is null or assigned_by = auth.uid())
  );

create policy "task_assignments_delete_writable"
  on public.task_assignments for delete
  to authenticated
  using (public.has_task_write_access(task_id));

-- ============================================================================
-- CONFIGURACIÓN SEGURA DE SUPABASE REALTIME Y STORAGE (IDEMPOTENTE)
-- ============================================================================
alter table public.tasks replica identity full;
alter table public.subtasks replica identity full;
alter table public.categories replica identity full;
alter table public.reminders replica identity full;
alter table public.user_preferences replica identity full;
alter table public.projects replica identity full;

do $$
declare
  t text;
  tables_to_pub text[] := array['tasks', 'subtasks', 'categories', 'reminders', 'user_preferences', 'projects'];
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  foreach t in array tables_to_pub loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "avatars_user_upload" on storage.objects;
create policy "avatars_user_upload"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatars_user_delete" on storage.objects;
create policy "avatars_user_delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
