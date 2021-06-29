-- Tests for WITHOUT OVERLAPS.
--
-- We leave behind several tables to test pg_dump etc:
-- temporal_rng, temporal_per, temporal_rng2, temporal_per2,
-- temporal_fk_{rng,per}2{rng,per}.

--
-- test input parser
--

-- PK with no columns just WITHOUT OVERLAPS:

CREATE TABLE temporal_rng (
	valid_at tsrange,
	CONSTRAINT temporal_rng_pk PRIMARY KEY (valid_at WITHOUT OVERLAPS)
);

-- PK with a range column/PERIOD that isn't there:

CREATE TABLE temporal_rng (
	id INTEGER,
	CONSTRAINT temporal_rng_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);

-- PK with a non-range column:

CREATE TABLE temporal_rng (
	id INTEGER,
	valid_at TEXT,
	CONSTRAINT temporal_rng_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);

-- PK with one column plus a range:

CREATE TABLE temporal_rng (
	-- Since we can't depend on having btree_gist here,
	-- use an int4range instead of an int.
	-- (The rangetypes regression test uses the same trick.)
	id int4range,
	valid_at tsrange,
	CONSTRAINT temporal_rng_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);
\d temporal_rng
SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'temporal_rng_pk';
SELECT pg_get_indexdef(conindid, 0, true) FROM pg_constraint WHERE conname = 'temporal_rng_pk';

-- PK with two columns plus a range:
CREATE TABLE temporal_rng2 (
	id1 int4range,
	id2 int4range,
	valid_at tsrange,
	CONSTRAINT temporal_rng2_pk PRIMARY KEY (id1, id2, valid_at WITHOUT OVERLAPS)
);
\d temporal_rng2
SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'temporal_rng2_pk';
SELECT pg_get_indexdef(conindid, 0, true) FROM pg_constraint WHERE conname = 'temporal_rng2_pk';
DROP TABLE temporal_rng2;


-- PK with one column plus a PERIOD:
CREATE TABLE temporal_per (
	id int4range,
	valid_from timestamp,
	valid_til timestamp,
	PERIOD FOR valid_at (valid_from, valid_til),
	CONSTRAINT temporal_per_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);
\d temporal_per
SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'temporal_per_pk';
SELECT pg_get_indexdef(conindid, 0, true) FROM pg_constraint WHERE conname = 'temporal_per_pk';

-- PK with two columns plus a PERIOD:
CREATE TABLE temporal_per2 (
	id1 int4range,
	id2 int4range,
	valid_from timestamp,
	valid_til timestamp,
	PERIOD FOR valid_at (valid_from, valid_til),
	CONSTRAINT temporal_per2_pk PRIMARY KEY (id1, id2, valid_at WITHOUT OVERLAPS)
);
\d temporal_per2
SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'temporal_per2_pk';
SELECT pg_get_indexdef(conindid, 0, true) FROM pg_constraint WHERE conname = 'temporal_per2_pk';
DROP TABLE temporal_per2;

-- PK with a custom range type:
CREATE TYPE textrange2 AS range (subtype=text, collation="C");
CREATE TABLE temporal_rng2 (
	id int4range,
	valid_at textrange2,
	CONSTRAINT temporal_rng2_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
);
ALTER TABLE temporal_rng2 DROP CONSTRAINT temporal_rng2_pk;
DROP TABLE temporal_rng2;
DROP TYPE textrange2;

-- UNIQUE with no columns just WITHOUT OVERLAPS:

CREATE TABLE temporal_rng2 (
	valid_at tsrange,
	CONSTRAINT temporal_rng2_uq UNIQUE (valid_at WITHOUT OVERLAPS)
);

-- UNIQUE with a range column/PERIOD that isn't there:

CREATE TABLE temporal_rng2 (
	id INTEGER,
	CONSTRAINT temporal_rng2_uq UNIQUE (id, valid_at WITHOUT OVERLAPS)
);

