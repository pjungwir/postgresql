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
select '{["""","\""]}'::textmultirange;
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
