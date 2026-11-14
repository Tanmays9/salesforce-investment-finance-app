"""Bounded, non-writing source lock for the final migration window."""
import time
import os
import datetime as dt
import psycopg
from psycopg import sql
from prepare import PRIVATE,dump

release=PRIVATE/'release-neon-freeze.flag'
if release.exists():raise SystemExit('Remove the previous release flag before a new freeze')
with psycopg.connect((PRIVATE/'neon-url.tmp').read_text(encoding='utf-8').strip()) as conn:
    conn.execute("SET LOCAL lock_timeout = '10s'")
    conn.execute("SET LOCAL idle_in_transaction_session_timeout = '0'")
    tables=conn.execute("SELECT table_schema,table_name FROM information_schema.tables WHERE table_schema IN ('market','portfolio','planning','analytics','ops') AND table_type='BASE TABLE' ORDER BY 1,2").fetchall()
    identifiers=sql.SQL(',').join(sql.Identifier(s,t) for s,t in tables)
    conn.execute(sql.SQL('LOCK TABLE {} IN SHARE MODE').format(identifiers))
    print('Neon source writes frozen for',len(tables),'tables; no rows changed',flush=True)
    deadline=time.monotonic()+1800
    try:
        while not release.exists() and time.monotonic()<deadline:
            count=conn.execute("SELECT count(*) FROM pg_locks WHERE pid=pg_backend_pid() AND mode='ShareLock' AND granted").fetchone()[0]
            dump(PRIVATE/'freeze-state.json',{'active':True,'pid':os.getpid(),'lockedTables':count,'heartbeatAt':dt.datetime.now(dt.timezone.utc).isoformat()})
            for _ in range(10):
                if release.exists():break
                time.sleep(2)
    finally:
        conn.rollback()
        dump(PRIVATE/'freeze-state.json',{'active':False,'heartbeatAt':dt.datetime.now(dt.timezone.utc).isoformat()})
print('Neon source locks released',flush=True)
