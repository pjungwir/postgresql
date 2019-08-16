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


/* fn_extra cache entry for one of the range I/O functions */
typedef struct MultirangeIOData
{
	TypeCacheEntry *typcache;	/* range type's typcache entry */
	Oid			typiofunc;		/* element type's I/O function */
	Oid			typioparam;		/* element type's I/O parameter */
	FmgrInfo	proc;			/* lookup result for typiofunc */
} MultirangeIOData;


static MultirangeIOData *get_multirange_io_data(FunctionCallInfo fcinfo, Oid rngtypid,
									  IOFuncSelector func);
/*
static char range_parse_flags(const char *flags_str);
static void range_parse(const char *input_str, char *flags, char **lbound_str,
						char **ubound_str);
static const char *range_parse_bound(const char *string, const char *ptr,
									 char **bound_str, bool *infinite);
static char *range_deparse(char flags, const char *lbound_str,
						   const char *ubound_str);
static char *range_bound_escape(const char *value);
static Size datum_compute_size(Size sz, Datum datum, bool typbyval,
							   char typalign, int16 typlen, char typstorage);
static Pointer datum_write(Pointer ptr, Datum datum, bool typbyval,
						   char typalign, int16 typlen, char typstorage);
						   */


/*
 *----------------------------------------------------------
 * I/O FUNCTIONS
 *----------------------------------------------------------
 */

/*
 * Converts string to multirange.
 */
Datum
multirange_in(PG_FUNCTION_ARGS)
{
	char			   *input_str = PG_GETARG_CSTRING(0);
	Oid					mltrngtypoid = PG_GETARG_OID(1);
	Oid					typmod = PG_GETARG_INT32(2);
	TypeCacheEntry	   *typcache;
	TypeCacheEntry	   *rangetyp;
	Oid					rngtypoid;
	RangeType		   *lastRange;
	RangeBound lower;
	RangeBound upper;
	MultirangeType		*ret;
	
	check_stack_depth();		/* recurses when subtype is a range type */

	typcache = multirange_get_typcache(fcinfo, mltrngtypoid);
	rangetyp = typcache->rngtype;
	rngtypoid = rangetyp->type_id;

	lower.lower = true;
	upper.lower = false;
	lastRange = make_range(rangetyp, &lower, &upper, true);

	ret = make_multirange(mltrngtypoid, rangetyp, 1, &lastRange);
	PG_RETURN_MULTIRANGE_P(ret);

#if 0
	char			   *input_str = PG_GETARG_CSTRING(0);
	Oid					mltrngtypoid = PG_GETARG_OID(1);
	Oid					typmod = PG_GETARG_INT32(2);
	TypeCacheEntry	   *typcache;
	TypeCacheEntry	   *rngtype;
	Oid					rngtypoid;
	// Oid					rngtypmod;
	Datum				range_array_datum;
	ArrayType			*range_array;
	Datum				*ranges;
	bool				*null_ranges;
	int					ranges_length;
	// MultirangeType	   *multirange;
	// MultirangeIOData   *cache;
	int					i;
	RangeType		   *lastRange;
	RangeType		   *currentRange;

	check_stack_depth();		/* recurses when subtype is a range type */

	typcache = multirange_get_typcache(fcinfo, mltrngtypoid);
	rangetyp = typcache->rngtype;
	rngtypoid = rngtype->type_id;

	// rngtypmod = typcache->rngtype->
	// typcache->rngtype->type_id
	// If a multirange has a typemod we pass it down to the ranges:
	range_array_datum = DirectFunctionCall3(array_in, rngtypoid, typmod);
	range_array = DatumGetArrayTypeP(range_array);
	deconstruct_array(range_array, rngtypoid, rngtype->typlen,
			rngtype->typbyval, rngtype->typalign,
			&ranges, &null_ranges, &ranges_length);

	if (ranges_length == 0)
	{
		// TODO: Build an empty multirange and return that.
	}
	
	/* If any elements are NULL, the result is NULL. */
	for (i = 0; i < ranges_length; i++)
	{
		if (null_ranges[i]) PG_RETURN_NULL();
	}

	qsort_arg(ranges, ranges_length, sizeof(Datum), range_compare_by_lower, rngtype);

	lastRange = NULL;
	for (i = 0; i < ranges_length; i++)
	{
		/* Skip empties */
		RangeType *currentRange = DatumGetRangeTypeP(ranges[i]);
		RangeBound upper, lower;
		bool empty;
		range_deserialize(typcache, currentRange, &lower, &upper, &empty);

		if (empty) continue;

		if (!lastRange) {
			lastRange = r;
			continue;
		}

		if (range_adjacent_internal(typcache, lastRange, currentRange))
		{
			lastRange = range_union_internal(typcache, lastRange, currentRange, false);

		} else if (range_before_internal(typcache, lastRange, currentRange))
		{
			// TODO: add lastRange to the multirange
			lastRange = currentRange;

		} else // they must overlap
		{
			lastRange = range_union_internal(typcache, lastRange, currentRange, false);
		}
	}
	if (lastRange) {
		// TODO: add lastRange to the multirange
	}



	cache = get_multirange_io_data(fcinfo, mltrngtypoid, IOFunc_input);

	/* parse */
	range_parse(input_str, &flags, &lbound_str, &ubound_str);

	/* call element type's input function */
	if (RANGE_HAS_LBOUND(flags))
		lower.val = InputFunctionCall(&cache->proc, lbound_str,
									  cache->typioparam, typmod);
	if (RANGE_HAS_UBOUND(flags))
		upper.val = InputFunctionCall(&cache->proc, ubound_str,
									  cache->typioparam, typmod);

	lower.infinite = (flags & RANGE_LB_INF) != 0;
	lower.inclusive = (flags & RANGE_LB_INC) != 0;
	lower.lower = true;
	upper.infinite = (flags & RANGE_UB_INF) != 0;
	upper.inclusive = (flags & RANGE_UB_INC) != 0;
	upper.lower = false;

	/* serialize and canonicalize */
	range = make_range(cache->typcache, &lower, &upper, flags & RANGE_EMPTY);

	PG_RETURN_MULTIRANGE_P(range);
#endif
}

