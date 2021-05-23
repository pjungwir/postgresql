-- Tests for WITHOUT OVERLAPS.

--
-- test input parser
--

-- PK with no columns just WITHOUT OVERLAPS:

CREATE TABLE without_overlaps_test (
	valid_at tsrange,
	CONSTRAINT without_overlaps_pk PRIMARY KEY (valid_at WITHOUT OVERLAPS)
);

-- PK with a range column/PERIOD that isn't there:

CREATE TABLE without_overlaps_test (
	id INTEGER,
	CONSTRAINT without_overlaps_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);

-- PK with a non-range column:

CREATE TABLE without_overlaps_test (
	id INTEGER,
	valid_at TEXT,
	CONSTRAINT without_overlaps_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);

-- PK with one column plus a range:

CREATE TABLE without_overlaps_test (
	-- Since we can't depend on having btree_gist here,
	-- use an int4range instead of an int.
	-- (The rangetypes regression test uses the same trick.)
	id int4range,
	valid_at tsrange,
	CONSTRAINT without_overlaps_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);

-- PK with two columns plus a range:
CREATE TABLE without_overlaps_test2 (
	id1 int4range,
	id2 int4range,
	valid_at tsrange,
	CONSTRAINT without_overlaps2_pk PRIMARY KEY (id1, id2, valid_at WITHOUT OVERLAPS)
);
DROP TABLE without_overlaps_test2;


-- PK with one column plus a PERIOD:
CREATE TABLE without_overlaps_test2 (
	id int4range,
	valid_from date,
	valid_til date,
	PERIOD FOR valid_at (valid_from, valid_til),
	CONSTRAINT without_overlaps2_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);
SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'without_overlaps2_pk';
DROP TABLE without_overlaps_test2;

-- PK with two columns plus a PERIOD:
CREATE TABLE without_overlaps_test2 (
	id1 int4range,
	id2 int4range,
	valid_from date,
	valid_til date,
	PERIOD FOR valid_at (valid_from, valid_til),
	CONSTRAINT without_overlaps2_pk PRIMARY KEY (id1, id2, valid_at WITHOUT OVERLAPS)
);
DROP TABLE without_overlaps_test2;

-- PK with a custom range type:
CREATE TYPE textrange2 AS range (subtype=text, collation="C");
CREATE TABLE without_overlaps_test2 (
	id int4range,
	valid_at textrange2,
	CONSTRAINT without_overlaps2_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);
ALTER TABLE without_overlaps_test2 DROP CONSTRAINT without_overlaps2_pk;
DROP TABLE without_overlaps_test2;
DROP TYPE textrange2;

-- UNIQUE with no columns just WITHOUT OVERLAPS:

CREATE TABLE without_overlaps_uq_test (
	valid_at tsrange,
	CONSTRAINT without_overlaps_uq UNIQUE (valid_at WITHOUT OVERLAPS)
);

-- UNIQUE with a range column/PERIOD that isn't there:

CREATE TABLE without_overlaps_uq_test (
	id INTEGER,
	CONSTRAINT without_overlaps_uq UNIQUE (id, valid_at WITHOUT OVERLAPS)
);

-- UNIQUE with a non-range column:

CREATE TABLE without_overlaps_uq_test (
	id INTEGER,
	valid_at TEXT,
	CONSTRAINT without_overlaps_uq UNIQUE (id, valid_at WITHOUT OVERLAPS)
);

-- UNIQUE with one column plus a range:

CREATE TABLE without_overlaps_uq_test (
	-- Since we can't depend on having btree_gist here,
	-- use an int4range instead of an int.
	-- (The rangetypes regression test uses the same trick.)
	id int4range,
	valid_at tsrange,
	CONSTRAINT without_overlaps_uq UNIQUE (id, valid_at WITHOUT OVERLAPS)
);

-- UNIQUE with two columns plus a range:
CREATE TABLE without_overlaps_uq_test2 (
	id1 int4range,
	id2 int4range,
	valid_at tsrange,
	CONSTRAINT without_overlaps2_uq UNIQUE (id1, id2, valid_at WITHOUT OVERLAPS)
);
DROP TABLE without_overlaps_uq_test2;

-- UNIQUE with one column plus a PERIOD:
CREATE TABLE without_overlaps_uq_test2 (
	id int4range,
	valid_from timestamp,
	valid_til timestamp,
	PERIOD FOR valid_at (valid_from, valid_til),
	CONSTRAINT without_overlaps2_uq UNIQUE (id, valid_at WITHOUT OVERLAPS)
);
DROP TABLE without_overlaps_uq_test2;

-- UNIQUE with two columns plus a PERIOD:
CREATE TABLE without_overlaps_uq_test2 (
	id1 int4range,
	id2 int4range,
	valid_from timestamp,
	valid_til timestamp,
	PERIOD FOR valid_at (valid_from, valid_til),
	CONSTRAINT without_overlaps2_uq UNIQUE (id1, id2, valid_at WITHOUT OVERLAPS)
);
DROP TABLE without_overlaps_uq_test2;

-- UNIQUE with a custom range type:
CREATE TYPE textrange2 AS range (subtype=text, collation="C");
CREATE TABLE without_overlaps_uq_test2 (
	id int4range,
	valid_at textrange2,
	CONSTRAINT without_overlaps2_uq UNIQUE (id, valid_at WITHOUT OVERLAPS)
);
ALTER TABLE without_overlaps_uq_test2 DROP CONSTRAINT without_overlaps2_uq;
DROP TABLE without_overlaps_uq_test2;
DROP TYPE textrange2;

--
-- test ALTER TABLE ADD CONSTRAINT
--

DROP TABLE without_overlaps_test;
CREATE TABLE without_overlaps_test (
	id int4range,
	valid_at tsrange
);
ALTER TABLE without_overlaps_test
	ADD CONSTRAINT without_overlaps_pk
	PRIMARY KEY (id, valid_at WITHOUT OVERLAPS);

-- PK with USING INDEX (not yet allowed):
CREATE TABLE without_overlaps_test2 (
	id int4range,
	valid_at tsrange
);
CREATE INDEX idx_without_overlaps2 ON without_overlaps_test2 USING gist (id, valid_at);
ALTER TABLE without_overlaps_test2
	ADD CONSTRAINT without_overlaps2_pk
	PRIMARY KEY USING INDEX idx_without_overlaps2;
DROP TABLE without_overlaps_test2;

-- UNIQUE with USING INDEX (not yet allowed):
CREATE TABLE without_overlaps_uq_test2 (
	id int4range,
	valid_at tsrange
);
CREATE INDEX idx_without_overlaps_uq ON without_overlaps_uq_test2 USING gist (id, valid_at);
ALTER TABLE without_overlaps_uq_test2
	ADD CONSTRAINT without_overlaps2_uq
	UNIQUE USING INDEX idx_without_overlaps_uq;
