/*-------------------------------------------------------------------------
 *
 * multirangetypes.c
 *	  I/O functions, operators, and support functions for multirange types.
 *
 * The stored (serialized) format of a multirange value is:
 *
 * TODO!
 *
 *
 * Portions Copyright (c) 1996-2019, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *	  src/backend/utils/adt/multirangetypes.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/tupmacs.h"
#include "lib/stringinfo.h"
#include "libpq/pqformat.h"
#include "miscadmin.h"
#include "utils/builtins.h"
#include "utils/date.h"
#include "utils/hashutils.h"
#include "utils/int8.h"
#include "utils/lsyscache.h"
#include "utils/rangetypes.h"
#include "utils/multirangetypes.h"
#include "utils/timestamp.h"
#include "utils/array.h"


/* fn_extra cache entry for one of the range I/O functions */
typedef struct MultirangeIOData
{
	TypeCacheEntry *typcache;	/* multirange type's typcache entry */
	Oid			typiofunc;		/* range type's I/O function */
	Oid			typioparam;		/* range type's I/O parameter */
	FmgrInfo	proc;			/* lookup result for typiofunc */
} MultirangeIOData;

typedef enum
{
	MULTIRANGE_BEFORE_RANGE,
	MULTIRANGE_IN_RANGE,
	MULTIRANGE_IN_RANGE_ESCAPED,
	MULTIRANGE_IN_RANGE_QUOTED,
	MULTIRANGE_IN_RANGE_QUOTED_ESCAPED,
	MULTIRANGE_AFTER_RANGE,
	MULTIRANGE_FINISHED,
} MultirangeParseState;

static MultirangeIOData *get_multirange_io_data(FunctionCallInfo fcinfo, Oid rngtypid,
									  IOFuncSelector func);
static int32
multirange_canonicalize(TypeCacheEntry *rangetyp, int32 input_range_count,
		RangeType **ranges);


/*
 *----------------------------------------------------------
 * I/O FUNCTIONS
 *----------------------------------------------------------
 */

/*
 * Converts string to multirange.
 *
 * We expect curly brackets to bound the list,
 * with zero or more ranges separated by commas.
 * We accept whitespace anywhere:
 * before/after our brackets and around the commas.
 * Ranges can be the empty literal or some stuff inside parens/brackets.
 * Mostly we delegate parsing the individual range contents
 * to range_in, but we have to detect quoting and backslash-escaping
 * which can happen for range bounds.
 * Backslashes can escape something inside or outside a quoted string,
 * and a quoted string can escape quote marks either either backslashes
 * or double double-quotes.
 */
