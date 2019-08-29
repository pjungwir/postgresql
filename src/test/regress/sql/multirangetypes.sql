-- Tests for multirange data types.

--
-- test input parser
--

-- negative tests; should fail
select ''::textmultirange;
select '{,}'::textmultirange;
select '{[a,c),}'::textmultirange;
select '{,[a,c)}'::textmultirange;
select '{-[a,z)}'::textmultirange;
select '{[a,z) - }'::textmultirange;
select '{(",a)}'::textmultirange;
select '{(,,a)}'::textmultirange;
select '{(),a)}'::textmultirange;
select '{(a,))}'::textmultirange;
select '{(],a)}'::textmultirange;
select '{(a,])}'::textmultirange;
select '{[z,a]}'::textmultirange;

-- should succeed
select '{}'::textmultirange;
select '  {}  '::textmultirange;
select ' { empty, empty }  '::textmultirange;
select ' {( " a " " a ", " z " " z " )  }'::textmultirange;
select '{(,z)}'::textmultirange;
select '{(a,)}'::textmultirange;
select '{[,z]}'::textmultirange;
select '{[a,]}'::textmultirange;
select '{(,)}'::textmultirange;
select '{[ , ]}'::textmultirange;
select '{["",""]}'::textmultirange;
select '{[",",","]}'::textmultirange;
select '{["\\","\\"]}'::textmultirange;
select '{(\\,a)}'::textmultirange;
select '{((,z)}'::textmultirange;
select '{([,z)}'::textmultirange;
select '{(!,()}'::textmultirange;
select '{(!,[)}'::textmultirange;
select '{[a,a]}'::textmultirange;
select '{[a,a],[a,b]}'::textmultirange;
select '{[a,b), [b,e]}'::textmultirange;
select '{[a,d), [b,f]}'::textmultirange;
select '{[a,a],[b,b]}'::textmultirange;
-- without canonicalization, we can't join these:
select '{[a,a], [b,b]}'::textmultirange;
-- with canonicalization, we can join these:
select '{[1,2], [3,4]}'::int4multirange;
select '{[a,a], [b,b], [c,c]}'::textmultirange;
select '{[a,d], [b,e]}'::textmultirange;
select '{[a,d), [d,e)}'::textmultirange;
-- these are allowed but normalize to empty:
select '{[a,a)}'::textmultirange;
select '{(a,a]}'::textmultirange;
select '{(a,a)}'::textmultirange;

--
-- test the constructor
---
select textmultirange();
select textmultirange(textrange('a', 'c'));
select textmultirange(textrange('a', 'c'), textrange('f', 'g'));
select textmultirange(textrange('a', 'c'), textrange('b', 'd'));

--
-- create some test data and test the operators
--

CREATE TABLE nummultirange_test (nmr NUMMULTIRANGE);
CREATE INDEX nummultirange_test_btree ON nummultirange_test(nmr);

INSERT INTO nummultirange_test VALUES('{}');
INSERT INTO nummultirange_test VALUES('{[,)}');
INSERT INTO nummultirange_test VALUES('{[3,]}');
INSERT INTO nummultirange_test VALUES('{[,), [3,]}');
INSERT INTO nummultirange_test VALUES('{[, 5)}');
INSERT INTO nummultirange_test VALUES(nummultirange());
INSERT INTO nummultirange_test VALUES(nummultirange(variadic '{}'::numrange[]));
INSERT INTO nummultirange_test VALUES(nummultirange(numrange(1.1, 2.2)));
INSERT INTO nummultirange_test VALUES('{empty}');
INSERT INTO nummultirange_test VALUES(nummultirange(numrange(1.7, 1.7, '[]'), numrange(1.7, 1.9)));
INSERT INTO nummultirange_test VALUES(nummultirange(numrange(1.7, 1.7, '[]'), numrange(1.9, 2.1)));

SELECT nmr, isempty(nmr) FROM nummultirange_test ORDER BY nmr;

-- mr contains x
SELECT * FROM nummultirange_test WHERE multirange_contains_elem(nmr, 4.0);
SELECT * FROM nummultirange_test WHERE nmr @> 4.0;
SELECT * FROM nummultirange_test WHERE multirange_contains_range(nmr, numrange(4.0, 4.2));
SELECT * FROM nummultirange_test WHERE nmr @> numrange(4.0, 4.2);
SELECT * FROM nummultirange_test WHERE multirange_contains_multirange(nmr, '{[4.0,4.2), [6.0, 8.0)}');
SELECT * FROM nummultirange_test WHERE nmr @> '{[4.0,4.2), [6.0, 8.0)}'::nummultirange;

-- x is contained by mr
SELECT * FROM nummultirange_test WHERE elem_contained_by_multirange(4.0, nmr);
SELECT * FROM nummultirange_test WHERE 4.0 <@ nmr;
SELECT * FROM nummultirange_test WHERE range_contained_by_multirange(numrange(4.0, 4.2), nmr);
SELECT * FROM nummultirange_test WHERE numrange(4.0, 4.2) <@ nmr;
SELECT * FROM nummultirange_test WHERE multirange_contained_by_multirange('{[4.0,4.2), [6.0, 8.0)}', nmr);
SELECT * FROM nummultirange_test WHERE '{[4.0,4.2), [6.0, 8.0)}'::nummultirange <@ nmr;

-- TODO: more, see rangetypes.sql

-- first, verify non-indexed results
SET enable_seqscan    = t;
SET enable_indexscan  = f;
SET enable_bitmapscan = f;

select * from nummultirange_test where nmr = '{[3,]}';

-- TODO: more, see rangetypes.sql

-- now check same queries using index
SET enable_seqscan    = f;
SET enable_indexscan  = t;
SET enable_bitmapscan = f;
select * from nummultirange_test where nmr = '{[3,]}';

-- TODO: more, see rangetypes.sql

RESET enable_seqscan;
RESET enable_indexscan;
RESET enable_bitmapscan;

-- TODO: more, see rangetypes.sql
