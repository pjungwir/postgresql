/* System periods are not implemented */
create table periodst (id integer, ds date, de date, period for system_time (ds, de));

/* Periods must specify actual columns */
create table periodst (id integer, ds date, de date, period for p (bogus, de));
create table periodst (id integer, ds date, de date, period for p (ds, bogus));

/* Data types must match exactly */
create table periodst (id integer, ds date, de timestamp, period for p (ds, de));
create table periodst (id integer, ds text collate "C", de text collate "POSIX", period for p (ds, de));

/* Periods must have a default BTree operator class */
create table periodst (id integer, ds xml, de xml, period for p (ds, de));

/* Period and column names are in the same namespace */
create table periodst (id integer, ds date, de date, period for ctid (ds, de));
create table periodst (id integer, ds date, de date, period for id (ds, de));

/* Period name can't be given more than once */
create table periodst (id integer, ds date, de date, period for p (ds, de), period for p (ds, de));

/* Period can't use the same colum for start and end*/
create table periodst (id integer, ds date, de date, period for p (ds, ds));

/* Now make one that works */
create table periodst (id integer, ds date, de date, period for p (ds, de));
/* Its generated column looks good */
select attname, atttypid::regtype, attnotnull, attgenerated from pg_attribute
where attrelid = 'periodst'::regclass and attname = 'p';
select conname, contype from pg_constraint where conrelid = 'periodst'::regclass order by conname;
/* It appears in the information_schema */
select * from information_schema.periods;

/* SELECT * excludes the PERIOD */
insert into periodst values (1, '2000-01-01', '2001-01-01');
select * from periodst;

/* You can get it if you want */
select *, p from periodst;

/* You can comment on it */
comment on period periodst.p is 'test comment';
select obj_description((select oid from pg_period where perrelid = 'periodst'::regclass and pername = 'p'), 'pg_period');

/* Two are okay */
create table periodst2 (id integer, ds date, de date, period for p1 (ds, de), period for p2 (ds, de));
drop table periodst2;

/* Skip creating GENERATED column: works */
create table periodst2 (id integer, ds date, de date, p daterange not null generated always as (daterange(ds, de)) stored, period for p (ds, de) with (colexists = true));
\d periodst2
drop table periodst2;
/* Skip creating GENERATED column: fails because the col isn't there */
create table periodst2 (id integer, ds date, de date, period for p (ds, de) with (colexists = true));
/* Skip creating GENERATED column: fails because the option has an invalid value */
create table periodst2 (id integer, ds date, de date, period for p (ds, de) with (colexists = 'whatever'));
/* Skip creating GENERATED column: fails because the column is not NOT NULL */
create table periodst2 (id integer, ds date, de date, p daterange generated always as (daterange(ds, de)) stored, period for p (ds, de) with (colexists = true));
/* Skip creating GENERATED column: fails because the column is not GENERATED */
create table periodst2 (id integer, ds date, de date, p daterange not null, period for p (ds, de) with (colexists = true));
/* Skip creating GENERATED column: fails because the column is GENERATED but with the wrong expression */
-- TODO:
-- create table periodst2 (id integer, ds date, de date, p daterange not null generated always as (daterange(de, ds)) stored, period for p (ds, de) with (colexists = true));
/* Skip creating GENERATED column: fails because the column is the wrong type */
create table periodst2 (id integer, ds date, de date, p tsrange not null generated always as (tsrange(ds, de)) stored, period for p (ds, de) with (colexists = true));
/* Skip creating GENERATED column: fails because the column is inherited */
create table periodst2parent (id integer, ds date, de date, p daterange not null generated always as (daterange(ds, de)) stored);
create table periodst2 (period for p (ds, de) with (colexists = true)) inherits (periodst2parent);
drop table periodst2parent;


/*
 * ALTER TABLE tests
 */
alter table periodst drop period for p;
alter table periodst add period for system_time (ds, de);
alter table periodst add period for p (ds, de);
/* Its generated column looks good */
select attname, atttypid::regtype, attnotnull, attgenerated from pg_attribute where attrelid = 'periodst'::regclass and attname = 'p';
select conname, contype from pg_constraint where conrelid = 'periodst'::regclass order by conname;

/* Adding a second one */
create table periodst2 (id integer, ds date, de date, period for p1 (ds, de));
alter table periodst2 add period for p2 (ds, de);
drop table periodst2;

/* Can't drop its columns */
alter table periodst drop column ds;
alter table periodst drop column de;

/* Can't change the data types */
alter table periodst alter column ds type timestamp;
alter table periodst alter column ds type timestamp;