Datum
multirange_in(PG_FUNCTION_ARGS)
{
	char			   *input_str = PG_GETARG_CSTRING(0);
	Oid					mltrngtypoid = PG_GETARG_OID(1);
	Oid					typmod = PG_GETARG_INT32(2);
	TypeCacheEntry	   *rangetyp;
	Oid					rngtypoid;
	int32				ranges_seen = 0;
	int32				range_count = 0;
	int32				range_capacity = 8;
	RangeType		   *range;
	RangeType		  **ranges = palloc(range_capacity * sizeof(RangeType *));
	MultirangeIOData *cache;
	MultirangeType		*ret;
	MultirangeParseState parse_state;
	const char *ptr = input_str;
	const char *range_str;
	int32 range_str_len;
	char *range_str_copy;
	
	check_stack_depth();		/* recurses when subtype is a range type */

	cache = get_multirange_io_data(fcinfo, mltrngtypoid, IOFunc_input);
	rangetyp = cache->typcache->rngtype;
	rngtypoid = rangetyp->type_id;

	/* consume whitespace */
	while (*ptr != '\0' && isspace((unsigned char) *ptr))
		ptr++;

	if (*ptr == '{')
		ptr++;
	else
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
				 errmsg("malformed multirange literal: \"%s\"",
						input_str),
				 errdetail("Missing left bracket.")));

	/* consume ranges */
	parse_state = MULTIRANGE_BEFORE_RANGE;
	for (; parse_state != MULTIRANGE_FINISHED; ptr++)
	{
		char ch = *ptr;

		if (ch == '\0')
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
					 errmsg("malformed multirange literal: \"%s\"",
							input_str),
					 errdetail("Unexpected end of input.")));

		/* skip whitespace */;
		if (isspace((unsigned char) ch))
			continue;

		switch (parse_state) {
			case MULTIRANGE_BEFORE_RANGE:
				if (ch == '[' || ch == '(')
				{
					range_str = ptr;
					parse_state = MULTIRANGE_IN_RANGE;
				}
				else if (ch == '}' && ranges_seen == 0)
					parse_state = MULTIRANGE_FINISHED;
				else if (pg_strncasecmp(ptr, RANGE_EMPTY_LITERAL,
					   strlen(RANGE_EMPTY_LITERAL)) == 0)
				{
					// TODO: DRY up with below:
					if (range_capacity == range_count)
					{
						range_capacity *= 2;
						ranges = (RangeType **) repalloc(ranges,
								range_capacity * sizeof(RangeType *));
					}
					ranges_seen++;
					range = DatumGetRangeTypeP(
							InputFunctionCall(&cache->proc, RANGE_EMPTY_LITERAL,
								cache->typioparam, typmod));
					if (!RangeIsEmpty(range))
						ranges[range_count++] = range;
					ptr += strlen(RANGE_EMPTY_LITERAL) - 1;
					parse_state = MULTIRANGE_AFTER_RANGE;
				}
				else
					ereport(ERROR,
							(errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
							 errmsg("malformed multirange literal: \"%s\"",
									input_str),
							 errdetail("Expected range start.")));
				break;
			case MULTIRANGE_IN_RANGE:
				if (ch == '"')
					parse_state = MULTIRANGE_IN_RANGE_QUOTED;
				else if (ch == '\\')
					parse_state = MULTIRANGE_IN_RANGE_ESCAPED;
				else if (ch == ']' || ch == ')') {
					range_str_len = ptr - range_str + 2;
					range_str_copy = palloc0(range_str_len);
					strlcpy(range_str_copy, range_str, range_str_len);
					// TODO: DRY up with below:
					if (range_capacity == range_count)
					{
						range_capacity *= 2;
						ranges = (RangeType **) repalloc(ranges,
								range_capacity * sizeof(RangeType *));
					}
					ranges_seen++;
					range = DatumGetRangeTypeP(
							InputFunctionCall(&cache->proc, range_str_copy,
								cache->typioparam, typmod));
					if (!RangeIsEmpty(range))
						ranges[range_count++] = range;
					parse_state = MULTIRANGE_AFTER_RANGE;
				}
				else
					/* include it in range_str */;
				break;
			case MULTIRANGE_IN_RANGE_ESCAPED:
				/* include it in range_str */
				parse_state = MULTIRANGE_IN_RANGE;
				break;
			case MULTIRANGE_IN_RANGE_QUOTED:
				if (ch == '"')
					if (*(ptr + 1) == '"')
					{
						/* two quote marks means an escaped quote mark */
						ptr++;
					}
					else
						parse_state = MULTIRANGE_IN_RANGE;
				else if (ch == '\\')
					parse_state = MULTIRANGE_IN_RANGE_QUOTED_ESCAPED;
				else
					/* include it in range_str */;
				break;
			case MULTIRANGE_AFTER_RANGE:
				if (ch == ',')
					parse_state = MULTIRANGE_BEFORE_RANGE;
				else if (ch == '}')
					parse_state = MULTIRANGE_FINISHED;
				else
					ereport(ERROR,
							(errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
							 errmsg("malformed multirange literal: \"%s\"",
									input_str),
							 errdetail("Expected comma or end of multirange.")));
				break;
			case MULTIRANGE_IN_RANGE_QUOTED_ESCAPED:
				/* include it in range_str */
				parse_state = MULTIRANGE_IN_RANGE_QUOTED;
				break;
			default:
				elog(ERROR, "Unknown parse state: %d", parse_state);
		}
	}

	/* consume whitespace */
	while (*ptr != '\0' && isspace((unsigned char) *ptr))
		ptr++;

	if (*ptr != '\0')
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
				 errmsg("malformed multirange literal: \"%s\"",
						input_str),
				 errdetail("Junk after right bracket.")));

	ret = make_multirange(mltrngtypoid, rangetyp, range_count, ranges);
	PG_RETURN_MULTIRANGE_P(ret);
}

