--
-- Test GiST indexes.
--
-- There are other tests to test different GiST opclasses. This is for
-- testing GiST code itself. Vacuuming in particular.

create table gist_point_tbl(id int4, p point);
create index gist_pointidx on gist_point_tbl using gist(p);

-- Verify the fillfactor and buffering options
create index gist_pointidx2 on gist_point_tbl using gist(p) with (buffering = on, fillfactor=50);
create index gist_pointidx3 on gist_point_tbl using gist(p) with (buffering = off);
create index gist_pointidx4 on gist_point_tbl using gist(p) with (buffering = auto);
drop index gist_pointidx2, gist_pointidx3, gist_pointidx4;

-- Make sure bad values are refused
create index gist_pointidx5 on gist_point_tbl using gist(p) with (buffering = invalid_value);
create index gist_pointidx5 on gist_point_tbl using gist(p) with (fillfactor=9);
create index gist_pointidx5 on gist_point_tbl using gist(p) with (fillfactor=101);

-- Insert enough data to create a tree that's a couple of levels deep.
insert into gist_point_tbl (id, p)
select g,        point(g*10, g*10) from generate_series(1, 10000) g;

insert into gist_point_tbl (id, p)
select g+100000, point(g*10+1, g*10+1) from generate_series(1, 10000) g;

-- To test vacuum, delete some entries from all over the index.
delete from gist_point_tbl where id % 2 = 1;

-- And also delete some concentration of values.
delete from gist_point_tbl where id > 5000;

vacuum analyze gist_point_tbl;

-- rebuild the index with a different fillfactor
alter index gist_pointidx SET (fillfactor = 40);
reindex index gist_pointidx;

--
-- Test Index-only plans on GiST indexes
--

create table gist_tbl (b box, p point, c circle);

insert into gist_tbl
select box(point(0.05*i, 0.05*i), point(0.05*i, 0.05*i)),
       point(0.05*i, 0.05*i),
       circle(point(0.05*i, 0.05*i), 1.0)
from generate_series(0,10000) as i;

vacuum analyze gist_tbl;

set enable_seqscan=off;
set enable_bitmapscan=off;
set enable_indexonlyscan=on;

-- Test index-only scan with point opclass
create index gist_tbl_point_index on gist_tbl using gist (p);

-- check that the planner chooses an index-only scan
explain (costs off)
select p from gist_tbl where p <@ box(point(0,0), point(0.5, 0.5));

-- execute the same
select p from gist_tbl where p <@ box(point(0,0), point(0.5, 0.5));

-- Also test an index-only knn-search
explain (costs off)
select p from gist_tbl where p <@ box(point(0,0), point(0.5, 0.5))
order by p <-> point(0.201, 0.201);

select p from gist_tbl where p <@ box(point(0,0), point(0.5, 0.5))
order by p <-> point(0.201, 0.201);

-- Check commuted case as well
explain (costs off)
select p from gist_tbl where p <@ box(point(0,0), point(0.5, 0.5))
order by point(0.101, 0.101) <-> p;

select p from gist_tbl where p <@ box(point(0,0), point(0.5, 0.5))
order by point(0.101, 0.101) <-> p;

