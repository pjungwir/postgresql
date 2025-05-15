# RI Trigger test
#
# Test C-based referential integrity enforcement.
# Under REPEATABLE READ we need some snapshot trickery in C,
# or we would permit things that violate referential integrity.

setup
{
  CREATE TABLE parent (parent_id SERIAL NOT NULL PRIMARY KEY);
  CREATE TABLE child (
	child_id SERIAL NOT NULL PRIMARY KEY,
	parent_id INTEGER REFERENCES parent);
  INSERT INTO parent VALUES(1);
}

teardown { DROP TABLE parent, child; }

session s1
setup		{ BEGIN ISOLATION LEVEL REPEATABLE READ; }
step s1del	{ DELETE FROM parent WHERE parent_id = 1; }
step s1c	{ COMMIT; }

session s2
setup		{ BEGIN ISOLATION LEVEL REPEATABLE READ; }
step s2ins	{ INSERT INTO child VALUES (1, 1); }
step s2c	{ COMMIT; }

# Violates referential integrity unless we use an up-to-date crosscheck snapshot:
permutation s2ins s1del s2c s1c

# Raises a can't-serialize exception
# when the INSERT trigger does SELECT FOR KEY SHARE:
permutation s1del s2ins s1c s2c
