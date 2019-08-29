/*-------------------------------------------------------------------------
 *
 * multirangetypes.h
 *	  Declarations for Postgres multirange types.
 *
 *
 * Portions Copyright (c) 1996-2019, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/include/utils/multirangetypes.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef MULTIRANGETYPES_H
#define MULTIRANGETYPES_H

#include "utils/typcache.h"


/*
 * Multiranges are varlena objects, so must meet the varlena convention that
 * the first int32 of the object contains the total object size in bytes.
 * Be sure to use VARSIZE() and SET_VARSIZE() to access it, though!
 */
typedef struct
{
	char		vl_len_[4];			/* varlena header (do not touch directly!) */
	Oid			multirangetypid;	/* multirange type's own OID */
	uint32		rangeCount;			/* the number of ranges */
	/*
	 * Following the OID are the range objects themselves.
	 * Note that ranges are varlena too,
	 * depending on whether they have lower/upper bounds
	 * and because even their base types can be varlena.
	 * So we can't really index into this list.
	 */
} MultirangeType;

/* Use this macro in preference to fetching multirangetypid field directly */
#define MultirangeTypeGetOid(r)	((r)->multirangetypid)

/*
 * fmgr macros for multirange type objects
 */
#define DatumGetMultirangeTypeP(X)		((MultirangeType *) PG_DETOAST_DATUM(X))
#define DatumGetMultirangeTypePCopy(X)	((MultirangeType *) PG_DETOAST_DATUM_COPY(X))
#define MultirangeTypePGetDatum(X)		PointerGetDatum(X)
#define PG_GETARG_MULTIRANGE_P(n)		DatumGetMultirangeTypeP(PG_GETARG_DATUM(n))
#define PG_GETARG_MULTIRANGE_P_COPY(n)	DatumGetMultirangeTypePCopy(PG_GETARG_DATUM(n))
#define PG_RETURN_MULTIRANGE_P(x)		return MultirangeTypePGetDatum(x)

/*
 * prototypes for functions defined in multirangetypes.c
 */

// extern bool range_contains_elem_internal(TypeCacheEntry *typcache, RangeType *r, Datum val);

/* internal versions of the above */
extern bool multirange_eq_internal(TypeCacheEntry *typcache, MultirangeType *mr1,
								   MultirangeType *mr2);
extern bool multirange_ne_internal(TypeCacheEntry *typcache, MultirangeType *mr1,
								   MultirangeType *mr2);
extern bool multirange_contains_elem_internal(TypeCacheEntry *typcache, MultirangeType *mr,
											  Datum elem);
extern bool multirange_contains_range_internal(TypeCacheEntry *typcache, MultirangeType *mr,
											   RangeType *r);
/*
extern bool range_contained_by_internal(TypeCacheEntry *typcache, RangeType *r1,
										RangeType *r2);
extern bool range_before_internal(TypeCacheEntry *typcache, RangeType *r1,
								  RangeType *r2);
extern bool range_after_internal(TypeCacheEntry *typcache, RangeType *r1,
								 RangeType *r2);
extern bool range_adjacent_internal(TypeCacheEntry *typcache, RangeType *r1,
									RangeType *r2);
extern bool range_overlaps_internal(TypeCacheEntry *typcache, RangeType *r1,
									RangeType *r2);
extern bool range_overleft_internal(TypeCacheEntry *typcache, RangeType *r1,
									RangeType *r2);
extern bool range_overright_internal(TypeCacheEntry *typcache, RangeType *r1,
									 RangeType *r2);
									 */

/* assorted support functions */
extern TypeCacheEntry *multirange_get_typcache(FunctionCallInfo fcinfo,
											   Oid mltrngtypid);
/*
extern MultirangeType *multirange_serialize(TypeCacheEntry *typcache,
								  RangeBound *lower,
								  RangeBound *upper, bool empty);
								  */
extern void multirange_deserialize(MultirangeType *range,
								   int32 *range_count, RangeType ***ranges);
extern MultirangeType *make_multirange(Oid mltrngtypoid,
		TypeCacheEntry *typcache, int32 range_count, RangeType **ranges);

#endif							/* MULTIRANGETYPES_H */
