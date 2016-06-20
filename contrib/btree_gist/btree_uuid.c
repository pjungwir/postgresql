/*
 * contrib/btree_gist/btree_uuid.c
 */
#include "postgres.h"

#include "math.h"
#include "btree_gist.h"
#include "btree_utils_num.h"
#include "utils/uuid.h"
#include "utils/builtins.h"
#include "port/pg_bswap.h"

/*
 * Also defined in backend/utils/adt/uuid.c
 * We define also two uint64 fields, that will be used for uuid comparisons.
 */
union pg_uuid_t
{
	unsigned char data[UUID_LEN];
	uint64 v64[2];
};

typedef struct
{
	pg_uuid_t	lower,
				upper;
} uuidKEY;


/*
** UUID ops
*/
PG_FUNCTION_INFO_V1(gbt_uuid_compress);
PG_FUNCTION_INFO_V1(gbt_uuid_fetch);
PG_FUNCTION_INFO_V1(gbt_uuid_union);
PG_FUNCTION_INFO_V1(gbt_uuid_picksplit);
PG_FUNCTION_INFO_V1(gbt_uuid_consistent);
PG_FUNCTION_INFO_V1(gbt_uuid_penalty);
PG_FUNCTION_INFO_V1(gbt_uuid_same);


/*
 * Convert uuid value to other uuid value, that will have correct low and high
 * parts of uuid. Because the uuid type by default has a bigendian order, so
 * for correct uint64 values we need to change ordering on littleendian
 * machines, and that's the reason we can't change fields in place (because it
 * can corrupt uuid).
 *
 * Reason to use uint64 values is that comparison using them is faster than
 * memcmp and same time it has a same behavior.
 */
static void
uuid_cnv(pg_uuid_t *src, pg_uuid_t *dst)
{
#ifdef WORDS_BIGENDIAN
	memcpy(dst->data, src->data, UUID_LEN);
#else
	dst->v64[0] = BSWAP64(src->v64[0]);
	dst->v64[1] = BSWAP64(src->v64[1]);
#endif
}

static int
uuid_cmp_parts(pg_uuid_t *a, pg_uuid_t *b)
{
	pg_uuid_t ua, ub;

	uuid_cnv(a, &ua);
	uuid_cnv(b, &ub);

	if (ua.v64[0] == ub.v64[0])
	{
		if (ua.v64[1] == ub.v64[1])
			return 0;

		return (ua.v64[1] > ub.v64[1]) ? 1 : -1;
	}

	return (ua.v64[0] > ub.v64[0]) ? 1 : -1;
}

static bool
gbt_uuidgt(const void *a, const void *b)
{
	return uuid_cmp_parts((pg_uuid_t *) a, (pg_uuid_t *) b) > 0;
}

static bool
gbt_uuidge(const void *a, const void *b)
{
	return uuid_cmp_parts((pg_uuid_t *) a, (pg_uuid_t *) b) >= 0;
}

static bool
gbt_uuideq(const void *a, const void *b)
{
	return uuid_cmp_parts((pg_uuid_t *) a, (pg_uuid_t *) b) == 0;
}

static bool
gbt_uuidle(const void *a, const void *b)
{
	return uuid_cmp_parts((pg_uuid_t *) a, (pg_uuid_t *) b) <= 0;
}

static bool
gbt_uuidlt(const void *a, const void *b)
{
	return uuid_cmp_parts((pg_uuid_t *) a, (pg_uuid_t *) b) < 0;
}

static int
gbt_uuidkey_cmp(const void *a, const void *b)
{
	uuidKEY    *ia = (uuidKEY *) (((const Nsrt *) a)->t);
	uuidKEY    *ib = (uuidKEY *) (((const Nsrt *) b)->t);
	int			res;

	res = uuid_cmp_parts(&ia->upper, &ib->upper);
	if (res == 0)
		return uuid_cmp_parts(&ia->lower, &ib->lower);

	return res;
}


static const gbtree_ninfo tinfo =
{
	gbt_t_uuid,
	UUID_LEN,
	32,							/* sizeof(gbtreekey32) */
	gbt_uuidgt,
	gbt_uuidge,
	gbt_uuideq,
	gbt_uuidle,
	gbt_uuidlt,
	gbt_uuidkey_cmp,
	NULL
};


/**************************************************
 * uuid ops
 **************************************************/