Datum
multirange_out(PG_FUNCTION_ARGS)
{
	MultirangeType  *multirange = PG_GETARG_MULTIRANGE_P(0);
	Oid mltrngtypoid = MultirangeTypeGetOid(multirange);
	MultirangeIOData   *cache;
	StringInfoData buf;
	RangeType  *range;
	char *rangeStr;
	Pointer ptr = (char *) multirange;
	Pointer end = ptr + VARSIZE(multirange);
	int32 range_count = 0;

	cache = get_multirange_io_data(fcinfo, mltrngtypoid, IOFunc_output);

	initStringInfo(&buf);

	appendStringInfoChar(&buf, '{');

	ptr = (char *) MAXALIGN(multirange + 1);
	while (ptr < end) {
		if (range_count > 0)
			appendStringInfoChar(&buf, ',');
		range = (RangeType *)ptr;
		rangeStr = OutputFunctionCall(&cache->proc, RangeTypePGetDatum(range));
		appendStringInfoString(&buf, rangeStr);
		ptr += MAXALIGN(VARSIZE(range));
		range_count++;
	}

	appendStringInfoChar(&buf, '}');

	PG_RETURN_CSTRING(buf.data);
}

/*
 * Binary representation: The first byte is the flags, then the lower bound
 * (if present), then the upper bound (if present).  Each bound is represented
 * by a 4-byte length header and the binary representation of that bound (as
 * returned by a call to the send function for the subtype).
 */

Datum
multirange_recv(PG_FUNCTION_ARGS)
{
	StringInfo	buf = (StringInfo) PG_GETARG_POINTER(0);
	Oid			mltrngtypoid = PG_GETARG_OID(1);
	int32		typmod = PG_GETARG_INT32(2);
	MultirangeIOData	*cache;
	TypeCacheEntry	   *rangetyp;
	uint32				range_count;
	RangeType		   **ranges;
	MultirangeType		*ret;
	int i;

	check_stack_depth();		/* recurses when subtype is a range type */

	cache = get_multirange_io_data(fcinfo, mltrngtypoid, IOFunc_receive);
	rangetyp = cache->typcache->rngtype;

	range_count = pq_getmsgint(buf, 4);
	ranges = palloc0(range_count * sizeof(RangeType *));
	for (i = 0; i < range_count; i++) {
		uint32		range_len = pq_getmsgint(buf, 4);
		const char *range_data = pq_getmsgbytes(buf, range_len);
		StringInfoData range_buf;

		initStringInfo(&range_buf);
		appendBinaryStringInfo(&range_buf, range_data, range_len);

		ranges[i] = DatumGetRangeTypeP(
						ReceiveFunctionCall(&cache->proc,
											&range_buf,
											cache->typioparam,
											typmod));
		pfree(range_buf.data);
	}

	pq_getmsgend(buf);

	ret = make_multirange(mltrngtypoid, rangetyp, range_count, ranges);
	PG_RETURN_MULTIRANGE_P(ret);
}

