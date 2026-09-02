# Two plain INSERTs racing on a unique GiST index can deadlock
#
# GiST inserts an entry first and then searches for conflicts, the way
# exclusion constraints work.  So if two sessions insert the same key at the
# same instant, each can find the other's uncommitted entry and wait for it,
# and the deadlock detector has to abort one of them.  That one gets a
# deadlock error instead of a unique violation; the other goes on to insert.
#
# "gist-unique-before-search" holds each session after its index insertion,
# so both entries are in place before either searches.  s2's short
# deadlock_timeout makes it the one that notices the deadlock.

setup
{
    CREATE EXTENSION injection_points;
    CREATE TABLE gist_deadlock (id int4range);
    CREATE UNIQUE INDEX gist_deadlock_uq ON gist_deadlock USING gist (id);
    CREATE FUNCTION waiting_at(point text) RETURNS bigint LANGUAGE sql AS $$
        SELECT count(*) FROM pg_stat_activity WHERE wait_event = point
    $$;
    -- Wait up to about 10s for n sessions to stop at the point.
    CREATE FUNCTION await(point text, n int) RETURNS void LANGUAGE plpgsql AS $$
    BEGIN
        FOR i IN 1..1000 LOOP
            PERFORM pg_stat_clear_snapshot();
            EXIT WHEN waiting_at(point) = n;
            PERFORM pg_sleep(0.01);
        END LOOP;
    END $$;
    -- Wake every session waiting at the point, one at a time.
    CREATE FUNCTION wake_all(point text) RETURNS void LANGUAGE plpgsql AS $$
    DECLARE n bigint;
    BEGIN
        LOOP
            PERFORM pg_stat_clear_snapshot();
            n := waiting_at(point);
            EXIT WHEN n = 0;
            PERFORM injection_points_wakeup(point);
            PERFORM await(point, (n - 1)::int);
            PERFORM pg_sleep(0.1);  -- let it give up its wait slot
        END LOOP;
    END $$;
}

teardown
{
    DROP TABLE gist_deadlock;
    DROP FUNCTION wake_all(text), await(text, int), waiting_at(text);
    DROP EXTENSION injection_points;
}

session s1
setup { SET deadlock_timeout = '100s'; }
step ins1 { INSERT INTO gist_deadlock VALUES ('[1,2)'); }

session s2
setup { SET deadlock_timeout = '10ms'; }
step ins2 { INSERT INTO gist_deadlock VALUES ('[1,2)'); }

session s3
step attach {
    SELECT injection_points_attach('gist-unique-before-search', 'wait');
}
step wake {
    SELECT await('gist-unique-before-search', 2);
    SELECT injection_points_detach('gist-unique-before-search');
    SELECT wake_all('gist-unique-before-search');
}
step result { SELECT * FROM gist_deadlock; }

permutation attach ins1 ins2 wake result
