# GiST tests
#
# Test concurrency for unique indexes

setup
{
  CREATE TABLE t (
	id int4range NOT NULL
  );
  CREATE UNIQUE INDEX ON t USING gist (id);
}

teardown { DROP TABLE t; }

session s1
step s1rc	{ BEGIN ISOLATION LEVEL READ COMMITTED; }
step s1ins  { INSERT INTO t VALUES ('[1,2)'); }
step s1del  { DELETE FROM t WHERE id = '[1,2)'; }
step s1c	{ COMMIT; }
step s1r	{ ROLLBACK; }

session s2
step s2rc	{ BEGIN ISOLATION LEVEL READ COMMITTED; }
step s2ins  { INSERT INTO t VALUES ('[1,2)'); }
step s2c	{ COMMIT; }

# s2 inserts, finds the row s1 is deleting, and waits for s1.  s1 commits,
# so the row is gone and s2's insert succeeds.
permutation s1rc s1ins s1c s1rc s2rc s1del s2ins s1c s2c

# s2 inserts, finds the row s1 is deleting, and waits for s1.  s1 rolls
# back, so the row is still there and s2's insert fails.
permutation s1rc s1ins s1c s1rc s2rc s1del s2ins s1r s2c

# s2 inserts, finds the row s1 is inserting, and waits for s1.  s1 commits,
# so s2's insert fails.
permutation s1rc s2rc s1ins s2ins s1c s2c

# s2 inserts, finds the row s1 is inserting, and waits for s1.  s1 rolls
# back, so s2's insert succeeds.
permutation s1rc s2rc s1ins s2ins s1r s2c