DROP TABLE without_overlaps_uq_test2;

-- Add range column and the PK at the same time
CREATE TABLE without_overlaps_test2 (
	id int4range
);
ALTER TABLE without_overlaps_test2
	ADD COLUMN valid_at tsrange,
	ADD CONSTRAINT without_overlaps2_pk
	PRIMARY KEY (id, valid_at WITHOUT OVERLAPS);
DROP TABLE without_overlaps_test2;

-- Add PERIOD and the PK at the same time
CREATE TABLE without_overlaps_test2 (
	id int4range,
	valid_from date,
	valid_til date
);
ALTER TABLE without_overlaps_test2
	ADD PERIOD FOR valid_at (valid_from, valid_til),
	ADD CONSTRAINT without_overlaps2_pk
	PRIMARY KEY (id, valid_at WITHOUT OVERLAPS);
DROP TABLE without_overlaps_test2;

-- Add range column and UNIQUE constraint at the same time
CREATE TABLE without_overlaps_test2 (
	id int4range
);
ALTER TABLE without_overlaps_test2
	ADD COLUMN valid_at tsrange,
	ADD CONSTRAINT without_overlaps2_uq
	UNIQUE (id, valid_at WITHOUT OVERLAPS);
DROP TABLE without_overlaps_test2;

-- Add PERIOD column and UNIQUE constraint at the same time
CREATE TABLE without_overlaps_test2 (
	id int4range,
	valid_from date,
	valid_til date
);
ALTER TABLE without_overlaps_test2
	ADD PERIOD FOR valid_at (valid_from, valid_til),
	ADD CONSTRAINT without_overlaps2_uq
	UNIQUE (id, valid_at WITHOUT OVERLAPS);
DROP TABLE without_overlaps_test2;

-- Add date columns, PERIOD, and the PK at the same time
CREATE TABLE without_overlaps_test2 (
	id int4range
);
ALTER TABLE without_overlaps_test2
	ADD COLUMN valid_from date,
	ADD COLUMN valid_til date,
	ADD PERIOD FOR valid_at (valid_from, valid_til),
	ADD CONSTRAINT without_overlaps2_pk
	PRIMARY KEY (id, valid_at WITHOUT OVERLAPS);
DROP TABLE without_overlaps_test2;

-- Add date columns, PERIOD, and UNIQUE constraint at the same time
CREATE TABLE without_overlaps_test2 (
	id int4range
);
ALTER TABLE without_overlaps_test2
	ADD COLUMN valid_from date,
	ADD COLUMN valid_til date,
	ADD PERIOD FOR valid_at (valid_from, valid_til),
	ADD CONSTRAINT without_overlaps2_uq
	UNIQUE (id, valid_at WITHOUT OVERLAPS);
DROP TABLE without_overlaps_test2;

--
-- test pg_get_constraintdef
--

SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'without_overlaps_pk';

--
-- test PK inserts
--

-- okay:
INSERT INTO without_overlaps_test VALUES ('[1,1]', tsrange('2018-01-02', '2018-02-03'));
INSERT INTO without_overlaps_test VALUES ('[1,1]', tsrange('2018-03-03', '2018-04-04'));
INSERT INTO without_overlaps_test VALUES ('[2,2]', tsrange('2018-01-01', '2018-01-05'));
INSERT INTO without_overlaps_test VALUES ('[3,3]', tsrange('2018-01-01', NULL));

-- should fail:
INSERT INTO without_overlaps_test VALUES ('[1,1]', tsrange('2018-01-01', '2018-01-05'));
INSERT INTO without_overlaps_test VALUES (NULL, tsrange('2018-01-01', '2018-01-05'));
INSERT INTO without_overlaps_test VALUES ('[3,3]', NULL);

--
-- test changing the PK's dependencies
--

CREATE TABLE without_overlaps_test2 (
	id int4range,
	valid_at tsrange,
	CONSTRAINT without_overlaps2_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);

ALTER TABLE without_overlaps_test2 ALTER COLUMN valid_at DROP NOT NULL;
ALTER TABLE without_overlaps_test2 ALTER COLUMN valid_at TYPE tstzrange USING tstzrange(lower(valid_at), upper(valid_at));
ALTER TABLE without_overlaps_test2 RENAME COLUMN valid_at TO valid_thru;
ALTER TABLE without_overlaps_test2 DROP COLUMN valid_thru;
DROP TABLE without_overlaps_test2;

--
-- test FK dependencies
--

-- can't drop a range referenced by an FK, unless with CASCADE
CREATE TABLE without_overlaps_test2 (
	id int4range,
	valid_at tsrange,
	CONSTRAINT without_overlaps2_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);
CREATE TABLE referencing_period_test2 (
	id int4range,
	valid_at tsrange,
	parent_id int4range,
	CONSTRAINT referencing_period2_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS),
	CONSTRAINT referencing_period2_fk FOREIGN KEY (parent_id, PERIOD valid_at)
		REFERENCES without_overlaps_test2 (id, PERIOD valid_at)
);
ALTER TABLE without_overlaps_test2 DROP COLUMN valid_at;
ALTER TABLE without_overlaps_test2 DROP COLUMN valid_at CASCADE;
DROP TABLE referencing_period_test2;
DROP TABLE without_overlaps_test2;

-- can't drop a PERIOD referenced by an FK, unless with CASCADE
CREATE TABLE without_overlaps_test2 (
	id int4range,
	valid_from timestamp,
	valid_til timestamp,
	PERIOD FOR valid_at (valid_from, valid_til),
	CONSTRAINT without_overlaps2_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);
CREATE TABLE referencing_period_test2 (
	id int4range,
	valid_at tsrange,
	parent_id int4range,
	CONSTRAINT referencing_period2_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS),
	CONSTRAINT referencing_period2_fk FOREIGN KEY (parent_id, PERIOD valid_at)
		REFERENCES without_overlaps_test2 (id, PERIOD valid_at)
);
ALTER TABLE without_overlaps_test2 DROP PERIOD FOR valid_at;
ALTER TABLE without_overlaps_test2 DROP PERIOD FOR valid_at CASCADE;
DROP TABLE referencing_period_test2;
DROP TABLE without_overlaps_test2;

--
-- test FOREIGN KEY, range references range
--

CREATE TABLE referencing_period_test (
	id int4range,
	valid_at tsrange,
	parent_id int4range,
	CONSTRAINT referencing_period_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS),
	CONSTRAINT referencing_period_fk FOREIGN KEY (parent_id, PERIOD valid_at)
		REFERENCES without_overlaps_test (id, PERIOD valid_at)
);
DROP TABLE referencing_period_test;

-- with inferred PK on the referenced table:
CREATE TABLE referencing_period_test (
	id int4range,
	valid_at tsrange,
	parent_id int4range,
	CONSTRAINT referencing_period_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS),
	CONSTRAINT referencing_period_fk FOREIGN KEY (parent_id, PERIOD valid_at)
		REFERENCES without_overlaps_test
);
DROP TABLE referencing_period_test;