-- Check case with multiple rescans (bug #14641)
explain (costs off)
select p from
  (values (box(point(0,0), point(0.5,0.5))),
          (box(point(0.5,0.5), point(0.75,0.75))),
          (box(point(0.8,0.8), point(1.0,1.0)))) as v(bb)
cross join lateral
  (select p from gist_tbl where p <@ bb order by p <-> bb[0] limit 2) ss;

select p from
  (values (box(point(0,0), point(0.5,0.5))),
          (box(point(0.5,0.5), point(0.75,0.75))),
          (box(point(0.8,0.8), point(1.0,1.0)))) as v(bb)
cross join lateral
  (select p from gist_tbl where p <@ bb order by p <-> bb[0] limit 2) ss;

drop index gist_tbl_point_index;

-- Test index-only scan with box opclass
create index gist_tbl_box_index on gist_tbl using gist (b);

-- check that the planner chooses an index-only scan
explain (costs off)
select b from gist_tbl where b <@ box(point(5,5), point(6,6));

-- execute the same
select b from gist_tbl where b <@ box(point(5,5), point(6,6));

-- Also test an index-only knn-search
explain (costs off)
select b from gist_tbl where b <@ box(point(5,5), point(6,6))
order by b <-> point(5.2, 5.91);

select b from gist_tbl where b <@ box(point(5,5), point(6,6))
order by b <-> point(5.2, 5.91);

-- Check commuted case as well
explain (costs off)
select b from gist_tbl where b <@ box(point(5,5), point(6,6))
order by point(5.2, 5.91) <-> b;

select b from gist_tbl where b <@ box(point(5,5), point(6,6))
order by point(5.2, 5.91) <-> b;

drop index gist_tbl_box_index;

-- Test that an index-only scan is not chosen, when the query involves the
-- circle column (the circle opclass does not support index-only scans).
create index gist_tbl_multi_index on gist_tbl using gist (p, c);

explain (costs off)
select p, c from gist_tbl
where p <@ box(point(5,5), point(6, 6));

-- execute the same
select b, p from gist_tbl
where b <@ box(point(4.5, 4.5), point(5.5, 5.5))
and p <@ box(point(5,5), point(6, 6));

drop index gist_tbl_multi_index;

-- Test that we don't try to return the value of a non-returnable
-- column in an index-only scan.  (This isn't GIST-specific, but
-- it only applies to index AMs that can return some columns and not
-- others, so GIST with appropriate opclasses is a convenient test case.)
create index gist_tbl_multi_index on gist_tbl using gist (circle(p,1), p);
explain (verbose, costs off)
select circle(p,1) from gist_tbl
where p <@ box(point(5, 5), point(5.3, 5.3));
select circle(p,1) from gist_tbl
where p <@ box(point(5, 5), point(5.3, 5.3));

-- Similarly, test that index rechecks involving a non-returnable column
-- are done correctly.
explain (verbose, costs off)
select p from gist_tbl where circle(p,1) @> circle(point(0,0),0.95);
select p from gist_tbl where circle(p,1) @> circle(point(0,0),0.95);

-- Also check that use_physical_tlist doesn't trigger in such cases.
explain (verbose, costs off)
select count(*) from gist_tbl;
select count(*) from gist_tbl;

-- This case isn't supported, but it should at least EXPLAIN correctly.
explain (verbose, costs off)
select p from gist_tbl order by circle(p,1) <-> point(0,0) limit 1;
select p from gist_tbl order by circle(p,1) <-> point(0,0) limit 1;

-- Test that an index-only scan deforms the tuple it reconstructs with the
-- descriptor the AM formed it with, not the scan slot's descriptor.
create temp table gist_ios_tupdesc (a inet, r numrange);

-- range_ops forms its tuples using the opclass input type, the polymorphic
-- anyrange (alignment 'd'), while the scan slot uses the actual range type
-- numrange (alignment 'i').  A buggy implementation will incorrectly access
-- the r/numrange column at the wrong offset.
--
-- The range bounds are made long so the value needs a four-byte varlena
-- header; shorter values get a one-byte header and are stored without
-- alignment padding, which would mask the problem.
insert into gist_ios_tupdesc
values (
        '::1', -- shifts "r" datum value to differing offset
        numrange(repeat('7', 200)::numeric, repeat('8', 200)::numeric));
create index on gist_ios_tupdesc using gist (a inet_ops, r);
vacuum analyze gist_ios_tupdesc;

explain (costs off)
select lower(r) = repeat('7', 200)::numeric as lower_ok,
       upper(r) = repeat('8', 200)::numeric as upper_ok
  from gist_ios_tupdesc where r && numrange(null, null);
select lower(r) = repeat('7', 200)::numeric as lower_ok,
       upper(r) = repeat('8', 200)::numeric as upper_ok
  from gist_ios_tupdesc where r && numrange(null, null);

drop table gist_ios_tupdesc;

-- test deletion of LP_DEAD-marked index tuples
create table gist_prune_tbl (k int, p point);
create index gist_prune_tbl_p_index on gist_prune_tbl using gist (p);

begin;
insert into gist_prune_tbl select i, point(1, i) from generate_series(1, 600) i;
rollback;

set enable_bitmapscan = off;
set enable_indexonlyscan = off;
set enable_seqscan = off;

select count(*) from gist_prune_tbl where p <@ box(point(0,0), point(2,1000));
insert into gist_prune_tbl select i, point(1, i) from generate_series(1, 600) i;
select count(*) from gist_prune_tbl where p <@ box(point(0,0), point(2,1000));

reset enable_bitmapscan;
reset enable_indexonlyscan;
reset enable_seqscan;
drop table gist_prune_tbl;

-- Force an index build using buffering.
create index gist_tbl_box_index_forcing_buffering on gist_tbl using gist (p)
  with (buffering=on, fillfactor=50);

-- Unique indexes need an equality operator in the opclass's operator family.
-- tsvector_ops has only @@, so there is nothing to translate COMPARE_EQ to:
create table gist_tsvtbl (t tsvector);
create unique index on gist_tsvtbl using gist (t); -- fail
drop table gist_tsvtbl;

-- Unique indexes, no compress function:
create table gist_rngtbl (id int4range);
insert into gist_rngtbl values ('[1,2)'), ('[2,3)'), (NULL), (NULL);
create unique index uq_gist_rngtbl on gist_rngtbl using gist (id);
insert into gist_rngtbl values ('[3,4)'), ('[4,5)'); -- okay
\d gist_rngtbl
select pg_get_indexdef('uq_gist_rngtbl'::regclass);
-- enforced on build
drop index uq_gist_rngtbl;
insert into gist_rngtbl values ('[1,2)');
create unique index uq_gist_rngtbl on gist_rngtbl using gist (id); -- fail
-- expressions:
delete from gist_rngtbl where id is null;
create unique index uq_gist_rngtbl_expr on gist_rngtbl using gist (
  int4range(lower(id) + 1, upper(id) + 1)
); -- fail
delete from gist_rngtbl where id = '[1,2)';
create unique index uq_gist_rngtbl_expr on gist_rngtbl using gist (
  int4range(lower(id) + 1, upper(id) + 1)
); -- now okay
truncate gist_rngtbl;
drop index uq_gist_rngtbl_expr;
-- enforced on insert
create unique index uq_gist_rngtbl on gist_rngtbl using gist (id);
insert into gist_rngtbl values ('[1,2)'), ('[2,3)'); -- okay
insert into gist_rngtbl values (NULL), (NULL); -- okay
insert into gist_rngtbl values ('[1,2)'); -- fail
drop table gist_rngtbl;

-- Unique indexes, NULLS NOT DISTINCT:
create table gist_rngtbl (id int4range);
-- enforced on build
insert into gist_rngtbl values (NULL), (NULL);
create unique index uq_gist_rngtbl on gist_rngtbl using gist (id) nulls not distinct; -- fail
-- enforced on insert
delete from gist_rngtbl;
create unique index uq_gist_rngtbl on gist_rngtbl using gist (id) nulls not distinct; -- okay
insert into gist_rngtbl values (NULL); -- okay
insert into gist_rngtbl values (NULL); -- fail
drop table gist_rngtbl;

-- Unique indexes, compress function and lossy keys (e.g. multiranges):
create table gist_mltrngtbl (id int4multirange);
insert into gist_mltrngtbl values ('{[1,10)}'), ('{[20,30)}');
create unique index uq_gist_mltrngtbl on gist_mltrngtbl using gist (id);
insert into gist_mltrngtbl values ('{[3,4)}'), ('{[4,5)}'); -- okay
\d gist_mltrngtbl
select pg_get_indexdef('uq_gist_mltrngtbl'::regclass);
-- enforced on build
drop index uq_gist_mltrngtbl;
insert into gist_mltrngtbl values ('{[1,10)}');
create unique index uq_gist_mltrngtbl on gist_mltrngtbl using gist (id); -- fail
-- expressions:
create unique index uq_gist_mltrngtbl_expr on gist_mltrngtbl using gist (
  (id + '{[100,200)}')
); -- fail
delete from gist_mltrngtbl where id = '{[1,10)}';
create unique index uq_gist_mltrngtbl_expr on gist_mltrngtbl using gist (
  (id + '{[100,200)}')
); -- now okay
truncate gist_mltrngtbl;
drop index uq_gist_mltrngtbl_expr;
-- enforced on insert
create unique index uq_gist_mltrngtbl on gist_mltrngtbl using gist (id);
insert into gist_mltrngtbl values ('{[1,10)}'), ('{[20,30)}'); -- okay
-- okay, even though compresses to [1,10):
insert into gist_mltrngtbl values ('{[1,3), [8,10)}');
insert into gist_mltrngtbl values ('{[1,10)}'); -- fails, exact duplicate
drop table gist_mltrngtbl;

-- Duplicates can be in any leaf page whose ancestors' keys are consistent with
-- the new value, not only the page an insert descends to, so make sure we look
-- at the whole tree.  These keys overlap enough that the index has several
-- pages with overlapping downlinks.
create table gist_uniqtbl (id int4range);
insert into gist_uniqtbl
  select int4range((i * 7919) % 3000, (i * 7919) % 3000 + 1 + i % 13)
  from generate_series(1, 3000) i;
create unique index uq_gist_uniqtbl on gist_uniqtbl using gist (id);
do $$
declare
  r record;
  missed int := 0;
begin
  for r in select id from gist_uniqtbl loop
    begin
      insert into gist_uniqtbl values (r.id);
      missed := missed + 1;
    exception when unique_violation then
      null;
    end;
  end loop;
  raise notice 'missed % duplicates', missed;
end
$$;
drop table gist_uniqtbl;

-- A buffered build is validated afterwards like any other:
create table gist_buftbl (id int4range);
insert into gist_buftbl select int4range(i, i + 1) from generate_series(1, 2000) i;
insert into gist_buftbl values ('[1000,1001)');
create unique index uq_gist_buftbl on gist_buftbl using gist (id)
  with (buffering = on); -- fail
delete from gist_buftbl where ctid = (select max(ctid) from gist_buftbl);
create unique index uq_gist_buftbl on gist_buftbl using gist (id)
  with (buffering = on); -- okay
drop table gist_buftbl;

-- Unique indexes as ON CONFLICT arbiters:
create table gist_rngtbl (id int4range, n int);
create unique index uq_gist_rngtbl on gist_rngtbl using gist (id);
insert into gist_rngtbl values ('[1,2)', 1);
insert into gist_rngtbl values ('[1,2)', 2) on conflict do nothing;
insert into gist_rngtbl values ('[1,2)', 3)
  on conflict (id) do update set n = excluded.n;
insert into gist_rngtbl values ('[2,3)', 4)
  on conflict (id) do update set n = excluded.n;
select * from gist_rngtbl order by id;
drop table gist_rngtbl;

-- Multi-column unique indexes, NULLS NOT DISTINCT, with some columns null:
create table gist_mctbl (a int4range, b int4range);
create unique index uq_gist_mctbl on gist_mctbl using gist (a, b) nulls not distinct;
insert into gist_mctbl values
  ('[1,2)', NULL), (NULL, '[1,2)'), (NULL, NULL), ('[1,2)', '[1,2)'); -- okay
insert into gist_mctbl values ('[1,2)', NULL); -- fail
insert into gist_mctbl values (NULL, '[1,2)'); -- fail
insert into gist_mctbl values (NULL, NULL); -- fail
insert into gist_mctbl values ('[1,2)', '[1,2)'); -- fail
insert into gist_mctbl values ('[1,2)', '[2,3)'); -- okay
drop table gist_mctbl;

-- Partial unique indexes:
create table gist_parttbl (id int4range, active bool);
create unique index uq_gist_parttbl on gist_parttbl using gist (id) where active;
insert into gist_parttbl values ('[1,2)', true), ('[1,2)', false), ('[1,2)', false); -- okay
insert into gist_parttbl values ('[1,2)', true); -- fail
-- enforced on build, only for the rows the index covers
drop index uq_gist_parttbl;
create unique index uq_gist_parttbl on gist_parttbl using gist (id) where active; -- okay
create unique index uq_gist_parttbl2 on gist_parttbl using gist (id) where not active; -- fail
drop table gist_parttbl;

-- Unique indexes with non-key attributes:
create table gist_rngtbl (id int4range, name text);
insert into gist_rngtbl values ('[1,2)', 'a'), ('[2,3)', 'b'), (NULL, 'c'), (NULL, 'd');
create unique index uq_gist_rngtbl on gist_rngtbl using gist (id) include (name);
insert into gist_rngtbl values ('[3,4)', 'e'), ('[4,5)', 'f'); -- okay
\d gist_rngtbl
select pg_get_indexdef('uq_gist_rngtbl'::regclass);
-- enforced on build
drop index uq_gist_rngtbl;
insert into gist_rngtbl values ('[1,2)', 'g');
create unique index uq_gist_rngtbl on gist_rngtbl using gist (id) include (name); -- fail
truncate gist_rngtbl;
-- enforced on insert
create unique index uq_gist_rngtbl on gist_rngtbl using gist (id) include (name);
insert into gist_rngtbl values ('[1,2)', 'a'), ('[2,3)', 'b'); -- okay
insert into gist_rngtbl values (NULL, 'c'), (NULL, 'd'); -- okay
insert into gist_rngtbl values ('[1,2)', 'g'); -- fail
drop table gist_rngtbl;

-- Clean up
reset enable_seqscan;
reset enable_bitmapscan;
reset enable_indexonlyscan;

drop table gist_tbl;

-- test an unlogged table, mostly to get coverage of gistbuildempty
create unlogged table gist_tbl (b box);
create index gist_tbl_box_index on gist_tbl using gist (b);
insert into gist_tbl
  select box(point(0.05*i, 0.05*i)) from generate_series(0,10) as i;
drop table gist_tbl;
