# RI Trigger test
#
# Test C-based temporal referential integrity enforcement.
# Under REPEATABLE READ we need some snapshot trickery in C,
# or we would permit things that violate referential integrity.

setup
{
  CREATE TABLE parent (
	id int4range NOT NULL,
	valid_at daterange NOT NULL,
	PRIMARY KEY (id, valid_at WITHOUT OVERLAPS));
  CREATE TABLE child (
	id int4range NOT NULL,
	valid_at daterange NOT NULL,
	parent_id int4range,
	FOREIGN KEY (parent_id, PERIOD valid_at) REFERENCES parent);
  INSERT INTO parent VALUES ('[1,2)', '[2020-01-01,2030-01-01)');
}

teardown { DROP TABLE parent, child; }

session s1
setup		{ BEGIN ISOLATION LEVEL REPEATABLE READ; }
step s1del	{ DELETE FROM parent WHERE id = '[1,2)'; }
step s1c	{ COMMIT; }

session s2
setup		{ BEGIN ISOLATION LEVEL REPEATABLE READ; }
step s2ins	{
  INSERT INTO child VALUES ('[1,2)', '[2020-01-01,2030-01-01)', '[1,2)');
}
step s2c	{ COMMIT; }

# Violates referential integrity unless we use an up-to-date crosscheck snapshot:
permutation s2ins s1del s2c s1c

# Raises a can't-serialize exception
# when the INSERT trigger does SELECT FOR KEY SHARE:
permutation s1del s2ins s1c s2c