-- UNIQUE with a non-range column:

CREATE TABLE temporal_rng2 (
	id INTEGER,
	valid_at TEXT,
	CONSTRAINT temporal_rng2_uq UNIQUE (id, valid_at WITHOUT OVERLAPS)
);

-- UNIQUE with one column plus a range:

CREATE TABLE temporal_rng2 (
	-- Since we can't depend on having btree_gist here,
	-- use an int4range instead of an int.
	-- (The rangetypes regression test uses the same trick.)
	id int4range,
	valid_at tsrange,
	CONSTRAINT temporal_rng2_uq UNIQUE (id, valid_at WITHOUT OVERLAPS)
);
\d temporal_rng2
SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'temporal_rng2_uq';
SELECT pg_get_indexdef(conindid, 0, true) FROM pg_constraint WHERE conname = 'temporal_rng2_uq';

-- UNIQUE with two columns plus a range:
CREATE TABLE temporal_rng3 (
	id1 int4range,
	id2 int4range,
	valid_at tsrange,
	CONSTRAINT temporal_rng3_uq UNIQUE (id1, id2, valid_at WITHOUT OVERLAPS)
);
\d temporal_rng3
SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'temporal_rng3_uq';
SELECT pg_get_indexdef(conindid, 0, true) FROM pg_constraint WHERE conname = 'temporal_rng3_uq';
DROP TABLE temporal_rng3;

-- UNIQUE with one column plus a PERIOD:
CREATE TABLE temporal_per2 (
	id int4range,
	valid_from timestamp,
	valid_til timestamp,
	PERIOD FOR valid_at (valid_from, valid_til),
	CONSTRAINT temporal_per2_uq UNIQUE (id, valid_at WITHOUT OVERLAPS)
);
\d temporal_per2
SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'temporal_per2_uq';
SELECT pg_get_indexdef(conindid, 0, true) FROM pg_constraint WHERE conname = 'temporal_per2_uq';

-- UNIQUE with two columns plus a PERIOD:
CREATE TABLE temporal_per3 (
	id1 int4range,
	id2 int4range,
	valid_from timestamp,
	valid_til timestamp,
	PERIOD FOR valid_at (valid_from, valid_til),
	CONSTRAINT temporal_per3_uq UNIQUE (id1, id2, valid_at WITHOUT OVERLAPS)
);
\d temporal_per3
SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'temporal_per3_uq';
SELECT pg_get_indexdef(conindid, 0, true) FROM pg_constraint WHERE conname = 'temporal_per3_uq';
DROP TABLE temporal_per3;

-- UNIQUE with a custom range type:
CREATE TYPE textrange2 AS range (subtype=text, collation="C");
CREATE TABLE temporal_per3 (
	id int4range,
	valid_at textrange2,
	CONSTRAINT temporal_per3_uq UNIQUE (id, valid_at WITHOUT OVERLAPS)
);
ALTER TABLE temporal_per3 DROP CONSTRAINT temporal_per3_uq;
DROP TABLE temporal_per3;
DROP TYPE textrange2;

--
-- test ALTER TABLE ADD CONSTRAINT
--

DROP TABLE temporal_rng;
CREATE TABLE temporal_rng (
	id int4range,
	valid_at tsrange
);
ALTER TABLE temporal_rng
	ADD CONSTRAINT temporal_rng_pk
	PRIMARY KEY (id, valid_at WITHOUT OVERLAPS);

-- PK with USING INDEX (not possible):
CREATE TABLE temporal3 (
	id int4range,
	valid_at tsrange
);
CREATE INDEX idx_temporal3_uq ON temporal3 USING gist (id, valid_at);
ALTER TABLE temporal3
	ADD CONSTRAINT temporal3_pk
	PRIMARY KEY USING INDEX idx_temporal3_uq;
DROP TABLE temporal3;