-- should fail because of duplicate referenced columns:
CREATE TABLE referencing_period_test (
	id int4range,
	valid_at tsrange,
	parent_id int4range,
	CONSTRAINT referencing_period_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS),
	CONSTRAINT referencing_period_fk FOREIGN KEY (parent_id, PERIOD parent_id)
		REFERENCES without_overlaps_test (id, PERIOD id)
);

--
-- test ALTER TABLE ADD CONSTRAINT
--

CREATE TABLE referencing_period_test (
	id int4range,
	valid_at tsrange,
	parent_id int4range,
	CONSTRAINT referencing_period_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test (id, PERIOD valid_at);
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
-- with inferred PK on the referenced table:
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;

-- should fail because of duplicate referenced columns:
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk2
	FOREIGN KEY (parent_id, PERIOD parent_id)
	REFERENCES without_overlaps_test (id, PERIOD id);

--
-- test with rows already
--

DELETE FROM referencing_period_test;
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
INSERT INTO referencing_period_test VALUES ('[1,1]', tsrange('2018-01-02', '2018-02-01'), '[1,1]');
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
INSERT INTO referencing_period_test VALUES ('[2,2]', tsrange('2018-01-02', '2018-04-01'), '[1,1]');
-- should fail:
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;
-- okay again:
DELETE FROM referencing_period_test;
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;

--
-- test pg_get_constraintdef
--

SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'referencing_period_fk';

--
-- test FK child inserts
--

INSERT INTO referencing_period_test VALUES ('[1,1]', tsrange('2018-01-02', '2018-02-01'), '[1,1]');
-- should fail:
INSERT INTO referencing_period_test VALUES ('[2,2]', tsrange('2018-01-02', '2018-04-01'), '[1,1]');
-- now it should work:
INSERT INTO without_overlaps_test VALUES ('[1,1]', tsrange('2018-02-03', '2018-03-03'));
INSERT INTO referencing_period_test VALUES ('[2,2]', tsrange('2018-01-02', '2018-04-01'), '[1,1]');

--
-- test FK child updates
--

UPDATE referencing_period_test SET valid_at = tsrange('2018-01-02', '2018-03-01') WHERE id = '[1,1]';
-- should fail:
UPDATE referencing_period_test SET valid_at = tsrange('2018-01-02', '2018-05-01') WHERE id = '[1,1]';
UPDATE referencing_period_test SET parent_id = '[8,8]' WHERE id = '[1,1]';

--
-- test FK parent updates NO ACTION
--

-- a PK update that succeeds because the numeric id isn't referenced:
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-01-01', '2018-02-01'));
UPDATE without_overlaps_test SET valid_at = tsrange('2016-01-01', '2016-02-01') WHERE id = '[5,5]';
-- a PK update that succeeds even though the numeric id is referenced because the range isn't:
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-01-01', '2018-02-01'));
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-02-01', '2018-03-01'));
INSERT INTO referencing_period_test VALUES ('[3,3]', tsrange('2018-01-05', '2018-01-10'), '[5,5]');
UPDATE without_overlaps_test SET valid_at = tsrange('2016-02-01', '2016-03-01')
WHERE id = '[5,5]' AND valid_at = tsrange('2018-02-01', '2018-03-01');
-- a PK update that fails because both are referenced:
UPDATE without_overlaps_test SET valid_at = tsrange('2016-01-01', '2016-02-01')
WHERE id = '[5,5]' AND valid_at = tsrange('2018-01-01', '2018-02-01');
-- then delete the objecting FK record and the same PK update succeeds:
DELETE FROM referencing_period_test WHERE id = '[3,3]';
UPDATE without_overlaps_test SET valid_at = tsrange('2016-01-01', '2016-02-01')
WHERE id = '[5,5]' AND valid_at = tsrange('2018-01-01', '2018-02-01');
-- clean up:
DELETE FROM referencing_period_test WHERE parent_id = '[5,5]';
DELETE FROM without_overlaps_test WHERE id = '[5,5]';

--
-- test FK parent updates RESTRICT
--

ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test
	ON DELETE RESTRICT;
-- a PK update that succeeds because the numeric id isn't referenced:
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-01-01', '2018-02-01'));
UPDATE without_overlaps_test SET valid_at = tsrange('2016-01-01', '2016-02-01') WHERE id = '[5,5]';
-- a PK update that succeeds even though the numeric id is referenced because the range isn't:
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-01-01', '2018-02-01'));
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-02-01', '2018-03-01'));
INSERT INTO referencing_period_test VALUES ('[3,3]', tsrange('2018-01-05', '2018-01-10'), '[5,5]');
UPDATE without_overlaps_test SET valid_at = tsrange('2016-02-01', '2016-03-01')
WHERE id = '[5,5]' AND valid_at = tsrange('2018-02-01', '2018-03-01');
-- a PK update that fails because both are referenced:
UPDATE without_overlaps_test SET valid_at = tsrange('2016-01-01', '2016-02-01')
WHERE id = '[5,5]' AND valid_at = tsrange('2018-01-01', '2018-02-01');
-- then delete the objecting FK record and the same PK update succeeds:
DELETE FROM referencing_period_test WHERE id = '[3,3]';
UPDATE without_overlaps_test SET valid_at = tsrange('2016-01-01', '2016-02-01')
WHERE id = '[5,5]' AND valid_at = tsrange('2018-01-01', '2018-02-01');
-- clean up:
DELETE FROM referencing_period_test WHERE parent_id = '[5,5]';
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
--
-- test FK parent deletes NO ACTION
--
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;
-- a PK delete that succeeds because the numeric id isn't referenced:
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-01-01', '2018-02-01'));
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
-- a PK delete that succeeds even though the numeric id is referenced because the range isn't:
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-01-01', '2018-02-01'));
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-02-01', '2018-03-01'));
INSERT INTO referencing_period_test VALUES ('[3,3]', tsrange('2018-01-05', '2018-01-10'), '[5,5]');
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_at = tsrange('2018-02-01', '2018-03-01');
-- a PK delete that fails because both are referenced:
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_at = tsrange('2018-01-01', '2018-02-01');
-- then delete the objecting FK record and the same PK delete succeeds:
DELETE FROM referencing_period_test WHERE id = '[3,3]';
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_at = tsrange('2018-01-01', '2018-02-01');

--
-- test FK parent deletes RESTRICT
--

ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test
	ON DELETE RESTRICT;
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-01-01', '2018-02-01'));
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
-- a PK delete that succeeds even though the numeric id is referenced because the range isn't:
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-01-01', '2018-02-01'));
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-02-01', '2018-03-01'));
INSERT INTO referencing_period_test VALUES ('[3,3]', tsrange('2018-01-05', '2018-01-10'), '[5,5]');
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_at = tsrange('2018-02-01', '2018-03-01');
-- a PK delete that fails because both are referenced:
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_at = tsrange('2018-01-01', '2018-02-01');
-- then delete the objecting FK record and the same PK delete succeeds:
DELETE FROM referencing_period_test WHERE id = '[3,3]';
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_at = tsrange('2018-01-01', '2018-02-01');

--
-- test ON UPDATE/DELETE options
--

-- test FK parent updates CASCADE
INSERT INTO without_overlaps_test VALUES ('[6,6]', tsrange('2018-01-01', '2021-01-01'));
INSERT INTO referencing_period_test VALUES ('[4,4]', tsrange('2018-01-01', '2021-01-01'), '[6,6]');
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk,
	ADD CONSTRAINT referencing_period_fk
		FOREIGN KEY (parent_id, PERIOD valid_at)
		REFERENCES without_overlaps_test
		ON DELETE CASCADE ON UPDATE CASCADE;
UPDATE without_overlaps_test FOR PORTION OF valid_at FROM '2019-01-01' TO '2020-01-01' SET id = '[7,7]' WHERE id = '[6,6]';
SELECT * FROM referencing_period_test WHERE id = '[4,4]';
UPDATE without_overlaps_test SET id = '[7,7]' WHERE id = '[6,6]';
SELECT * FROM referencing_period_test WHERE id = '[4,4]';

-- test FK parent deletes CASCADE
INSERT INTO without_overlaps_test VALUES ('[8,8]', tsrange('2018-01-01', '2021-01-01'));
INSERT INTO referencing_period_test VALUES ('[5,5]', tsrange('2018-01-01', '2021-01-01'), '[8,8]');
DELETE FROM without_overlaps_test FOR PORTION OF valid_at FROM '2019-01-01' TO '2020-01-01' WHERE id = '[8,8]';
SELECT * FROM referencing_period_test WHERE id = '[5,5]';
DELETE FROM without_overlaps_test WHERE id = '[8,8]';
SELECT * FROM referencing_period_test WHERE id = '[5,5]';

-- TODO: Need a delete without a FOR PORTION OF too, and make sure the whole child row is deleted.
-- test FK parent updates SET NULL
-- TODO
-- test FK parent deletes SET NULL
-- TODO
-- test FK parent updates SET DEFAULT
-- TODO
-- test FK parent deletes SET DEFAULT
-- TODO

-- test cascades through a FOR PORTION OF



--
-- test FOREIGN KEY, range references PERIOD
--

DROP TABLE without_overlaps_test CASCADE;
CREATE TABLE without_overlaps_test (
	id int4range,
	valid_from timestamp,
	valid_til timestamp,
	PERIOD FOR valid_at (valid_from, valid_til),
	CONSTRAINT without_overlaps_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);
INSERT INTO without_overlaps_test VALUES ('[1,1]', '2018-01-02', '2018-02-03');
INSERT INTO without_overlaps_test VALUES ('[1,1]', '2018-03-03', '2018-04-04');
INSERT INTO without_overlaps_test VALUES ('[2,2]', '2018-01-01', '2018-01-05');
INSERT INTO without_overlaps_test VALUES ('[3,3]', '2018-01-01', NULL);

-- with inferred PK on the referenced table:
DROP TABLE referencing_period_test;
CREATE TABLE referencing_period_test (
	id int4range,
	valid_at tsrange,
	parent_id int4range,
	CONSTRAINT referencing_period_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS),
	CONSTRAINT referencing_period_fk FOREIGN KEY (parent_id, PERIOD valid_at)
		REFERENCES without_overlaps_test
);
DROP TABLE referencing_period_test;