/* column/period namespace conflicts */
alter table periodst add column p integer;
alter table periodst rename column id to p;
alter table periodst add period for tableoid (ds, de);
alter table periodst add period for "........pg.dropped.4........" (ds, de);

/* adding columns and the period at the same time */
create table periodst2 (id integer);
alter table periodst2 add column ds date, add column de date, add period for p (ds, de);
drop table periodst2;

/* Ambiguous range types raise an error */
create type mydaterange as range(subtype=date);
create table periodst2 (id int, ds date, de date, period for p (ds, de));

/* You can give an explicit range type */
create table periodst2 (id int, ds date, de date, period for p (ds, de) with (rangetype = 'mydaterange'));
drop type mydaterange;
drop type mydaterange cascade;
drop table periodst2;
create table periodst2 (id int, ds date, de date, period for p (ds, de) with (rangetype = 'daterange'));

/* Range type is not found */
create table periodst3 (id int, ds date, de date, period for p (ds, de) with (rangetype = 'notarange'));

/* Range type is the wrong type */
create table periodst3 (id int, ds date, de date, period for p (ds, de) with (rangetype = 'tstzrange'));
drop table periodst2;

/* Period can't use the same colum for start and end*/
create table periodst2 (id integer, ds date, de date);
alter table periodst2 add period for p (ds, ds);
drop table periodst2;

/* Skip creating GENERATED column: works */
create table periodst2 (id integer, ds date, de date, p daterange not null generated always as (daterange(ds, de)) stored);
alter table periodst2 add period for p (ds, de) with (colexists = true);
\d periodst2
drop table periodst2;
/* Skip creating GENERATED column: fails because the col isn't there */
create table periodst2 (id integer, ds date, de date);
alter table periodst2 add period for p (ds, de) with (colexists = true);
drop table periodst2;
/* Skip creating GENERATED column: fails because the option has an invalid value */
create table periodst2 (id integer, ds date, de date, p daterange not null generated always as (daterange(ds, de)) stored);
alter table periodst2 add period for p (ds, de) with (colexists = 'whatever');
drop table periodst2;
/* Skip creating GENERATED column: fails because the column is not NOT NULL */
create table periodst2 (id integer, ds date, de date, p daterange generated always as (daterange(ds, de)) stored);
alter table periodst2 add period for p (ds, de) with (colexists = true);
drop table periodst2;
/* Skip creating GENERATED column: fails because the column is not GENERATED */
create table periodst2 (id integer, ds date, de date, p daterange not null);
alter table periodst2 add period for p (ds, de) with (colexists = true);
drop table periodst2;
/* Skip creating GENERATED column: fails because the column is GENERATED but with the wrong expression */
-- TODO:
-- create table periodst2 (id integer, ds date, de date, p daterange not null generated always as (daterange(de, ds)) stored);
-- alter table periodst2 add period for p (ds, de) with (colexists = true);
/* Skip creating GENERATED column: fails because the column is the wrong type */
create table periodst2 (id integer, ds date, de date, p tsrange not null generated always as (tsrange(ds, de)) stored);
alter table periodst2 add period for p (ds, de) with (colexists = true);
drop table periodst2;
/* Skip creating GENERATED column: fails because the column is inherited */
create table periodst2parent (id integer, ds date, de date, p daterange not null generated always as (daterange(ds, de)) stored);
create table periodst2 () inherits (periodst2parent);
alter table periodst2 add period for p (ds, de) with (colexists = true);
drop table periodst2;
drop table periodst2parent;

/* CREATE TABLE (LIKE ...) */

/* Periods are not copied by LIKE, so their columns aren't either */
create table periodst2 (like periodst);
\d periodst2
drop table periodst2;

/* Can add a period referring to LIKE'd columns */
create table not_p (id integer, ds date, de date);
create table periodst2 (like not_p, period for p (ds, de));
\d periodst2
drop table periodst2;

/* Can add a period with the same name */
create table periodst2 (like periodst, period for p (ds, de));
\d periodst2
drop table periodst2;

/* Can add a period with a different name */
create table periodst2 (like periodst, period for p2 (ds, de));
\d periodst2
drop table periodst2;

/* Can't add a period whose name conflicts with a LIKE'd column */
create table periodst2 (like periodst, period for id (ds, de));

/* CREATE TALBE INHERITS */

/* Can't inherit from a table with a period */
create table periodst2 (name text) inherits (periodst);

/* Can't inherit with a period */
create table periodst2 (d2s date, d2e date, period for p (d2s, d2e)) inherits (not_p);

drop table not_p;
