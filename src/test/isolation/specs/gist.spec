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
# step s1rr	{ BEGIN ISOLATION LEVEL REPEATABLE READ; }
# step s1ser	{ BEGIN ISOLATION LEVEL SERIALIZABLE; }
step s1ins  { INSERT INTO t VALUES ('[1,2)'); }
step s1del  { DELETE FROM t WHERE id = '[1,2)'; }
step s1c	{ COMMIT; }
step s1r	{ ROLLBACK; }

session s2
step s2rc	{ BEGIN ISOLATION LEVEL READ COMMITTED; }
# step s2rr	{ BEGIN ISOLATION LEVEL REPEATABLE READ; }
# step s2ser	{ BEGIN ISOLATION LEVEL SERIALIZABLE; }
step s2ins  { INSERT INTO t VALUES ('[1,2)'); }
step s2c	{ COMMIT; }

# s2 should wait for s1 to commit before trying to insert,
# then see that the deleted row is committed.
permutation s1rc s1ins s1c s1rc s2rc s1del s2ins s1c s2c

# s2 should wait for s1 to commit before trying to insert,
# then see that the deleted row is rolled back.
permutation s1rc s1ins s1c s1rc s2rc s1del s2ins s1r s2c

# s2 should wait for s1 to commit before trying to insert.
# then see that the row was committed.
permutation s1rc s2rc s1ins s2ins s1c s2c

# s2 should wait for s1 to commit before trying to insert.
# then see that the row was rolled back.
permutation s1rc s2rc s1ins s2ins s1r s2c