Datum
multirange_out(PG_FUNCTION_ARGS)
{
	char	   *output_str = "{[1,2]}";;
	PG_RETURN_CSTRING(output_str);
#if 0
	MultiRangeType  *multirange = PG_GETARG_MULTIRANGE_P(0);
	char	   *output_str;
	RangeIOData *cache;
	char		flags;
	char	   *lbound_str = NULL;
	char	   *ubound_str = NULL;
	RangeBound	lower;
	RangeBound	upper;
	bool		empty;

	check_stack_depth();		/* recurses when subtype is a multirange type */

	cache = get_range_io_data(fcinfo, RangeTypeGetOid(range), IOFunc_output);

	/* deserialize */
	range_deserialize(cache->typcache, range, &lower, &upper, &empty);
	flags = range_get_flags(range);

	/* call element type's output function */
	if (RANGE_HAS_LBOUND(flags))
		lbound_str = OutputFunctionCall(&cache->proc, lower.val);
	if (RANGE_HAS_UBOUND(flags))
		ubound_str = OutputFunctionCall(&cache->proc, upper.val);

	/* construct result string */
	output_str = range_deparse(flags, lbound_str, ubound_str);

	PG_RETURN_CSTRING(output_str);
#endif
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

	check_stack_depth();		/* recurses when subtype is a range type */
}

Datum
multirange_send(PG_FUNCTION_ARGS)
{
	RangeType  *range = PG_GETARG_RANGE_P(0);
	StringInfo	buf = makeStringInfo();

	check_stack_depth();		/* recurses when subtype is a range type */
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
		if (cache->typcache->rngelemtype == NULL)
			elog(ERROR, "type %u is not a multirange type", mltrngtypid);

		/* get_type_io_data does more than we need, but is convenient */
		get_type_io_data(cache->typcache->rngelemtype->type_id,
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
								format_type_be(cache->typcache->rngelemtype->type_id))));
			else
				ereport(ERROR,
						(errcode(ERRCODE_UNDEFINED_FUNCTION),
						 errmsg("no binary output function available for type %s",
								format_type_be(cache->typcache->rngelemtype->type_id))));
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
		if (typcache->rngelemtype == NULL)
			elog(ERROR, "type %u is not a multirange type", mltrngtypid);
		fcinfo->flinfo->fn_extra = (void *) typcache;
	}

	return typcache;
}

/*
 * This serializes the multirange from a list of non-null ranges.
 * The ranges should already be detoasted.
 * This should be used by most callers.
 */
MultirangeType *
make_multirange(Oid mltrngtypoid, TypeCacheEntry *rangetyp, int range_count, RangeType **ranges)
{
	MultirangeType *multirange;
	RangeType  *range;
	int i;
	int32 bytelen;
	Pointer ptr;

	/* Count space for varlena header and multirange type's OID */
	bytelen = sizeof(MultirangeType);
	Assert(bytelen == MAXALIGN(bytelen));

	/* Count space for all ranges */
	for (i = 0; i < range_count; i++)
	{
		range = ranges[i];
		bytelen += VARSIZE(range);
		bytelen += att_align_nominal(bytelen, rangetyp->typalign);
	}
	
	/* Note: zero-fill is required here, just as in heap tuples */
	multirange = palloc0(bytelen);
	SET_VARSIZE(multirange, bytelen);

	/* Now fill in the datum */
	multirange->multirangetypid = mltrngtypoid;

	ptr = (char *) (multirange + 1);
	for (i = 0; i < range_count; i++)
	{
		range = ranges[i];
		ptr += MAXALIGN_DOWN(ptr);
		memcpy(ptr, range, VARSIZE(range));
		// memcpy(MAXALIGN(ptr), range, VARSIZE(range));
	}

	return multirange;
}
