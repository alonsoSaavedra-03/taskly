-- ============================================================================
-- TASKLY 1.0 — MIGRACIÓN INCREMENTAL: BLOQUEO ESTRICTO DE ESCRITURA PARA
-- ROL 'VIEWER' EN TAREAS DE PROYECTO (INCLUSO SI FUE EL CREADOR DE LA TAREA)
-- Archivo: 20261114020000_strict_project_task_write_access.sql
-- Segura e idempotente: NO elimina tablas ni datos existentes.
-- ============================================================================

-- 1. Actualizar has_task_read_access:
-- - Si la tarea es personal (project_id IS NULL): solo su creador (user_id = auth.uid()).
-- - Si la tarea pertenece a un proyecto (project_id IS NOT NULL): requiere acceso de lectura
--   vigente al proyecto (owner, editor o viewer).
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

-- 2. Actualizar has_task_write_access:
-- - Si la tarea es personal (project_id IS NULL): solo su creador (user_id = auth.uid()).
-- - Si la tarea pertenece a un proyecto (project_id IS NOT NULL): exige obligatoriamente
--   public.has_project_write_access(t.project_id) (rol 'owner' o 'editor').
--   Si el usuario tiene rol 'viewer' en el proyecto, NO puede modificar la tarea,
--   ni sus subtareas, ni sus asignaciones, aunque t.user_id = auth.uid().
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

-- Mantener alias has_task_access apuntando a has_task_read_access
create or replace function public.has_task_access(p_task_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select public.has_task_read_access(p_task_id);
$$;

-- 3. Actualizar políticas RLS de public.tasks para aplicar la misma regla estricta:
-- En tareas de proyecto (project_id IS NOT NULL), un 'viewer' jamás puede hacer UPDATE ni DELETE,
-- aunque haya sido originalmente el creador (user_id = auth.uid()).
drop policy if exists "tasks_select_own_or_project" on public.tasks;
create policy "tasks_select_own_or_project"
  on public.tasks for select
  to authenticated
  using (
    (project_id is null and user_id = auth.uid())
    or (project_id is not null and public.has_project_read_access(project_id))
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

-- 4. Reforzar el trigger enforce_task_integrity para validar también el proyecto anterior (OLD.project_id)
-- en caso de UPDATE, impidiendo que un 'viewer' desvincule una tarea del proyecto (poniendo project_id = null)
-- para recuperar permisos de edición sobre una tarea que él creó antes de ser degradado a 'viewer'.
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

    if old.project_id is not null and auth.uid() is not null then
      if not public.has_project_write_access(old.project_id) then
        raise exception 'Permiso denegado: un usuario con rol viewer no puede modificar ni desvincular tareas del proyecto';
      end if;
    end if;

    if old.user_id <> auth.uid() and new.project_id is distinct from old.project_id then
      raise exception 'Violación de integridad: solo el autor con permisos de edición o el propietario puede mover la tarea de proyecto';
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

-- 5. Garantizar privilegios de tabla para el rol 'authenticated' en las 9 tablas
-- (Las políticas RLS filtran fila por fila; PostgreSQL requiere además permiso de tabla para 'authenticated')
grant usage on schema public to anon, authenticated;

grant select, insert, update, delete on table
  public.profiles,
  public.user_preferences,
  public.categories,
  public.projects,
  public.project_members,
  public.tasks,
  public.subtasks,
  public.reminders,
  public.task_assignments
to authenticated;

