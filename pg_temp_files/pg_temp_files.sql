CREATE OR REPLACE VIEW pg_temp_files AS
WITH RECURSIVE
tablespace_dirs AS (
    SELECT
        dirname,
        'pg_tblspc/' || dirname || '/' AS path,
        1 AS depth
    FROM
        PG_LS_DIR('pg_tblspc/', TRUE, FALSE) AS dirname
    UNION ALL
    SELECT
        subdir,
        td.path || subdir || '/',
        td.depth + 1
    FROM
        tablespace_dirs AS td,
        PG_LS_DIR(td.path, TRUE, FALSE) AS subdir
    WHERE
        td.depth < 3
),
temp_dirs AS (
    SELECT
        td.path,
        ts.spcname AS tablespace
    FROM
        tablespace_dirs AS td
        INNER JOIN pg_tablespace AS ts ON (ts.oid = SUBSTRING(td.path FROM 'pg_tblspc/(\d+)')::INT)
    WHERE
        td.depth = 3
        AND
        td.dirname = 'pgsql_tmp'
    UNION ALL
    VALUES
    ('base/pgsql_tmp/', 'pg_default')
),
temp_files AS (
    SELECT
        SUBSTRING(filename FROM 'pgsql_tmp(\d+)')::INT AS pid,
        td.tablespace,
        PG_STAT_FILE(td.path || '/' || filename, TRUE) AS file
    FROM
        temp_dirs AS td,
        PG_LS_DIR(td.path, TRUE, FALSE) AS filename
)
SELECT
    pid,
    tablespace,
    COUNT(1) AS file_count,
    SUM((file).size)::BIGINT AS total_size,
    MAX((file).modification) AS last_modification
FROM
    temp_files
GROUP BY
    1, 2;
