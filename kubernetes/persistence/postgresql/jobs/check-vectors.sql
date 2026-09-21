\set ON_ERROR_STOP on

SELECT current_database() AS database,
       e.extname,
       e.extversion,
       count(d.objid) AS extension_members
FROM pg_extension AS e
LEFT JOIN pg_depend AS d
  ON d.refobjid = e.oid
 AND d.deptype = 'e'
WHERE e.extname = 'vectors'
GROUP BY current_database(), e.extname, e.extversion;

SELECT n.nspname AS dependent_schema,
       c.relname AS dependent_relation,
       a.attname AS dependent_column,
       t.typname AS dependent_type
FROM pg_attribute AS a
JOIN pg_class AS c ON c.oid = a.attrelid
JOIN pg_namespace AS n ON n.oid = c.relnamespace
JOIN pg_type AS t ON t.oid = a.atttypid
JOIN pg_namespace AS tn ON tn.oid = t.typnamespace
WHERE a.attnum > 0
  AND NOT a.attisdropped
  AND tn.nspname = 'vectors'
ORDER BY n.nspname, c.relname, a.attnum;