-- should fail because of duplicate referenced columns:
CREATE TABLE referencing_period_test (
	id int4range,
	valid_at tsrange,
	parent_id int4range,
	CONSTRAINT referencing_period_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS),
	CONSTRAINT referencing_period_fk FOREIGN KEY (parent_id, PERIOD parent_id)
		REFERENCES without_overlaps_test (id, PERIOD id)
);

--
-- test ALTER TABLE ADD CONSTRAINT
--

CREATE TABLE referencing_period_test (
	id int4range,
	valid_at tsrange,
	parent_id int4range,
	CONSTRAINT referencing_period_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test (id, PERIOD valid_at);
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
-- with inferred PK on the referenced table:
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;

-- should fail because of duplicate referenced columns:
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk2
	FOREIGN KEY (parent_id, PERIOD parent_id)
	REFERENCES without_overlaps_test (id, PERIOD id);

--
-- test with rows already
--

DELETE FROM referencing_period_test;
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
INSERT INTO referencing_period_test VALUES ('[1,1]', tsrange('2018-01-02', '2018-02-01'), '[1,1]');
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
INSERT INTO referencing_period_test VALUES ('[2,2]', tsrange('2018-01-02', '2018-04-01'), '[1,1]');
-- should fail:
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;
-- okay again:
DELETE FROM referencing_period_test;
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;

--
-- test pg_get_constraintdef
--

SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'referencing_period_fk';

--
-- test FK child inserts
--

INSERT INTO referencing_period_test VALUES ('[1,1]', tsrange('2018-01-02', '2018-02-01'), '[1,1]');
-- should fail:
INSERT INTO referencing_period_test VALUES ('[2,2]', tsrange('2018-01-02', '2018-04-01'), '[1,1]');
-- now it should work:
INSERT INTO without_overlaps_test VALUES ('[1,1]', '2018-02-03', '2018-03-03');
INSERT INTO referencing_period_test VALUES ('[2,2]', tsrange('2018-01-02', '2018-04-01'), '[1,1]');

--
-- test FK child updates
--
UPDATE referencing_period_test SET valid_at = tsrange('2018-01-02', '2018-03-01') WHERE id = '[1,1]';
-- should fail:
UPDATE referencing_period_test SET valid_at = tsrange('2018-01-02', '2018-05-01') WHERE id = '[1,1]';
UPDATE referencing_period_test SET parent_id = '[8,8]' WHERE id = '[1,1]';

--
-- test FK parent updates NO ACTION
--

-- a PK update that succeeds because the numeric id isn't referenced:
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-01-01', '2018-02-01');
UPDATE without_overlaps_test SET valid_from = '2016-01-01', valid_til = '2016-02-01' WHERE id = '[5,5]';
-- a PK update that succeeds even though the numeric id is referenced because the range isn't:
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-01-01', '2018-02-01');
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-02-01', '2018-03-01');
INSERT INTO referencing_period_test VALUES ('[3,3]', tsrange('2018-01-05', '2018-01-10'), '[5,5]');
UPDATE without_overlaps_test SET valid_from = '2016-02-01', valid_til = '2016-03-01'
WHERE id = '[5,5]' AND valid_from = '2018-02-01' AND valid_til = '2018-03-01';
-- a PK update that fails because both are referenced:
UPDATE without_overlaps_test SET valid_from = '2016-01-01', valid_til = '2016-02-01'
WHERE id = '[5,5]' AND valid_from = '2018-01-01' AND valid_til = '2018-02-01';
-- then delete the objecting FK record and the same PK update succeeds:
DELETE FROM referencing_period_test WHERE id = '[3,3]';
UPDATE without_overlaps_test SET valid_from = '2016-01-01', valid_til = '2016-02-01'
WHERE id = '[5,5]' AND valid_from = '2018-01-01' AND valid_til = '2018-02-01';
-- clean up:
DELETE FROM referencing_period_test WHERE parent_id = '[5,5]';
DELETE FROM without_overlaps_test WHERE id = '[5,5]';

--
-- test FK parent updates RESTRICT
--

ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test
	ON DELETE RESTRICT;
-- a PK update that succeeds because the numeric id isn't referenced:
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-01-01', '2018-02-01');
UPDATE without_overlaps_test SET valid_from = '2016-01-01', valid_til = '2016-02-01' WHERE id = '[5,5]';
-- a PK update that succeeds even though the numeric id is referenced because the range isn't:
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-01-01', '2018-02-01');
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-02-01', '2018-03-01');
INSERT INTO referencing_period_test VALUES ('[3,3]', tsrange('2018-01-05', '2018-01-10'), '[5,5]');
UPDATE without_overlaps_test SET valid_from = '2016-02-01', valid_til = '2016-03-01'
WHERE id = '[5,5]' AND valid_from = '2018-02-01' AND valid_til = '2018-03-01';
-- a PK update that fails because both are referenced:
UPDATE without_overlaps_test SET valid_from = '2016-01-01', valid_til = '2016-02-01'
WHERE id = '[5,5]' AND valid_from = '2018-01-01' AND valid_til = '2018-02-01';
-- then delete the objecting FK record and the same PK update succeeds:
DELETE FROM referencing_period_test WHERE id = '[3,3]';
UPDATE without_overlaps_test SET valid_from = '2016-01-01', valid_til = '2016-02-01'
WHERE id = '[5,5]' AND valid_from = '2018-01-01' AND valid_til = '2018-02-01';
-- clean up:
DELETE FROM referencing_period_test WHERE parent_id = '[5,5]';
DELETE FROM without_overlaps_test WHERE id = '[5,5]';

--
-- test FK parent deletes NO ACTION
--

ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;
-- a PK delete that succeeds because the numeric id isn't referenced:
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-01-01', '2018-02-01');
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
-- a PK delete that succeeds even though the numeric id is referenced because the range isn't:
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-01-01', '2018-02-01');
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-02-01', '2018-03-01');
INSERT INTO referencing_period_test VALUES ('[3,3]', tsrange('2018-01-05', '2018-01-10'), '[5,5]');
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_from = '2018-02-01' AND valid_til = '2018-03-01';
-- a PK delete that fails because both are referenced:
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_from = '2018-01-01' AND valid_til = '2018-02-01';
-- then delete the objecting FK record and the same PK delete succeeds:
DELETE FROM referencing_period_test WHERE id = '[3,3]';
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_from = '2018-01-01' AND valid_til = '2018-02-01';

--
-- test FK parent deletes RESTRICT
--

ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test
	ON DELETE RESTRICT;
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-01-01', '2018-02-01');
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
-- a PK delete that succeeds even though the numeric id is referenced because the range isn't:
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-01-01', '2018-02-01');
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-02-01', '2018-03-01');
INSERT INTO referencing_period_test VALUES ('[3,3]', tsrange('2018-01-05', '2018-01-10'), '[5,5]');
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_from = '2018-02-01' AND valid_til = '2018-03-01';
-- a PK delete that fails because both are referenced:
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_from = '2018-01-01' AND valid_til = '2018-02-01';
-- then delete the objecting FK record and the same PK delete succeeds:
DELETE FROM referencing_period_test WHERE id = '[3,3]';
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_from = '2018-01-01' AND valid_til = '2018-02-01';

--
-- test ON UPDATE/DELETE options
--

-- test FK parent updates CASCADE
INSERT INTO without_overlaps_test VALUES ('[6,6]', '2018-01-01', '2021-01-01');
INSERT INTO referencing_period_test VALUES ('[4,4]', tsrange('2018-01-01', '2021-01-01'), '[6,6]');
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk,
	ADD CONSTRAINT referencing_period_fk
		FOREIGN KEY (parent_id, PERIOD valid_at)
		REFERENCES without_overlaps_test
		ON DELETE CASCADE ON UPDATE CASCADE;
UPDATE without_overlaps_test FOR PORTION OF valid_at FROM '2019-01-01' TO '2020-01-01' SET id = '[7,7]' WHERE id = '[6,6]';
SELECT * FROM referencing_period_test WHERE id = '[4,4]';
UPDATE without_overlaps_test SET id = '[7,7]' WHERE id = '[6,6]';
SELECT * FROM referencing_period_test WHERE id = '[4,4]';

-- test FK parent deletes CASCADE
INSERT INTO without_overlaps_test VALUES ('[8,8]', '2018-01-01', '2021-01-01');
INSERT INTO referencing_period_test VALUES ('[5,5]', tsrange('2018-01-01', '2021-01-01'), '[8,8]');
DELETE FROM without_overlaps_test FOR PORTION OF valid_at FROM '2019-01-01' TO '2020-01-01' WHERE id = '[8,8]';
SELECT * FROM referencing_period_test WHERE id = '[5,5]';
DELETE FROM without_overlaps_test WHERE id = '[8,8]';
SELECT * FROM referencing_period_test WHERE id = '[5,5]';
-- test FK parent updates SET NULL
-- TODO
-- test FK parent deletes SET NULL
-- TODO
-- test FK parent updates SET DEFAULT
-- TODO
-- test FK parent deletes SET DEFAULT
-- TODO

-- test cascades through a FOR PORTION OF


--
-- test FOREIGN KEY, PERIOD references range
--

DROP TABLE without_overlaps_test CASCADE;
CREATE TABLE without_overlaps_test (
	id int4range,
	valid_at tsrange,
	CONSTRAINT without_overlaps_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);
INSERT INTO without_overlaps_test VALUES ('[1,1]', tsrange('2018-01-02', '2018-02-03'));
INSERT INTO without_overlaps_test VALUES ('[1,1]', tsrange('2018-03-03', '2018-04-04'));
INSERT INTO without_overlaps_test VALUES ('[2,2]', tsrange('2018-01-01', '2018-01-05'));
INSERT INTO without_overlaps_test VALUES ('[3,3]', tsrange('2018-01-01', NULL));

-- with inferred PK on the referenced table:
DROP TABLE referencing_period_test;
CREATE TABLE referencing_period_test (
	id int4range,
	valid_from timestamp,
	valid_til timestamp,
	PERIOD FOR valid_at (valid_from, valid_til),
	parent_id int4range,
	CONSTRAINT referencing_period_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS),
	CONSTRAINT referencing_period_fk FOREIGN KEY (parent_id, PERIOD valid_at)
		REFERENCES without_overlaps_test
);
DROP TABLE referencing_period_test;