Datum
multirange_send(PG_FUNCTION_ARGS)
{
	MultirangeType  *multirange = PG_GETARG_MULTIRANGE_P(0);
	Oid mltrngtypoid = MultirangeTypeGetOid(multirange);
	StringInfo	buf = makeStringInfo();
	MultirangeIOData   *cache;
	Pointer ptr = (char *) multirange;
	Pointer end = ptr + VARSIZE(multirange);

	check_stack_depth();		/* recurses when subtype is a range type */

	cache = get_multirange_io_data(fcinfo, mltrngtypoid, IOFunc_send);

	/* construct output */
	pq_begintypsend(buf);

	pq_sendint32(buf, multirange->rangeCount);

	ptr = (char *) MAXALIGN(multirange + 1);
	while (ptr < end) {
		Datum range	= RangeTypePGetDatum((RangeType *)ptr);
		range = PointerGetDatum(SendFunctionCall(&cache->proc, range));
		uint32		range_len = VARSIZE(range) - VARHDRSZ;
		char	   *range_data = VARDATA(range);
		pq_sendint32(buf, range_len);
		pq_sendbytes(buf, range_data, range_len);
		ptr += MAXALIGN(VARSIZE(range));
	}

	PG_RETURN_BYTEA_P(pq_endtypsend(buf));
}

Datum
multirange_typanalyze(PG_FUNCTION_ARGS)
{
	PG_RETURN_BOOL(true);
}

/*
 * get_multirange_io_data: get cached information needed for multirange type I/O
 *
 * The multirange I/O functions need a bit more cached info than other multirange
 * functions, so they store a MultirangeIOData struct in fn_extra, not just a
 * pointer to a type cache entry.
 */
static MultirangeIOData *
get_multirange_io_data(FunctionCallInfo fcinfo, Oid mltrngtypid, IOFuncSelector func)
{
	MultirangeIOData *cache = (MultirangeIOData *) fcinfo->flinfo->fn_extra;

	if (cache == NULL || cache->typcache->type_id != mltrngtypid)
	{
		int16		typlen;
		bool		typbyval;
		char		typalign;
		char		typdelim;

		cache = (MultirangeIOData *) MemoryContextAlloc(fcinfo->flinfo->fn_mcxt,
														sizeof(MultirangeIOData));
		cache->typcache = lookup_type_cache(mltrngtypid, TYPECACHE_MULTIRANGE_INFO);
		if (cache->typcache->rngtype == NULL)
			elog(ERROR, "type %u is not a multirange type", mltrngtypid);

		/* get_type_io_data does more than we need, but is convenient */
		get_type_io_data(cache->typcache->rngtype->type_id,
						 func,
						 &typlen,
						 &typbyval,
						 &typalign,
						 &typdelim,
						 &cache->typioparam,
						 &cache->typiofunc);

		if (!OidIsValid(cache->typiofunc))
		{
			/* this could only happen for receive or send */
			if (func == IOFunc_receive)
				ereport(ERROR,
						(errcode(ERRCODE_UNDEFINED_FUNCTION),
						 errmsg("no binary input function available for type %s",
								format_type_be(cache->typcache->rngtype->type_id))));
			else
				ereport(ERROR,
						(errcode(ERRCODE_UNDEFINED_FUNCTION),
						 errmsg("no binary output function available for type %s",
								format_type_be(cache->typcache->rngtype->type_id))));
		}
		fmgr_info_cxt(cache->typiofunc, &cache->proc,
					  fcinfo->flinfo->fn_mcxt);

		fcinfo->flinfo->fn_extra = (void *) cache;
	}

	return cache;
}

/*
 *----------------------------------------------------------
 * SUPPORT FUNCTIONS
 *
 *	 These functions aren't in pg_proc, but are useful for
 *	 defining new generic multirange functions in C.
 *----------------------------------------------------------
 */

/*
 * multirange_get_typcache: get cached information about a multirange type
 *
 * This is for use by multirange-related functions that follow the convention
 * of using the fn_extra field as a pointer to the type cache entry for
 * the multirange type.  Functions that need to cache more information than
 * that must fend for themselves.
 */
