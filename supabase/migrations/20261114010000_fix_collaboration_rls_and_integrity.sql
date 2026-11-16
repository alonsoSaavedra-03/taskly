-- ============================================================================
-- TASKLY 1.0 — MIGRACIÓN INCREMENTAL: CORRECCIÓN DE RLS DE COLABORACIÓN
-- Y RESTRICCIONES DE INTEGRIDAD ENTRE PROPIETARIOS, PROYECTOS Y CATEGORÍAS
-- Archivo: 20261114010000_fix_collaboration_rls_and_integrity.sql
-- Segura e idempotente: NO elimina tablas ni datos existentes.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. FUNCIONES DE AUTORIZACIÓN POR ROL (Lectura vs Escritura en Proyectos/Tareas)
-- ----------------------------------------------------------------------------

-- Lectura en proyecto: propietario o miembro con rol ('owner', 'editor', 'viewer')
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

-- Escritura en proyecto: EXCLUSIVAMENTE propietario o miembro con rol ('owner', 'editor').
-- El rol 'viewer' queda estrictamente excluido de operaciones de escritura.
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

-- Mantener has_project_access como alias de lectura para compatibilidad
create or replace function public.has_project_access(p_project_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select public.has_project_read_access(p_project_id);
$$;

-- Lectura en tarea: tarea personal propia o tarea de proyecto con acceso de lectura vigente
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

-- Escritura en tarea:
-- - Si es tarea personal (project_id is null): solo su creador (t.user_id = auth.uid()).
-- - Si pertenece a un proyecto (project_id is not null): exige has_project_write_access(t.project_id).
--   Un usuario con rol 'viewer' NO tiene permiso de escritura sobre tareas del proyecto, aunque haya sido su creador.
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

-- Actualizar has_task_access para reflejar lectura
create or replace function public.has_task_access(p_task_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select public.has_task_read_access(p_task_id);
$$;

-- Comprobar si una categoría pertenece a un usuario válido para la tarea/proyecto
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

-- Comprobar si dos usuarios comparten algún proyecto (para visibilidad de perfiles en colaboración)
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

grant execute on function public.has_project_read_access(uuid) to authenticated;
grant execute on function public.has_project_write_access(uuid) to authenticated;
grant execute on function public.has_task_read_access(uuid) to authenticated;
grant execute on function public.has_task_write_access(uuid) to authenticated;
grant execute on function public.is_valid_category_for_owner(uuid, uuid, uuid) to authenticated;
grant execute on function public.shares_project_with(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 2. TRIGGERS DE INTEGRIDAD ENTRE PROPIETARIOS, PROYECTOS, CATEGORÍAS Y TAREAS
-- ----------------------------------------------------------------------------

-- 2.1 Integridad en projects: la categoría asociada (si existe) debe pertenecer al owner_id del proyecto
create or replace function public.enforce_project_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.owner_id <> old.owner_id then
    raise exception 'No se permite transferir el owner_id del proyecto directamente';
  end if;

  if new.category_id is not null then
    if not exists (
      select 1 from public.categories c
      where c.id = new.category_id
        and c.user_id = new.owner_id
    ) then
      raise exception 'Violación de integridad: la categoría asignada al proyecto no pertenece al propietario del proyecto';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_project_integrity on public.projects;
create trigger trg_enforce_project_integrity
  before insert or update on public.projects
  for each row execute function public.enforce_project_integrity();

-- 2.2 Integridad en tasks:
-- - La categoría debe pertenecer al creador de la tarea o al propietario del proyecto.
-- - Si la tarea pertenece a un proyecto, quien inserta/edita debe tener permiso de escritura ('owner' o 'editor').
-- - Un colaborador ('editor') NO puede cambiar el user_id (propietario creador) de una tarea existente.
create or replace function public.enforce_task_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.user_id <> old.user_id then
      raise exception 'Violación de integridad: no se permite alterar el propietario creador (user_id) de la tarea';
    end if;

    if old.user_id <> auth.uid() and new.project_id is distinct from old.project_id then
      raise exception 'Violación de integridad: solo el autor o propietario puede mover la tarea de proyecto';
    end if;
  end if;

  if new.project_id is not null and auth.uid() is not null then
    if not public.has_project_write_access(new.project_id) then
      raise exception 'Permiso denegado: se requiere rol owner o editor en el proyecto para escribir tareas';
    end if;
  end if;

  if new.category_id is not null then
    if not public.is_valid_category_for_owner(new.category_id, new.user_id, new.project_id) then
      raise exception 'Violación de integridad: la categoría no pertenece al usuario ni al propietario del proyecto';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_task_integrity on public.tasks;
create trigger trg_enforce_task_integrity
  before insert or update on public.tasks
  for each row execute function public.enforce_task_integrity();

-- 2.3 Integridad en task_assignments:
-- Si se especifica user_id en la asignación y la tarea pertenece a un proyecto,
-- el usuario asignado debe ser propietario/miembro del proyecto o el creador de la tarea.
create or replace function public.enforce_task_assignment_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task_owner uuid;
  v_project_id uuid;
begin
  select t.user_id, t.project_id
    into v_task_owner, v_project_id
    from public.tasks t
   where t.id = new.task_id;

  if v_task_owner is null then
    raise exception 'La tarea especificada no existe';
  end if;

  if new.user_id is not null then
    if v_project_id is null and new.user_id <> v_task_owner then
      raise exception 'Violación de integridad: en tareas personales sin proyecto solo puede asignarse al propietario';
    end if;

    if v_project_id is not null then
      if not exists (
        select 1 from public.projects p where p.id = v_project_id and p.owner_id = new.user_id
      ) and not exists (
        select 1 from public.project_members pm where pm.project_id = v_project_id and pm.user_id = new.user_id
      ) and new.user_id <> v_task_owner then
        raise exception 'Violación de integridad: el usuario asignado no es miembro del proyecto';
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_task_assignment_integrity on public.task_assignments;
create trigger trg_enforce_task_assignment_integrity
  before insert or update on public.task_assignments
  for each row execute function public.enforce_task_assignment_integrity();

-- ----------------------------------------------------------------------------
-- 3. REEMPLAZO DE POLÍTICAS RLS CON SEPARACIÓN ESTRICTA VIEWER vs EDITOR/OWNER
-- ----------------------------------------------------------------------------

-- 3.1 Perfiles: propio o miembros que comparten proyecto
drop policy if exists "profiles_select_own_or_shared" on public.profiles;
create policy "profiles_select_own_or_shared"
  on public.profiles for select
  to authenticated
  using (id = auth.uid() or public.shares_project_with(id));

-- 3.2 Proyectos: el propietario gestiona el proyecto; la categoría debe pertenecerle
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

-- 3.3 Miembros de proyecto: lectura para miembros, escritura exclusiva para el propietario del proyecto
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

-- 3.4 Tareas (tasks):
-- SELECT: autor o cualquier miembro del proyecto ('owner', 'editor', 'viewer')
-- INSERT: autor (user_id = auth.uid()), con permiso de escritura en el proyecto si project_id no es nulo, y categoría válida
-- UPDATE: autor o miembro con rol ('owner', 'editor') en el proyecto (EXCLUYE 'viewer')
-- DELETE: autor o propietario del proyecto (EXCLUYE 'viewer')
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

-- 3.5 Subtareas (subtasks):
-- Separación explícita entre lectura (has_task_read_access) y escritura (has_task_write_access)
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

-- 3.6 Recordatorios (reminders):
-- Cada usuario gestiona únicamente sus propios recordatorios y solo puede vincularlos
-- a tareas a las que realmente tenga acceso de lectura (impide referenciar task_id ajenos).
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

-- 3.7 Asignaciones de tareas (task_assignments):
-- Lectura: quienes pueden leer la tarea o el usuario asignado.
-- Escritura (INSERT/UPDATE/DELETE): exclusivamente quienes tienen permiso de escritura en la tarea
-- (creador, project owner o project editor; NUNCA viewer) y assigned_by debe ser auth.uid() o null.
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
