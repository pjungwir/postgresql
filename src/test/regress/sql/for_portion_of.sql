-- Tests for UPDATE/DELETE FOR PORTION OF

--
-- test input parser
--

-- tables are without_overlaps_test
SELECT * FROM without_overlaps_test;

explain analyze UPDATE without_overlaps_test
FOR PORTION OF valid_at FROM '2018-06-01' TO 'infinity'
-- too add a non PK column so we have something to update:
SET id = '[5,6)'
WHERE id = '[3,4)';

SELECT * FROM without_overlaps_test;

UPDATE without_overlaps_test
FOR PORTION OF valid_at FROM '2018-06-01' TO 'infinity'
-- too add a non PK column so we have something to update:
SET id = '[6,7)',
    valid_at = '[1990-01-01,1999-01-01)'
WHERE id = '[5,6)';

SELECT * FROM without_overlaps_test;