TypeCacheEntry *
multirange_get_typcache(FunctionCallInfo fcinfo, Oid mltrngtypid)
{
	TypeCacheEntry *typcache = (TypeCacheEntry *) fcinfo->flinfo->fn_extra;

	if (typcache == NULL ||
		typcache->type_id != mltrngtypid)
	{
		typcache = lookup_type_cache(mltrngtypid, TYPECACHE_MULTIRANGE_INFO);
		if (typcache->rngtype == NULL)
			elog(ERROR, "type %u is not a multirange type", mltrngtypid);
		fcinfo->flinfo->fn_extra = (void *) typcache;
	}

	return typcache;
}

/*
 * This serializes the multirange from a list of non-null ranges.
 * It also sorts the ranges and merges any that touch.
 * The ranges should already be detoasted, and there should be no NULLs.
 * This should be used by most callers.
 *
 * Note that we may change the `ranges` parameter (the pointers, but not
 * any already-existing RangeType contents).
 */
MultirangeType *
make_multirange(Oid mltrngtypoid, TypeCacheEntry *rangetyp, int32 range_count,
		RangeType **ranges)
{
	MultirangeType *multirange;
	RangeType  *range;
	int i;
	int32 bytelen;
	Pointer ptr;

	/* Sort and merge input ranges. */
	range_count = multirange_canonicalize(rangetyp, range_count, ranges);

	/*
	 * Count space for varlena header, multirange type's OID,
	 * other fields, and padding so that RangeTypes start aligned.
	 */
	bytelen = MAXALIGN(sizeof(MultirangeType));

	/* Count space for all ranges */
	for (i = 0; i < range_count; i++)
	{
		range = ranges[i];
		bytelen += MAXALIGN(VARSIZE(range));
	}
	
	/* Note: zero-fill is required here, just as in heap tuples */
	multirange = palloc0(bytelen);
	SET_VARSIZE(multirange, bytelen);

	/* Now fill in the datum */
	multirange->multirangetypid = mltrngtypoid;
	multirange->rangeCount = range_count;

	ptr = (char *) MAXALIGN(multirange + 1);
	for (i = 0; i < range_count; i++)
	{
		range = ranges[i];
		memcpy(ptr, range, VARSIZE(range));
		ptr += MAXALIGN(VARSIZE(range));
	}

	return multirange;
}

/*
 * Converts a list of any ranges you like into a list that is sorted and merged.
 * Changes the contents of `ranges`.
 * Returns the number of slots actually used,
 * which may be less than input_range_count but never more.
 * We assume that no input ranges are null, but empties are okay.
 */
static int32
multirange_canonicalize(TypeCacheEntry *rangetyp, int32 input_range_count,
		RangeType **ranges)
{
	RangeType *lastRange = NULL;
	RangeType *currentRange;
	int32 i;
	int32 output_range_count = 0;

	/* Sort the ranges so we can find the ones that overlap/meet. */
	qsort_arg(ranges, input_range_count, sizeof(RangeType *), range_compare,
			rangetyp);

	/* Now merge where possible: */
	for (i = 0; i < input_range_count; i++)
	{
		currentRange = ranges[i];
		if (RangeIsEmpty(currentRange))
			continue;

		if (lastRange == NULL)
		{
			ranges[output_range_count++] = lastRange = currentRange;
			continue;
		}

		/*
		 * range_adjacent_internal gives true if *either* A meets B
		 * or B meets A, which is not quite want we want, but we rely
		 * on the sorting above to rule out B meets A ever happening.
		 */
		if (range_adjacent_internal(rangetyp, lastRange, currentRange))
		{
			/* The two ranges touch (without overlap), so merge them: */
			ranges[output_range_count - 1] = lastRange =
				range_union_internal(rangetyp, lastRange, currentRange, false);
		}
		else if (range_before_internal(rangetyp, lastRange, currentRange))
		{
			/* There's a gap, so make a new entry: */
			lastRange = ranges[output_range_count] = currentRange;
			output_range_count++;
		}
		else
		{
			/* They must overlap, so merge them: */
			ranges[output_range_count - 1] = lastRange =
				range_union_internal(rangetyp, lastRange, currentRange, true);
		}
	}

	return output_range_count;
}

