/*
 * contrib/btree_gist/btree_uuid.c
 */
#include "postgres.h"

#include "btree_gist.h"
#include "btree_utils_num.h"
#include "utils/uuid.h"
#include "utils/builtins.h"

#define UUIDSIZE 16

/* Also defined in backend/utils/adt/uuid.c */
struct pg_uuid_t
{
    unsigned char data[UUIDSIZE];
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


static bool
gbt_uuidgt(const void *a, const void *b)
{
	return DatumGetBool(DirectFunctionCall2(uuid_gt, UUIDPGetDatum(a), UUIDPGetDatum(b)));
}

static bool
gbt_uuidge(const void *a, const void *b)
{
	return DatumGetBool(DirectFunctionCall2(uuid_ge, UUIDPGetDatum(a), UUIDPGetDatum(b)));
}

static bool
gbt_uuideq(const void *a, const void *b)
{
	return DatumGetBool(DirectFunctionCall2(uuid_eq, UUIDPGetDatum(a), UUIDPGetDatum(b)));
}

static bool
gbt_uuidle(const void *a, const void *b)
{
	return DatumGetBool(DirectFunctionCall2(uuid_le, UUIDPGetDatum(a), UUIDPGetDatum(b)));
}

static bool
gbt_uuidlt(const void *a, const void *b)
{
	return DatumGetBool(DirectFunctionCall2(uuid_lt, UUIDPGetDatum(a), UUIDPGetDatum(b)));
}

static int
gbt_uuidkey_cmp(const void *a, const void *b)
{
	uuidKEY    *ia = (uuidKEY *) (((const Nsrt *) a)->t);
	uuidKEY    *ib = (uuidKEY *) (((const Nsrt *) b)->t);
	int			res;

	res = DatumGetInt32(DirectFunctionCall2(uuid_cmp, UUIDPGetDatum(&ia->lower), UUIDPGetDatum(&ib->lower)));
	if (res == 0)
		return DatumGetInt32(DirectFunctionCall2(uuid_cmp, UUIDPGetDatum(&ia->upper), UUIDPGetDatum(&ib->upper)));

	return res;
}


static double
uuid2num(const pg_uuid_t *i)
{
	return *((uint64 *)i);
}

static const gbtree_ninfo tinfo =
{
	gbt_t_uuid,
	UUIDSIZE,
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
		char	   *r = (char *) palloc(2 * UUIDSIZE);
		pg_uuid_t   *key = DatumGetUUIDP(entry->key);

		retval = palloc(sizeof(GISTENTRY));

		memcpy((void *) r, (void *) key, UUIDSIZE);
		memcpy((void *) (r + UUIDSIZE), (void *) key, UUIDSIZE);
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
				   gbt_num_consistent(&key, (void *) query, &strategy, GIST_LEAF(entry), &tinfo)
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


Datum
gbt_uuid_penalty(PG_FUNCTION_ARGS)
{
	uuidKEY    *origentry = (uuidKEY *) DatumGetPointer(((GISTENTRY *) PG_GETARG_POINTER(0))->key);
	uuidKEY    *newentry = (uuidKEY *) DatumGetPointer(((GISTENTRY *) PG_GETARG_POINTER(1))->key);
	float	   *result = (float *) PG_GETARG_POINTER(2);
	double		iorg[2],
				inew[2];

	iorg[0] = uuid2num(&origentry->lower);
	iorg[1] = uuid2num(&origentry->upper);
	inew[0] = uuid2num(&newentry->lower);
	inew[1] = uuid2num(&newentry->upper);

	penalty_num(result, iorg[0], iorg[1], inew[0], inew[1]);

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