-- should fail because of duplicate referenced columns:
CREATE TABLE referencing_period_test (
	id int4range,
	valid_from timestamp,
	valid_til timestamp,
	PERIOD FOR valid_at (valid_from, valid_til),
	parent_id int4range,
	CONSTRAINT referencing_period_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS),
	CONSTRAINT referencing_period_fk FOREIGN KEY (parent_id, PERIOD parent_id)
		REFERENCES without_overlaps_test (id, PERIOD id)
);

--
-- test ALTER TABLE ADD CONSTRAINT
--

CREATE TABLE referencing_period_test (
	id int4range,
	valid_from timestamp,
	valid_til timestamp,
	PERIOD FOR valid_at (valid_from, valid_til),
	parent_id int4range,
	CONSTRAINT referencing_period_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test (id, PERIOD valid_at);
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
-- with inferred PK on the referenced table:
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;

-- should fail because of duplicate referenced columns:
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk2
	FOREIGN KEY (parent_id, PERIOD parent_id)
	REFERENCES without_overlaps_test (id, PERIOD id);

--
-- test with rows already
--

DELETE FROM referencing_period_test;
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
INSERT INTO referencing_period_test VALUES ('[1,1]', '2018-01-02', '2018-02-01', '[1,1]');
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
INSERT INTO referencing_period_test VALUES ('[2,2]', '2018-01-02', '2018-04-01', '[1,1]');
-- should fail:
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;
-- okay again:
DELETE FROM referencing_period_test;
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;

--
-- test pg_get_constraintdef
--

SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'referencing_period_fk';

--
-- test FK child inserts
--

INSERT INTO referencing_period_test VALUES ('[1,1]', '2018-01-02', '2018-02-01', '[1,1]');
-- should fail:
INSERT INTO referencing_period_test VALUES ('[2,2]', '2018-01-02', '2018-04-01', '[1,1]');
-- now it should work:
INSERT INTO without_overlaps_test VALUES ('[1,1]', tsrange('2018-02-03', '2018-03-03'));
INSERT INTO referencing_period_test VALUES ('[2,2]', '2018-01-02', '2018-04-01', '[1,1]');

--
-- test FK child updates
--
UPDATE referencing_period_test SET valid_from = '2018-01-02', valid_til = '2018-03-01' WHERE id = '[1,1]';
-- should fail:
UPDATE referencing_period_test SET valid_from = '2018-01-02', valid_til = '2018-05-01' WHERE id = '[1,1]';
UPDATE referencing_period_test SET parent_id = '[8,8]' WHERE id = '[1,1]';

--
-- test FK parent updates NO ACTION
--

-- a PK update that succeeds because the numeric id isn't referenced:
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-01-01', '2018-02-01'));
UPDATE without_overlaps_test SET valid_at = tsrange('2016-01-01', '2016-02-01') WHERE id = '[5,5]';
-- a PK update that succeeds even though the numeric id is referenced because the range isn't:
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-01-01', '2018-02-01'));
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-02-01', '2018-03-01'));
INSERT INTO referencing_period_test VALUES ('[3,3]', '2018-01-05', '2018-01-10', '[5,5]');
UPDATE without_overlaps_test SET valid_at = tsrange('2016-02-01', '2016-03-01')
WHERE id = '[5,5]' AND valid_at = tsrange('2018-02-01', '2018-03-01');
-- a PK update that fails because both are referenced:
UPDATE without_overlaps_test SET valid_at = tsrange('2016-01-01', '2016-02-01')
WHERE id = '[5,5]' AND valid_at = tsrange('2018-01-01','2018-02-01');
-- then delete the objecting FK record and the same PK update succeeds:
DELETE FROM referencing_period_test WHERE id = '[3,3]';
UPDATE without_overlaps_test SET valid_at = tsrange('2016-01-01', '2016-02-01')
WHERE id = '[5,5]' AND valid_at = tsrange('2018-01-01', '2018-02-01');
-- clean up:
DELETE FROM referencing_period_test WHERE parent_id = '[5,5]';
DELETE FROM without_overlaps_test WHERE id = '[5,5]';

--
-- test FK parent updates RESTRICT
--

ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test
	ON DELETE RESTRICT;
-- a PK update that succeeds because the numeric id isn't referenced:
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-01-01', '2018-02-01'));
UPDATE without_overlaps_test SET valid_at = tsrange('2016-01-01', '2016-02-01') WHERE id = '[5,5]';
-- a PK update that succeeds even though the numeric id is referenced because the range isn't:
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-01-01', '2018-02-01'));
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-02-01', '2018-03-01'));
INSERT INTO referencing_period_test VALUES ('[3,3]', '2018-01-05', '2018-01-10', '[5,5]');
UPDATE without_overlaps_test SET valid_at = tsrange('2016-02-01', '2016-03-01')
WHERE id = '[5,5]' AND valid_at = tsrange('2018-02-01', '2018-03-01');
-- a PK update that fails because both are referenced:
UPDATE without_overlaps_test SET valid_at = tsrange('2016-01-01', '2016-02-01')
WHERE id = '[5,5]' AND valid_at = tsrange('2018-01-01', '2018-02-01');
-- then delete the objecting FK record and the same PK update succeeds:
DELETE FROM referencing_period_test WHERE id = '[3,3]';
UPDATE without_overlaps_test SET valid_at = tsrange('2016-01-01', '2016-02-01')
WHERE id = '[5,5]' AND valid_at = tsrange('2018-01-01', '2018-02-01');
-- clean up:
DELETE FROM referencing_period_test WHERE parent_id = '[5,5]';
DELETE FROM without_overlaps_test WHERE id = '[5,5]';

--
-- test FK parent deletes NO ACTION
--

ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;
-- a PK delete that succeeds because the numeric id isn't referenced:
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-01-01', '2018-02-01'));
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
-- a PK delete that succeeds even though the numeric id is referenced because the range isn't:
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-01-01', '2018-02-01'));
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-02-01', '2018-03-01'));
INSERT INTO referencing_period_test VALUES ('[3,3]', '2018-01-05', '2018-01-10', '[5,5]');
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_at = tsrange('2018-02-01', '2018-03-01');
-- a PK delete that fails because both are referenced:
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_at = tsrange('2018-01-01', '2018-02-01');
-- then delete the objecting FK record and the same PK delete succeeds:
DELETE FROM referencing_period_test WHERE id = '[3,3]';
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_at = tsrange('2018-01-01', '2018-02-01');

--
-- test FK parent deletes RESTRICT
--

ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test
	ON DELETE RESTRICT;
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-01-01', '2018-02-01'));
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
-- a PK delete that succeeds even though the numeric id is referenced because the range isn't:
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-01-01', '2018-02-01'));
INSERT INTO without_overlaps_test VALUES ('[5,5]', tsrange('2018-02-01', '2018-03-01'));
INSERT INTO referencing_period_test VALUES ('[3,3]', '2018-01-05', '2018-01-10', '[5,5]');
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_at = tsrange('2018-02-01', '2018-03-01');
-- a PK delete that fails because both are referenced:
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_at = tsrange('2018-01-01', '2018-02-01');
-- then delete the objecting FK record and the same PK delete succeeds:
DELETE FROM referencing_period_test WHERE id = '[3,3]';
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_at = tsrange('2018-01-01', '2018-02-01');

--
-- test ON UPDATE/DELETE options
--

-- test FK parent updates CASCADE
INSERT INTO without_overlaps_test VALUES ('[6,6]', tsrange('2018-01-01', '2021-01-01'));
INSERT INTO referencing_period_test VALUES ('[4,4]', '2018-01-01', '2021-01-01', '[6,6]');
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk,
	ADD CONSTRAINT referencing_period_fk
		FOREIGN KEY (parent_id, PERIOD valid_at)
		REFERENCES without_overlaps_test
		ON DELETE CASCADE ON UPDATE CASCADE;
UPDATE without_overlaps_test FOR PORTION OF valid_at FROM '2019-01-01' TO '2020-01-01' SET id = '[7,7]' WHERE id = '[6,6]';
SELECT * FROM referencing_period_test WHERE id = '[4,4]';
UPDATE without_overlaps_test SET id = '[7,7]' WHERE id = '[6,6]';
SELECT * FROM referencing_period_test WHERE id = '[4,4]';

-- test FK parent deletes CASCADE
INSERT INTO without_overlaps_test VALUES ('[8,8]', tsrange('2018-01-01', '2021-01-01'));
INSERT INTO referencing_period_test VALUES ('[5,5]', '2018-01-01', '2021-01-01', '[8,8]');
DELETE FROM without_overlaps_test FOR PORTION OF valid_at FROM '2019-01-01' TO '2020-01-01' WHERE id = '[8,8]';
SELECT * FROM referencing_period_test WHERE id = '[5,5]';
DELETE FROM without_overlaps_test WHERE id = '[8,8]';
SELECT * FROM referencing_period_test WHERE id = '[5,5]';

-- test FK parent updates SET NULL
-- TODO
-- test FK parent deletes SET NULL
-- TODO
-- test FK parent updates SET DEFAULT
-- TODO
-- test FK parent deletes SET DEFAULT
-- TODO
-- test cascades through a FOR PORTION OF



--
-- test FOREIGN KEY, PERIOD references PERIOD
--

DROP TABLE without_overlaps_test CASCADE;
CREATE TABLE without_overlaps_test (
	id int4range,
	valid_from timestamp,
	valid_til timestamp,
	PERIOD FOR valid_at (valid_from, valid_til),
	CONSTRAINT without_overlaps_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);
INSERT INTO without_overlaps_test VALUES ('[1,1]', '2018-01-02', '2018-02-03');
INSERT INTO without_overlaps_test VALUES ('[1,1]', '2018-03-03', '2018-04-04');
INSERT INTO without_overlaps_test VALUES ('[2,2]', '2018-01-01', '2018-01-05');
INSERT INTO without_overlaps_test VALUES ('[3,3]', '2018-01-01', NULL);

-- with inferred PK on the referenced table:
DROP TABLE referencing_period_test;
CREATE TABLE referencing_period_test (
	id int4range,
	valid_from timestamp,
	valid_til timestamp,
	PERIOD FOR valid_at (valid_from, valid_til),
	parent_id int4range,
	CONSTRAINT referencing_period_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS),
	CONSTRAINT referencing_period_fk FOREIGN KEY (parent_id, PERIOD valid_at)
		REFERENCES without_overlaps_test
);
DROP TABLE referencing_period_test;