/*
 * multirange_deserialize: deconstruct a multirange value
 *
 * NB: the given multirange object must be fully detoasted; it cannot have a
 * short varlena header.
 */
void
multirange_deserialize(MultirangeType *multirange,
				  int32 *range_count, RangeType ***ranges)
{
	RangeType *r;
	Pointer ptr;
	Pointer end;
	int32 i;

	*range_count = multirange->rangeCount;
	if (*range_count == 0)
	{
		ranges = NULL;
		return;
	}

	*ranges = palloc0(*range_count * sizeof(RangeType *));

	ptr = (char *) multirange;
	end = ptr + VARSIZE(multirange);
	ptr = (char *) MAXALIGN(multirange + 1);
	i = 0;
	while (ptr < end) {
		r = (RangeType *) ptr;
		(*ranges)[i++] = r;

		ptr += MAXALIGN(VARSIZE(r));
	}
}
/*
 *----------------------------------------------------------
 * GENERIC FUNCTIONS
 *----------------------------------------------------------
 */

/*
 * Construct multirange value from zero or more ranges.
 * Since this is a variadic function we get passed an array.
 * The array must contain range types that match our return value,
 * and there must be no NULLs.
 */
Datum
multirange_constructor1(PG_FUNCTION_ARGS)
{
	Oid			mltrngtypid = get_fn_expr_rettype(fcinfo->flinfo);
	Oid			rngtypid;
	TypeCacheEntry *typcache;
	TypeCacheEntry *rangetyp;
	ArrayType	*rangeArray;
	int	range_count;
	Datum	*elements;
	bool	*nulls;
	RangeType **ranges;
	int dims;
	int	i;

	typcache = multirange_get_typcache(fcinfo, mltrngtypid);
	rangetyp = typcache->rngtype;

	/*
	 * A no-arg invocation should call multirange_constructor0 instead,
	 * but returning an empty range is what that does.
	 */

	if (PG_NARGS() == 0)
		PG_RETURN_MULTIRANGE_P(make_multirange(mltrngtypid, rangetyp, 0, NULL));

	/*
	 * These checks should be guaranteed by our signature,
	 * but let's do them just in case.
	 */

	if (PG_ARGISNULL(0))
		ereport(ERROR, (errmsg("Can't construct multirange with a NULL input")));

	rangeArray = PG_GETARG_ARRAYTYPE_P(0);

	dims = ARR_NDIM(rangeArray);
	if (dims > 1)
		ereport(ERROR, (errmsg("Can't construct multirange with a multi-dimensional array")));

	rngtypid = ARR_ELEMTYPE(rangeArray);
	if (rngtypid != rangetyp->type_id)
		ereport(ERROR, (errmsg("type %u does not match constructor type", rngtypid)));

	/*
	 * Be careful: we can still be called with zero ranges, like this:
	 * `int4multirange(variadic '{}'::int4range[])
	 */
	if (dims == 0)
	{
		range_count = 0;
		ranges = NULL;
	}
	else
	{
		deconstruct_array(rangeArray, rngtypid, rangetyp->typlen, rangetyp->typbyval,
				rangetyp->typalign, &elements, &nulls, &range_count);

		ranges = palloc0(range_count * sizeof(RangeType *));
		for (i = 0; i < range_count; i++)
		{
			if (nulls[i])
				ereport(ERROR, (errmsg("Can't construct multirange with a NULL element")));

			/* make_multirange will do its own copy */
			ranges[i] = DatumGetRangeTypeP(elements[i]);
		}
	}

	PG_RETURN_MULTIRANGE_P(make_multirange(mltrngtypid, rangetyp, range_count, ranges));
}

/*
 * Constructor just like multirange_constructor1,
 * but opr_sanity gets angry if the same internal function
 * handles multiple functions with different arg counts.
 */
