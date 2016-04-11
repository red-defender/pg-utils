CREATE OR REPLACE VIEW pg_locks_tree AS
WITH RECURSIVE
plain_locks AS (
    SELECT
        l.locktype AS lock_type,
        COALESCE(
            l.relation::TEXT || '.' || l.page::TEXT || '.' || l.tuple::TEXT,
            l.relation::TEXT || '.' || l.page::TEXT,
            l.relation::TEXT,
            l.transactionid::TEXT,
            l.virtualxid,
            CASE
                WHEN l.locktype = 'advisory' AND l.objsubid = 1 THEN ((l.classid::BIGINT << 32) | l.objid::BIGINT)::TEXT
                WHEN l.locktype = 'advisory' AND l.objsubid = 2 THEN l.classid::TEXT || '.' || l.objid::TEXT
                ELSE l.classid::TEXT || '.' || l.objid::TEXT || '.' || l.objsubid::TEXT
            END,
            l.classid::TEXT || '.' || l.objid::TEXT,
            l.classid::TEXT,
            l.database::TEXT
        ) AS locked_object,
        COALESCE(l.relation, CASE WHEN l.locktype = 'advisory' THEN NULL ELSE l.classid END)::REGCLASS AS relation,
        l.pid,
        l.virtualtransaction AS virtual_xid,
        l.mode,
        l.granted,
        a.state,
        a.waiting,
        a.query,
        a.usename AS username,
        a.query_start,
        a.xact_start
    FROM
        pg_locks AS l
        INNER JOIN pg_stat_activity AS a ON (a.pid = l.pid)
),
direct_links AS (
    SELECT
        l.pid AS locking_pid,
        l.lock_type,
        l.locked_object,
        w.pid AS waiting_pid
    FROM
        plain_locks AS l
        INNER JOIN plain_locks AS w ON (
            w.lock_type = l.lock_type
            AND
            w.locked_object = l.locked_object
            AND
            l.granted
            AND
            NOT w.granted
        )
),
lock_links AS (
    SELECT
        l.*,
        EXISTS (SELECT 1 FROM direct_links AS w WHERE w.locking_pid = l.waiting_pid) AS has_children
    FROM
        direct_links AS l
),
locks_tree AS (
    SELECT
        pl.*,
        LPAD((ROW_NUMBER() OVER (ORDER BY pl.pid, pl.lock_type, pl.locked_object))::TEXT, 3, '0') AS sort,
        1 AS depth
    FROM
        plain_locks AS pl
    WHERE
        NOT pl.waiting
        AND
        EXISTS (
            SELECT
                1
            FROM
                lock_links AS ll
            WHERE
                ll.locking_pid = pl.pid
                AND
                ll.lock_type = pl.lock_type
                AND
                ll.locked_object = pl.locked_object
        )
    UNION ALL
    SELECT
        pl.*,
        lt.sort || LPAD((ROW_NUMBER() OVER (ORDER BY pl.pid, pl.lock_type, pl.locked_object))::TEXT, 3, '0') AS sort,
        lt.depth + 1 AS depth
    FROM
        locks_tree AS lt
        INNER JOIN lock_links ON (
            lock_links.locking_pid = lt.pid
            AND
            lock_links.lock_type = lt.lock_type
            AND
            lock_links.locked_object = lt.locked_object
        )
        INNER JOIN plain_locks AS pl ON (pl.pid = lock_links.waiting_pid)
    WHERE
        (
            pl.lock_type = lt.lock_type
            AND
            pl.locked_object = lt.locked_object
            AND
            NOT lock_links.has_children
        )
        OR
        EXISTS (
            SELECT
                1
            FROM
                lock_links AS ll
            WHERE
                ll.locking_pid = pl.pid
                AND
                ll.lock_type = pl.lock_type
                AND
                ll.locked_object = pl.locked_object
        )
)
SELECT
    LPAD('=>', depth * 2, ' ') AS tree,
    pid,
    lock_type,
    locked_object,
    relation,
    virtual_xid,
    mode,
    state,
    username,
    query_start,
    xact_start,
    query
FROM
    locks_tree
ORDER BY
    sort;