Datum
gbt_uuid_compress(PG_FUNCTION_ARGS)
{
	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);
	GISTENTRY  *retval;

	if (entry->leafkey)
	{
		char	   *r = (char *) palloc(2 * UUID_LEN);
		pg_uuid_t   *key = DatumGetUUIDP(entry->key);

		retval = palloc(sizeof(GISTENTRY));

		memcpy((void *) r, (void *) key, UUID_LEN);
		memcpy((void *) (r + UUID_LEN), (void *) key, UUID_LEN);
		gistentryinit(*retval, PointerGetDatum(r),
					  entry->rel, entry->page,
					  entry->offset, FALSE);
	} else {
		retval = entry;
	}

	PG_RETURN_POINTER(retval);
}

Datum
gbt_uuid_fetch(PG_FUNCTION_ARGS)
{
	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);

	PG_RETURN_POINTER(gbt_num_fetch(entry, &tinfo));
}

Datum
gbt_uuid_consistent(PG_FUNCTION_ARGS)
{
	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);
	pg_uuid_t   *query = PG_GETARG_UUID_P(1);
	StrategyNumber strategy = (StrategyNumber) PG_GETARG_UINT16(2);

	/* Oid		subtype = PG_GETARG_OID(3); */
	bool	   *recheck = (bool *) PG_GETARG_POINTER(4);
	uuidKEY    *kkk = (uuidKEY *) DatumGetPointer(entry->key);
	GBT_NUMKEY_R key;

	/* All cases served by this function are exact */
	*recheck = false;

	key.lower = (GBT_NUMKEY *) &kkk->lower;
	key.upper = (GBT_NUMKEY *) &kkk->upper;

	PG_RETURN_BOOL(
		gbt_num_consistent(&key, (void *) query, &strategy,
			GIST_LEAF(entry), &tinfo)
	);
}

Datum
gbt_uuid_union(PG_FUNCTION_ARGS)
{
	GistEntryVector *entryvec = (GistEntryVector *) PG_GETARG_POINTER(0);
	void	   *out = palloc(sizeof(uuidKEY));

	*(int *) PG_GETARG_POINTER(1) = sizeof(uuidKEY);
	PG_RETURN_POINTER(gbt_num_union((void *) out, entryvec, &tinfo));
}

/*
 * Calculate a distance. Distance is calculated by subtraction of two
 * uuid values presented as 128bit numbers, and by converting the result
 * to float (requirement of GiST).
 */
static float
uuid_parts_distance(pg_uuid_t *a, pg_uuid_t *b)
{
	pg_uuid_t		ua,
					ub;
	uint64			high,
					low;
	const double	mp = pow(2, -64);

	uuid_cnv(a, &ua);
	uuid_cnv(b, &ub);

	Assert(ua.v64[0] >= ub.v64[0]);

	high = ua.v64[0] - ub.v64[0];
	low = ua.v64[1] - ub.v64[1];
	if (low > ua.v64[1])
		high--;

	return (float) ((double) high + (double) low * mp);
}

Datum
gbt_uuid_penalty(PG_FUNCTION_ARGS)
{
	uuidKEY    *origentry = (uuidKEY *) DatumGetPointer(((GISTENTRY *) PG_GETARG_POINTER(0))->key);
	uuidKEY    *newentry = (uuidKEY *) DatumGetPointer(((GISTENTRY *) PG_GETARG_POINTER(1))->key);
	float	   *result = (float *) PG_GETARG_POINTER(2);

	int cmp = uuid_cmp_parts(&newentry->lower, &origentry->upper);
	if (cmp == 0)
		*result = 0.0F;
	else if (cmp > 0)
		*result = uuid_parts_distance(&newentry->lower, &origentry->upper);
	else
	{
		int cmp = uuid_cmp_parts(&newentry->lower, &origentry->lower);
		if (cmp == 0)
			*result = 0.0F;
		else if (cmp < 0)
			*result = uuid_parts_distance(&origentry->lower, &newentry->lower);
	}

	PG_RETURN_POINTER(result);
}

Datum
gbt_uuid_picksplit(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(gbt_num_picksplit(
									(GistEntryVector *) PG_GETARG_POINTER(0),
									  (GIST_SPLITVEC *) PG_GETARG_POINTER(1),
										&tinfo
										));
}

Datum
gbt_uuid_same(PG_FUNCTION_ARGS)
{
	uuidKEY    *b1 = (uuidKEY *) PG_GETARG_POINTER(0);
	uuidKEY    *b2 = (uuidKEY *) PG_GETARG_POINTER(1);
	bool	   *result = (bool *) PG_GETARG_POINTER(2);

	*result = gbt_num_same((void *) b1, (void *) b2, &tinfo);
	PG_RETURN_POINTER(result);
}