Datum
multirange_constructor0(PG_FUNCTION_ARGS)
{
	Oid			mltrngtypid = get_fn_expr_rettype(fcinfo->flinfo);
	TypeCacheEntry *typcache;
	TypeCacheEntry *rangetyp;

	typcache = multirange_get_typcache(fcinfo, mltrngtypid);
	rangetyp = typcache->rngtype;

	/* We should always be called with no arguments */

	if (PG_NARGS() == 0)
		PG_RETURN_MULTIRANGE_P(make_multirange(mltrngtypid, rangetyp, 0, NULL));
	else
		ereport(ERROR, (errmsg("Zero-param multirange constructor shouldn't have arguments")));
}


/* multirange, multirange -> bool functions */

/* equality (internal version) */
bool
multirange_eq_internal(TypeCacheEntry *typcache, MultirangeType *mr1, MultirangeType *mr2)
{
	int32			range_count_1;
	int32			range_count_2;
	int32			i;
	RangeType	  **ranges1;
	RangeType	  **ranges2;
	RangeType	   *r1;
	RangeType	   *r2;

	check_stack_depth();		/* recurses when subtype is a range type */

	/* Different types should be prevented by ANYMULTIRANGE matching rules */
	if (MultirangeTypeGetOid(mr1) != MultirangeTypeGetOid(mr2))
		elog(ERROR, "multirange types do not match");

	multirange_deserialize(mr1, &range_count_1, &ranges1);
	multirange_deserialize(mr2, &range_count_2, &ranges2);

	if (range_count_1 != range_count_2)
		return false;

	for (i = 0; i < range_count_1; i++)
	{
		r1 = ranges1[i];
		r2 = ranges2[i];

		if (!range_eq_internal(typcache->rngtype, r1, r2))
			return false;
	}

	return true;
}

/* equality */
Datum
multirange_eq(PG_FUNCTION_ARGS)
{
	MultirangeType  *mr1 = PG_GETARG_MULTIRANGE_P(0);
	MultirangeType  *mr2 = PG_GETARG_MULTIRANGE_P(1);
	TypeCacheEntry *typcache;

	typcache = multirange_get_typcache(fcinfo, MultirangeTypeGetOid(mr1));

	PG_RETURN_BOOL(multirange_eq_internal(typcache, mr1, mr2));
}

/* inequality (internal version) */
bool
multirange_ne_internal(TypeCacheEntry *typcache, MultirangeType *mr1, MultirangeType *mr2)
{
	return (!multirange_eq_internal(typcache, mr1, mr2));
}

/* inequality */
Datum
multirange_ne(PG_FUNCTION_ARGS)
{
	MultirangeType  *mr1 = PG_GETARG_MULTIRANGE_P(0);
	MultirangeType  *mr2 = PG_GETARG_MULTIRANGE_P(1);
	TypeCacheEntry *typcache;

	typcache = multirange_get_typcache(fcinfo, MultirangeTypeGetOid(mr1));

	PG_RETURN_BOOL(multirange_ne_internal(typcache, mr1, mr2));
}

/* Btree support */

