# INSERT ... ON CONFLICT DO NOTHING racing on a unique GiST index, and on a
# WITHOUT OVERLAPS key, which GiST enforces the same way
#
# GiST inserts an entry first and searches for conflicts afterwards.  So two
# sessions inserting the same key can both pass ON CONFLICT's pre-check, both
# insert their speculative tuples and index entries, and only then search, so
# that each finds the other's speculative tuple.  If both then backed out,
# both would retry from the start and could meet the same way forever.  The
# older transaction must wait for the younger instead, as the executor does
# for exclusion constraints (CEOUC_LIVELOCK_PREVENTING_WAIT).
#
# Three injection points hold the sessions: "exec-insert-before-insert-
# speculative" after the pre-check, "gist-unique-before-search" after the
# index insertion, and "gist-unique-partial-conflict" when a session decides
# to back out.  A session that backs out and retries comes back to the first
# one.  injection_points_wakeup() releases one waiter per call and fails if
# there is none, hence wake_all().

setup
{
    CREATE EXTENSION injection_points;
    CREATE TABLE gist_upsert (id int4range);
    CREATE UNIQUE INDEX gist_upsert_uq ON gist_upsert USING gist (id);
    CREATE TABLE gist_upsert_t (
        id int4range,
        valid_at daterange,
        PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
    );
    CREATE FUNCTION waiting_at(point text) RETURNS bigint LANGUAGE sql AS $$
        SELECT count(*) FROM pg_stat_activity WHERE wait_event = point
    $$;
    CREATE FUNCTION inserting() RETURNS bigint LANGUAGE sql AS $$
        SELECT count(*) FROM pg_stat_activity
        WHERE query LIKE '%INSERT INTO gist_upsert%' AND state = 'active'
          AND pid <> pg_backend_pid()
    $$;
    CREATE FUNCTION locked() RETURNS bigint LANGUAGE sql AS $$
        SELECT count(*) FROM pg_stat_activity
        WHERE query LIKE '%INSERT INTO gist_upsert%' AND wait_event_type = 'Lock'
    $$;
    -- Wait up to about 10s for the condition to hold.
    CREATE FUNCTION await(cond text) RETURNS void LANGUAGE plpgsql AS $$
    DECLARE ok bool;
    BEGIN
        FOR i IN 1..1000 LOOP
            PERFORM pg_stat_clear_snapshot();
            EXECUTE 'SELECT ' || cond INTO ok;
            EXIT WHEN ok;
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
            PERFORM await(format('waiting_at(%L) < %s', point, n));
            PERFORM pg_sleep(0.1);  -- let it give up its wait slot
        END LOOP;
    END $$;
}

teardown
{
    DROP TABLE gist_upsert, gist_upsert_t;
    DROP FUNCTION wake_all(text), await(text), locked(), inserting(),
        waiting_at(text);
    DROP EXTENSION injection_points;
}

session s1
step ins1 { INSERT INTO gist_upsert VALUES ('[1,2)') ON CONFLICT DO NOTHING; }
step ins1t {
    INSERT INTO gist_upsert_t VALUES ('[1,2)', '[2020-01-01,2021-01-01)')
    ON CONFLICT DO NOTHING;
}

session s2
step ins2 { INSERT INTO gist_upsert VALUES ('[1,2)') ON CONFLICT DO NOTHING; }
step ins2t {
    INSERT INTO gist_upsert_t VALUES ('[1,2)', '[2020-06-01,2021-06-01)')
    ON CONFLICT DO NOTHING;
}

session s3
step attach {
    SELECT injection_points_attach('exec-insert-before-insert-speculative', 'wait');
    SELECT injection_points_attach('gist-unique-before-search', 'wait');
    SELECT injection_points_attach('gist-unique-partial-conflict', 'wait');
}
# Both pass the pre-check, then both insert.
step wake_insert {
    SELECT await('waiting_at(''exec-insert-before-insert-speculative'') = 2');
    SELECT wake_all('exec-insert-before-insert-speculative');
}
# Both search, with the other's speculative tuple already in the index.
step wake_search {
    SELECT await('waiting_at(''gist-unique-before-search'') = 2');
    SELECT wake_all('gist-unique-before-search');
}
# How many decide to back out?  The other one waits for it.
step conflicted {
    SELECT await('waiting_at(''gist-unique-partial-conflict'') + locked() = 2');
    SELECT waiting_at('gist-unique-partial-conflict') AS backing_out,
           locked() AS waiting;
}
# Let them go on, until both have finished or come back to retry.
step wake_conflict {
    SELECT wake_all('gist-unique-partial-conflict');
    SELECT await('inserting() = 0 OR waiting_at(''exec-insert-before-insert-speculative'') = 2');
    SELECT waiting_at('exec-insert-before-insert-speculative') AS retrying;
}
step detach_wake {
    SELECT injection_points_detach('exec-insert-before-insert-speculative');
    SELECT injection_points_detach('gist-unique-before-search');
    SELECT injection_points_detach('gist-unique-partial-conflict');
    SELECT wake_all('exec-insert-before-insert-speculative');
}
step result { SELECT * FROM gist_upsert; }
step result_t { SELECT * FROM gist_upsert_t; }

permutation attach ins1 ins2 wake_insert wake_search conflicted wake_conflict detach_wake result
permutation attach ins1t ins2t wake_insert wake_search conflicted wake_conflict detach_wake result_t