-- should fail because of duplicate referenced columns:
CREATE TABLE referencing_period_test (
	id int4range,
	valid_from timestamp,
	valid_til timestamp,
	PERIOD FOR valid_at (valid_from, valid_til),
	parent_id int4range,
	CONSTRAINT referencing_period_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS),
	CONSTRAINT referencing_period_fk FOREIGN KEY (parent_id, PERIOD parent_id)
		REFERENCES without_overlaps_test (id, PERIOD id)
);

--
-- test ALTER TABLE ADD CONSTRAINT
--

CREATE TABLE referencing_period_test (
	id int4range,
	valid_from timestamp,
	valid_til timestamp,
	PERIOD FOR valid_at (valid_from, valid_til),
	parent_id int4range,
	CONSTRAINT referencing_period_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test (id, PERIOD valid_at);
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
-- with inferred PK on the referenced table:
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;

-- should fail because of duplicate referenced columns:
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk2
	FOREIGN KEY (parent_id, PERIOD parent_id)
	REFERENCES without_overlaps_test (id, PERIOD id);

--
-- test with rows already
--

DELETE FROM referencing_period_test;
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
INSERT INTO referencing_period_test VALUES ('[1,1]', '2018-01-02', '2018-02-01', '[1,1]');
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
INSERT INTO referencing_period_test VALUES ('[2,2]', '2018-01-02', '2018-04-01', '[1,1]');
-- should fail:
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;
-- okay again:
DELETE FROM referencing_period_test;
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;

--
-- test pg_get_constraintdef
--

SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'referencing_period_fk';

--
-- test FK child inserts
--

INSERT INTO referencing_period_test VALUES ('[1,1]', '2018-01-02', '2018-02-01', '[1,1]');
-- should fail:
INSERT INTO referencing_period_test VALUES ('[2,2]', '2018-01-02', '2018-04-01', '[1,1]');
-- now it should work:
INSERT INTO without_overlaps_test VALUES ('[1,1]', '2018-02-03', '2018-03-03');
INSERT INTO referencing_period_test VALUES ('[2,2]', '2018-01-02', '2018-04-01', '[1,1]');

--
-- test FK child updates
--
UPDATE referencing_period_test SET valid_from = '2018-01-02', valid_til = '2018-03-01' WHERE id = '[1,1]';
-- should fail:
UPDATE referencing_period_test SET valid_from = '2018-01-02', valid_til = '2018-05-01' WHERE id = '[1,1]';
UPDATE referencing_period_test SET parent_id = '[8,8]' WHERE id = '[1,1]';

--
-- test FK parent updates NO ACTION
--

-- a PK update that succeeds because the numeric id isn't referenced:
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-01-01', '2018-02-01');
UPDATE without_overlaps_test SET valid_from = '2016-01-01', valid_til = '2016-02-01' WHERE id = '[5,5]';
-- a PK update that succeeds even though the numeric id is referenced because the range isn't:
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-01-01', '2018-02-01');
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-02-01', '2018-03-01');
INSERT INTO referencing_period_test VALUES ('[3,3]', '2018-01-05', '2018-01-10', '[5,5]');
UPDATE without_overlaps_test SET valid_from = '2016-02-01', valid_til = '2016-03-01'
WHERE id = '[5,5]' AND valid_from = '2018-02-01' AND valid_til = '2018-03-01';
-- a PK update that fails because both are referenced:
UPDATE without_overlaps_test SET valid_from = '2016-01-01', valid_til = '2016-02-01'
WHERE id = '[5,5]' AND valid_from = '2018-01-01' AND valid_til = '2018-02-01';
-- then delete the objecting FK record and the same PK update succeeds:
DELETE FROM referencing_period_test WHERE id = '[3,3]';
UPDATE without_overlaps_test SET valid_from = '2016-01-01', valid_til = '2016-02-01'
WHERE id = '[5,5]' AND valid_from = '2018-01-01' AND valid_til = '2018-02-01';
-- clean up:
DELETE FROM referencing_period_test WHERE parent_id = '[5,5]';
DELETE FROM without_overlaps_test WHERE id = '[5,5]';

--
-- test FK parent updates RESTRICT
--

ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test
	ON DELETE RESTRICT;
-- a PK update that succeeds because the numeric id isn't referenced:
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-01-01', '2018-02-01');
UPDATE without_overlaps_test SET valid_from = '2016-01-01', valid_til = '2016-02-01' WHERE id = '[5,5]';
-- a PK update that succeeds even though the numeric id is referenced because the range isn't:
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-01-01', '2018-02-01');
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-02-01', '2018-03-01');
INSERT INTO referencing_period_test VALUES ('[3,3]', '2018-01-05', '2018-01-10', '[5,5]');
UPDATE without_overlaps_test SET valid_from = '2016-02-01', valid_til = '2016-03-01'
WHERE id = '[5,5]' AND valid_from = '2018-02-01' AND valid_til = '2018-03-01';
-- a PK update that fails because both are referenced:
UPDATE without_overlaps_test SET valid_from = '2016-01-01', valid_til = '2016-02-01'
WHERE id = '[5,5]' AND valid_from = '2018-01-01' AND valid_til = '2018-02-01';
-- then delete the objecting FK record and the same PK update succeeds:
DELETE FROM referencing_period_test WHERE id = '[3,3]';
UPDATE without_overlaps_test SET valid_from = '2016-01-01', valid_til = '2016-02-01'
WHERE id = '[5,5]' AND valid_from = '2018-01-01' AND valid_til = '2018-02-01';
-- clean up:
DELETE FROM referencing_period_test WHERE parent_id = '[5,5]';
DELETE FROM without_overlaps_test WHERE id = '[5,5]';

--
-- test FK parent deletes NO ACTION
--

ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test;
-- a PK delete that succeeds because the numeric id isn't referenced:
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-01-01', '2018-02-01');
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
-- a PK delete that succeeds even though the numeric id is referenced because the range isn't:
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-01-01', '2018-02-01');
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-02-01', '2018-03-01');
INSERT INTO referencing_period_test VALUES ('[3,3]', '2018-01-05', '2018-01-10', '[5,5]');
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_from = '2018-02-01' AND valid_til = '2018-03-01';
-- a PK delete that fails because both are referenced:
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_from = '2018-01-01' AND valid_til = '2018-02-01';
-- then delete the objecting FK record and the same PK delete succeeds:
DELETE FROM referencing_period_test WHERE id = '[3,3]';
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_from = '2018-01-01' AND valid_til = '2018-02-01';

--
-- test FK parent deletes RESTRICT
--

ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk;
ALTER TABLE referencing_period_test
	ADD CONSTRAINT referencing_period_fk
	FOREIGN KEY (parent_id, PERIOD valid_at)
	REFERENCES without_overlaps_test
	ON DELETE RESTRICT;
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-01-01', '2018-02-01');
DELETE FROM without_overlaps_test WHERE id = '[5,5]';
-- a PK delete that succeeds even though the numeric id is referenced because the range isn't:
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-01-01', '2018-02-01');
INSERT INTO without_overlaps_test VALUES ('[5,5]', '2018-02-01', '2018-03-01');
INSERT INTO referencing_period_test VALUES ('[3,3]', '2018-01-05', '2018-01-10', '[5,5]');
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_from = '2018-02-01' AND valid_til = '2018-03-01';
-- a PK delete that fails because both are referenced:
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_from = '2018-01-01' AND valid_til = '2018-02-01';
-- then delete the objecting FK record and the same PK delete succeeds:
DELETE FROM referencing_period_test WHERE id = '[3,3]';
DELETE FROM without_overlaps_test WHERE id = '[5,5]' AND valid_from = '2018-01-01' AND valid_til = '2018-02-01';

--
-- test ON UPDATE/DELETE options
--

-- test FK parent updates CASCADE
INSERT INTO without_overlaps_test VALUES ('[6,6]', '2018-01-01', '2021-01-01');
INSERT INTO referencing_period_test VALUES ('[4,4]', '2018-01-01', '2021-01-01', '[6,6]');
ALTER TABLE referencing_period_test
	DROP CONSTRAINT referencing_period_fk,
	ADD CONSTRAINT referencing_period_fk
		FOREIGN KEY (parent_id, PERIOD valid_at)
		REFERENCES without_overlaps_test
		ON DELETE CASCADE ON UPDATE CASCADE;
UPDATE without_overlaps_test FOR PORTION OF valid_at FROM '2019-01-01' TO '2020-01-01' SET id = '[7,7]' WHERE id = '[6,6]';
SELECT * FROM referencing_period_test WHERE id = '[4,4]';
UPDATE without_overlaps_test SET id = '[7,7]' WHERE id = '[6,6]';
SELECT * FROM referencing_period_test WHERE id = '[4,4]';

-- test FK parent deletes CASCADE
INSERT INTO without_overlaps_test VALUES ('[8,8]', '2018-01-01', '2021-01-01');
INSERT INTO referencing_period_test VALUES ('[5,5]', '2018-01-01', '2021-01-01', '[8,8]');
DELETE FROM without_overlaps_test FOR PORTION OF valid_at FROM '2019-01-01' TO '2020-01-01' WHERE id = '[8,8]';
SELECT * FROM referencing_period_test WHERE id = '[5,5]';
DELETE FROM without_overlaps_test WHERE id = '[8,8]';
SELECT * FROM referencing_period_test WHERE id = '[5,5]';

-- test FK parent updates SET NULL
-- TODO
-- test FK parent deletes SET NULL
-- TODO
-- test FK parent updates SET DEFAULT
-- TODO
-- test FK parent deletes SET DEFAULT
-- TODO
-- test cascades through a FOR PORTION OF