/* btree comparator */
Datum
multirange_cmp(PG_FUNCTION_ARGS)
{
	MultirangeType  *mr1 = PG_GETARG_MULTIRANGE_P(0);
	MultirangeType  *mr2 = PG_GETARG_MULTIRANGE_P(1);
	int32			range_count_1;
	int32			range_count_2;
	int32			range_count_max;
	int32			i;
	RangeType	  **ranges1;
	RangeType	  **ranges2;
	RangeType	   *r1;
	RangeType	   *r2;
	TypeCacheEntry *typcache;
	int			cmp = 0;	/* If both are empty we'll use this. */

	check_stack_depth();		/* recurses when subtype is a range type */

	/* Different types should be prevented by ANYMULTIRANGE matching rules */
	if (MultirangeTypeGetOid(mr1) != MultirangeTypeGetOid(mr2))
		elog(ERROR, "multirange types do not match");

	typcache = multirange_get_typcache(fcinfo, MultirangeTypeGetOid(mr1));

	multirange_deserialize(mr1, &range_count_1, &ranges1);
	multirange_deserialize(mr2, &range_count_2, &ranges2);

	/* Loop over source data */
	range_count_max = Max(range_count_1, range_count_2);
	for (i = 0; i < range_count_max; i++)
	{
		/*
		 * If one multirange is shorter,
		 * it's as if it had empty ranges at the end to extend its length.
		 * An empty range compares earlier than any other range,
		 * so the shorter multirange comes before the longer.
		 * This is the same behavior as in other types, e.g. in strings
		 * 'aaa' < 'aaaaaa'.
		 */
		if (i >= range_count_1)
		{
			cmp = -1;
			break;
		}
		if (i >= range_count_2)
		{
			cmp = 1;
			break;
		}
		r1 = ranges1[i];
		r2 = ranges2[i];

		cmp = range_cmp_internal(typcache->rngtype, r1, r2);
		if (cmp != 0) break;
	}
	
	PG_FREE_IF_COPY(mr1, 0);
	PG_FREE_IF_COPY(mr2, 1);

	PG_RETURN_INT32(cmp);
}

/* inequality operators using the multirange_cmp function */
Datum
multirange_lt(PG_FUNCTION_ARGS)
{
	int			cmp = multirange_cmp(fcinfo);

	PG_RETURN_BOOL(cmp < 0);
}

Datum
multirange_le(PG_FUNCTION_ARGS)
{
	int			cmp = multirange_cmp(fcinfo);

	PG_RETURN_BOOL(cmp <= 0);
}

Datum
multirange_ge(PG_FUNCTION_ARGS)
{
	int			cmp = multirange_cmp(fcinfo);

	PG_RETURN_BOOL(cmp >= 0);
}

Datum
multirange_gt(PG_FUNCTION_ARGS)
{
	int			cmp = multirange_cmp(fcinfo);

	PG_RETURN_BOOL(cmp > 0);
}

/* Hash support */

/* hash a multirange value */
Datum
hash_multirange(PG_FUNCTION_ARGS)
{
	MultirangeType  *mr = PG_GETARG_MULTIRANGE_P(0);
	uint32		result = 1;
	TypeCacheEntry *typcache;
	int32			range_count;
	RangeType	  **ranges;
	int32			i;
	RangeType	   *r;

	typcache = multirange_get_typcache(fcinfo, MultirangeTypeGetOid(mr));

	multirange_deserialize(mr, &range_count, &ranges);
	for (i = 0; i < range_count; i++)
	{
		uint32		elthash;

		r = ranges[i];
		elthash = hash_range_internal(typcache->rngtype, r);

		/*
		 * Use the same approach as hash_array
		 * to combine the individual elements' hash values:
		 */
		result = (result << 5) - result + elthash;
	}

	PG_FREE_IF_COPY(mr, 0);

	PG_RETURN_UINT32(result);
}

/*
 * Returns 64-bit value by hashing a value to a 64-bit value, with a seed.
 * Otherwise, similar to hash_multirange.
 */
Datum
hash_multirange_extended(PG_FUNCTION_ARGS)
{
	MultirangeType  *mr = PG_GETARG_MULTIRANGE_P(0);
	Datum		seed = PG_GETARG_DATUM(1);
	uint64		result = 1;
	TypeCacheEntry *typcache;
	int32			range_count;
	RangeType	  **ranges;
	int32			i;
	RangeType	   *r;

	typcache = multirange_get_typcache(fcinfo, MultirangeTypeGetOid(mr));

	multirange_deserialize(mr, &range_count, &ranges);
	for (i = 0; i < range_count; i++)
	{
		uint64		elthash;

		r = ranges[i];
		elthash = hash_range_extended_internal(typcache->rngtype, r, seed);

		/*
		 * Use the same approach as hash_array
		 * to combine the individual elements' hash values:
		 */
		result = (result << 5) - result + elthash;
	}

	PG_FREE_IF_COPY(mr, 0);

	PG_RETURN_UINT64(result);
}