-- UNIQUE with USING INDEX (not possible):
CREATE TABLE temporal3 (
	id int4range,
	valid_at tsrange
);
CREATE INDEX idx_temporal3_uq ON temporal3 USING gist (id, valid_at);
ALTER TABLE temporal3
	ADD CONSTRAINT temporal3_uq
	UNIQUE USING INDEX idx_temporal3_uq;
DROP TABLE temporal3;

-- Add range column and the PK at the same time
CREATE TABLE temporal3 (
	id int4range
);
ALTER TABLE temporal3
	ADD COLUMN valid_at tsrange,
	ADD CONSTRAINT temporal3_pk
	PRIMARY KEY (id, valid_at WITHOUT OVERLAPS);
DROP TABLE temporal3;

-- Add PERIOD and the PK at the same time
CREATE TABLE temporal3 (
	id int4range,
	valid_from date,
	valid_til date
);
ALTER TABLE temporal3
	ADD PERIOD FOR valid_at (valid_from, valid_til),
	ADD CONSTRAINT temporal3_pk
	PRIMARY KEY (id, valid_at WITHOUT OVERLAPS);
DROP TABLE temporal3;

-- Add range column and UNIQUE constraint at the same time
CREATE TABLE temporal3 (
	id int4range
);
ALTER TABLE temporal3
	ADD COLUMN valid_at tsrange,
	ADD CONSTRAINT temporal3_uq
	UNIQUE (id, valid_at WITHOUT OVERLAPS);
DROP TABLE temporal3;

-- Add PERIOD column and UNIQUE constraint at the same time
CREATE TABLE temporal3 (
	id int4range,
	valid_from date,
	valid_til date
);
ALTER TABLE temporal3
	ADD PERIOD FOR valid_at (valid_from, valid_til),
	ADD CONSTRAINT temporal3_uq
	UNIQUE (id, valid_at WITHOUT OVERLAPS);
DROP TABLE temporal3;

-- Add date columns, PERIOD, and the PK at the same time
CREATE TABLE temporal3 (
	id int4range
);
ALTER TABLE temporal3
	ADD COLUMN valid_from date,
	ADD COLUMN valid_til date,
	ADD PERIOD FOR valid_at (valid_from, valid_til),
	ADD CONSTRAINT temporal3_pk
	PRIMARY KEY (id, valid_at WITHOUT OVERLAPS);
DROP TABLE temporal3;

-- Add date columns, PERIOD, and UNIQUE constraint at the same time
CREATE TABLE temporal3 (
	id int4range
);
ALTER TABLE temporal3
	ADD COLUMN valid_from date,
	ADD COLUMN valid_til date,
	ADD PERIOD FOR valid_at (valid_from, valid_til),
	ADD CONSTRAINT temporal3_uq
	UNIQUE (id, valid_at WITHOUT OVERLAPS);
DROP TABLE temporal3;

--
-- test PK inserts
--

-- okay:
INSERT INTO temporal_rng VALUES ('[1,1]', tsrange('2018-01-02', '2018-02-03'));
INSERT INTO temporal_rng VALUES ('[1,1]', tsrange('2018-03-03', '2018-04-04'));
INSERT INTO temporal_rng VALUES ('[2,2]', tsrange('2018-01-01', '2018-01-05'));
INSERT INTO temporal_rng VALUES ('[3,3]', tsrange('2018-01-01', NULL));

-- should fail:
INSERT INTO temporal_rng VALUES ('[1,1]', tsrange('2018-01-01', '2018-01-05'));
INSERT INTO temporal_rng VALUES (NULL, tsrange('2018-01-01', '2018-01-05'));
INSERT INTO temporal_rng VALUES ('[3,3]', NULL);

--
-- test a range with both a PK and a UNIQUE constraint
--

