# CREATE UNIQUE INDEX CONCURRENTLY ... USING gist
#
# A unique GiST build validates the finished index with a second pass over
# the table.  In a concurrent build, each pass takes its own snapshot, so the
# second pass can see rows committed after the first.  Those rows have no
# index entry yet -- the index isn't ready for inserts -- and validate_index()
# adds them later.  The second pass must not treat them as corruption, and
# must still catch a duplicate among them.
#
# The injection point "gist-unique-before-validate" fires between the two
# passes.

setup
{
    CREATE EXTENSION injection_points;
    CREATE TABLE gist_cic (id int4range);
    INSERT INTO gist_cic VALUES ('[1,2)'), ('[3,4)');
}

teardown
{
    DROP TABLE gist_cic;
    DROP EXTENSION injection_points;
}

session s1
setup
{
    SELECT injection_points_set_local();
    SELECT injection_points_attach('gist-unique-before-validate', 'wait');
}
step cic { CREATE UNIQUE INDEX CONCURRENTLY gist_cic_uq ON gist_cic USING gist (id); }
step noop1 { }

session s2
step ins_new { INSERT INTO gist_cic VALUES ('[5,6)'); }
step ins_dup { INSERT INTO gist_cic VALUES ('[1,2)'); }
step wakeup {
    SELECT injection_points_detach('gist-unique-before-validate');
    SELECT injection_points_wakeup('gist-unique-before-validate');
}
step check {
    SELECT i.indisvalid, (SELECT count(*) FROM gist_cic) AS nrows
    FROM pg_index i WHERE i.indexrelid = 'gist_cic_uq'::regclass;
}

# A new, distinct row arrives between the passes: the build must succeed.
permutation cic ins_new wakeup noop1 check

# A duplicate arrives between the passes: the build must fail.
permutation cic ins_dup wakeup noop1 check
