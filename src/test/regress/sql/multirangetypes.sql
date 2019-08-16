-- Tests for multirange data types.

--
-- test input parser
--

-- negative tests; should fail
select ''::multitextrange;
select '{"-[a,z)"}'::multitextrange;
select '{"[a,z) - "}'::multitextrange;
select '{"(",a)"}'::multitextrange;
select '{"(,,a)"}'::multitextrange;
select '{"(),a)"}'::multitextrange;
select '{"(a,))"}'::multitextrange;
select '{"(],a)"}'::multitextrange;
select '{"(a,])"}'::multitextrange;
select '{"[z,a]"}'::multitextrange;

-- should succeed
select '{}'::multitextrange;
select '  {}  '::multitextrange;
select ' { empty, empty }  '::multitextrange;
select ' {"( " a " " a ", " z " " z " )"}  "}'::multitextrange;
select '{"(,z)"}'::multitextrange;
select '{"(a,)"}'::multitextrange;
select '{"[,z]"}'::multitextrange;
select '{"[a,]"}'::multitextrange;
select '{"(,)"}'::multitextrange;
select '{"[ , ]"}'::multitextrange;
select '{"["",""]"}'::multitextrange;
select '{"[",",","]"}'::multitextrange;
select '{"["\\","\\"]"}'::multitextrange;
select '{"(\\,a)"}'::multitextrange;
select '{"((,z)"}'::multitextrange;
select '{"([,z)"}'::multitextrange;
select '{"(!,()"}'::multitextrange;
select '{"(!,[)"}'::multitextrange;
select '{"[a,a]"}'::multitextrange;
-- these are allowed but normalize to empty:
select '{"[a,a)"}'::multitextrange;
select '{"(a,a]"}'::multitextrange;
select '{"(a,a)"}'::multitextrange;

-- TODO: more, see rangetypes.sql