CREATE TABLE temporal3 (
  id int4range,
  valid_at tsrange,
  id2 int8range,
  name TEXT,
  CONSTRAINT temporal3_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS),
  CONSTRAINT temporal3_uniq UNIQUE (id2, valid_at WITHOUT OVERLAPS)
);
INSERT INTO temporal3 (id, valid_at, id2, name)
  VALUES
  ('[1,1]', tsrange('2000-01-01', '2010-01-01'), '[7,7]', 'foo'),
  ('[2,2]', tsrange('2000-01-01', '2010-01-01'), '[9,9]', 'bar')
;
UPDATE without_overlaps_test2 FOR PORTION OF valid_at FROM '2000-05-01' TO '2000-07-01'
  SET name = name || '1';
UPDATE without_overlaps_test2 FOR PORTION OF valid_at FROM '2000-04-01' TO '2000-06-01'
  SET name = name || '2'
  WHERE id = '[2,2]';
SELECT * FROM without_overlaps_test2 ORDER BY id, valid_at;
-- conflicting id only:
INSERT INTO without_overlaps_test2 (id, valid_at, id2, name)
  VALUES
  ('[1,1]', tsrange('2005-01-01', '2006-01-01'), '[8,8]', 'foo3');
-- conflicting id2 only:
INSERT INTO without_overlaps_test2 (id, valid_at, id2, name)
  VALUES
  ('[3,3]', tsrange('2005-01-01', '2010-01-01'), '[9,9]', 'bar3')
;
DROP TABLE without_overlaps_test2;

--
-- test a PERIOD with both a PK and a UNIQUE constraint
--

CREATE TABLE without_overlaps_test2 (
  id int4range,
	valid_from timestamp,
	valid_til timestamp,
	PERIOD FOR valid_at (valid_from, valid_til),
  id2 int8range,
  name TEXT,
  CONSTRAINT without_overlaps_test2_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS),
  CONSTRAINT without_overlaps_test2_uniq UNIQUE (id2, valid_at WITHOUT OVERLAPS)
);
INSERT INTO without_overlaps_test2 (id, valid_from, valid_til, id2, name)
  VALUES
  ('[1,1]', '2000-01-01', '2010-01-01', '[7,7]', 'foo'),
  ('[2,2]', '2000-01-01', '2010-01-01', '[9,9]', 'bar')
;
UPDATE without_overlaps_test2 FOR PORTION OF valid_at FROM '2000-05-01' TO '2000-07-01'
  SET name = name || '1';
UPDATE without_overlaps_test2 FOR PORTION OF valid_at FROM '2000-04-01' TO '2000-06-01'
  SET name = name || '2'
  WHERE id = '[2,2]';
SELECT * FROM without_overlaps_test2 ORDER BY id, valid_from, valid_til;
-- conflicting id only:
INSERT INTO without_overlaps_test2 (id, valid_from, valid_til, id2, name)
  VALUES
  ('[1,1]', '2005-01-01', '2006-01-01', '[8,8]', 'foo3');
-- conflicting id2 only:
INSERT INTO without_overlaps_test2 (id, valid_from, valid_til, id2, name)
  VALUES
  ('[3,3]', '2005-01-01', '2010-01-01', '[9,9]', 'bar3')
;
DROP TABLE without_overlaps_test2;

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
-- test PARTITION BY for ranges
--

CREATE TABLE temporal_partitioned (
	id int4range,
	valid_at daterange,
	CONSTRAINT temporal_paritioned_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
) PARTITION BY LIST (id);
-- TODO: attach some partitions, insert into them, update them with and without FOR PORTION OF, delete them the same way.

--
-- test PARTITION BY for PERIODS
--

CREATE TABLE temporal_partitioned (
  id int4range,
  valid_from TIMESTAMP,
  valid_til TIMESTAMP,
  PERIOD FOR valid_at (valid_from, valid_til),
	CONSTRAINT temporal_paritioned_pk PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)
) PARTITION BY LIST (id);
-- TODO: attach some partitions, insert into them, update them with and without FOR PORTION OF, delete them the same way.
