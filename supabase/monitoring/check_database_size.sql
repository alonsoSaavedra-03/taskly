-- ============================================================================
-- TASKLY 1.0 — MONITOREO DE CUOTA SUPABASE FREE (500 MB POSTGRESQL)
-- Consulta de SOLO LECTURA para vigilar el tamaño real de la base de datos,
-- tablas, índices y generar alertas preventivas a los 300 MB y 400 MB.
-- No modifica ni elimina datos personales.
-- ============================================================================

-- 1. Tamaño total de la base de datos y estado frente a la cuota de 500 MB
SELECT
  current_database() AS base_de_datos,
  pg_size_pretty(pg_database_size(current_database())) AS tamano_total,
  ROUND((pg_database_size(current_database())::numeric / (1024 * 1024)), 2) AS tamano_mb,
  500.00 AS limite_free_mb,
  ROUND(((pg_database_size(current_database())::numeric / (500.0 * 1024 * 1024)) * 100), 2) AS porcentaje_usado,
  CASE
    WHEN pg_database_size(current_database()) >= 400 * 1024 * 1024 THEN
      'CRITICO (>= 400 MB): Ejecutar limpieza voluntaria de recordatorios antiguos y tareas archivadas antes de alcanzar 500 MB.'
    WHEN pg_database_size(current_database()) >= 300 * 1024 * 1024 THEN
      'ALERTA (>= 300 MB): Revisar crecimiento de tablas/indices y aplicar politica de retencion de notificaciones leidas.'
    ELSE
      'OK (< 300 MB): Uso saludable dentro del limite de Supabase Free.'
  END AS estado_y_recomendacion;

-- 2. Tamaño detallado por tabla e índices en el esquema public (9 tablas de Taskly)
SELECT
  c.relname AS tabla,
  COALESCE(s.n_live_tup, 0) AS filas_estimadas,
  ROUND((pg_table_size(c.oid)::numeric / (1024 * 1024)), 3) AS datos_mb,
  ROUND((pg_indexes_size(c.oid)::numeric / (1024 * 1024)), 3) AS indices_mb,
  ROUND((pg_total_relation_size(c.oid)::numeric / (1024 * 1024)), 3) AS total_mb,
  pg_size_pretty(pg_total_relation_size(c.oid)) AS total_legible
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
ORDER BY pg_total_relation_size(c.oid) DESC;

-- 3. Tamaño individual de índices para detectar índices redundantes o inflados
SELECT
  schemaname AS esquema,
  relname AS tabla,
  indexrelname AS indice,
  pg_size_pretty(pg_relation_size(indexrelid)) AS tamano_indice,
  idx_scan AS lecturas_indice
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;

-- 4. Diagnóstico de candidatos para retención manual (SOLO LECTURA, sin borrar nada)
SELECT
  (SELECT COUNT(*) FROM public.reminders WHERE is_read = true AND created_at < NOW() - INTERVAL '30 days') AS recordatorios_leidos_mayores_30d,
  (SELECT COUNT(*) FROM public.tasks WHERE status = 'completada' AND completed_at < NOW() - INTERVAL '180 days') AS tareas_completadas_mayores_180d;
