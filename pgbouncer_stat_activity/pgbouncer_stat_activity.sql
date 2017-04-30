-- Lowest compatible version: PostgreSQL 9, pgBouncer 1.6 (see comments lower).
CREATE OR REPLACE VIEW pgbouncer_stat_activity AS
WITH
servers AS (
    SELECT
        remote_pid AS server_pid,
        ptr AS server_ptr,
        link AS server_link
    FROM
        dblink('port=6432 user=pgbouncer', 'SHOW SERVERS') AS servers (
            type TEXT,
            "user" TEXT,
            database TEXT,
            state TEXT,
            addr TEXT,
            port INT,
            local_addr TEXT,
            local_port INT,
            connect_time TIMESTAMPTZ,
            request_time TIMESTAMPTZ,
            ptr TEXT,
            link TEXT,
            remote_pid INT,
            tls TEXT -- Remove this field for pgBouncer 1.6.
        )
),
clients AS (
    SELECT
        addr AS client_addr,
        port AS client_port,
        remote_pid AS client_pid,
        ptr AS client_ptr,
        link AS client_link
    FROM
        dblink('port=6432 user=pgbouncer', 'SHOW CLIENTS') AS clients (
            type TEXT,
            "user" TEXT,
            database TEXT,
            state TEXT,
            addr TEXT,
            port INT,
            local_addr TEXT,
            local_port INT,
            connect_time TIMESTAMPTZ,
            request_time TIMESTAMPTZ,
            ptr TEXT,
            link TEXT,
            remote_pid INT,
            tls TEXT -- Remove this field for pgBouncer 1.6.
        )
)
SELECT
    a.datid,
    a.datname,
    a.pid,
    a.usesysid,
    a.usename,
    a.application_name,
    NULLIF(c.client_addr, 'unix')::INET AS client_addr,
    a.client_hostname,
    CASE WHEN c.client_addr = 'unix' THEN c.client_pid ELSE c.client_port END AS client_port,
    a.backend_start,
    a.xact_start,
    a.query_start,
    a.state_change,
    a.wait_event_type, -- Remove this field for PostgreSQL 9.5 and lower.
    a.wait_event, -- Remove this field for PostgreSQL 9.5 and lower.
    --a.waiting, -- Enable this field for PostgreSQL 9.5 and lower.
    a.state,
    a.backend_xid, -- Remove this field for PostgreSQL 9.3 and lower.
    a.backend_xmin, -- Remove this field for PostgreSQL 9.3 and lower.
    a.query
FROM
    pg_catalog.pg_stat_activity AS a
    INNER JOIN servers AS s ON (s.server_pid = a.pid)
    INNER JOIN clients AS c ON (c.client_ptr = s.server_link AND c.client_link = s.server_ptr);
