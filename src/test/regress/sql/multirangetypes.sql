-- Tests for multirange data types.

--
-- test input parser
--

-- negative tests; should fail
select ''::textmultirange;
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
-- these are allowed but normalize to empty:
select '{[a,a)}'::textmultirange;
select '{(a,a]}'::textmultirange;
select '{(a,a)}'::textmultirange;

-- TODO: more, see rangetypes.sql
