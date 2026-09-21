\set ON_ERROR_STOP on

SHOW server_version;

SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
WHERE NOT datistemplate
ORDER BY datname;

SELECT extname, extversion
FROM pg_extension
WHERE extname IN ('vector', 'vchord', 'vectors')
ORDER BY extname;

SELECT indexname, indexdef
FROM pg_indexes
WHERE indexname IN ('clip_index', 'face_index')
ORDER BY indexname;
