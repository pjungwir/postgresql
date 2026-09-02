/*-------------------------------------------------------------------------
 *
 * gistunique.c
 *	  uniqueness checking for GiST indexes
 *
 * A GiST index can enforce a unique constraint, but not the way nbtree does.
 * In a B-tree every tuple that could conflict with the one we are inserting
 * lives on a single leaf page (or on the pages immediately to its right), so
 * _bt_check_unique() can hold a write lock on that page across both the check
 * and the insertion and thereby serialize concurrent inserters of the same
 * key.
 *
 * A GiST tree gives us neither property:
 *
 * - The downlink keys on an internal page may overlap, so a tuple equal to
 *	 the one we are inserting can be in any subtree whose downlink is
 *	 consistent with our key.  Descending along the path of smallest penalty,
 *	 which is what gistdoinsert() does, reaches only one of those subtrees, and
 *	 not necessarily the one an earlier insert of the same key ended up in (the
 *	 penalties depend on the shape of the tree, which changes over time).  To
 *	 find every possible duplicate we have to search the whole tree, following
 *	 every consistent downlink.
 *
 * - Consequently there is no one page whose lock could serialize two backends
 *	 inserting the same key: they may well be headed for different leaf pages.
 *
 * So we insert first and search afterwards, exactly the way exclusion
 * constraints are enforced.  That ordering is what makes the check safe
 * against concurrent inserters.  If two transactions insert conflicting
 * tuples, the one that inserts second begins its search after the first
 * tuple is already in the tree, and a GiST search is guaranteed to find every
 * tuple that was present when the search began (concurrent page splits are
 * handled by the usual NSN/rightlink interlock).  Searching before inserting
 * would let both transactions see a tree without the other's tuple and then
 * both insert.
 *
 * The downside, shared with exclusion constraints, is that two backends
 * racing to insert the same key can each find the other's tuple and wait for
 * it, in which case the deadlock detector aborts one of them.  One of them
 * had to fail anyway; only the error message differs.  It also means a failed
 * insert leaves a dead tuple behind in the index, but a failed insert leaves a
 * dead tuple in the heap too, so that is nothing new.
 *
 * Waiting is worth avoiding, so unlike _bt_check_unique() we do not stop at
 * the first conflict whose transaction is still running.  We have to visit
 * every consistent page in any case, so we note that transaction and keep
 * looking: if some other conflicting row has already committed we can report
 * the violation immediately, and only if the whole search turns up nothing
 * but in-doubt rows do we wait for one and start over.
 *
 * The search itself is an ordinary GiST tree walk driven by a queue of pages
 * we still have to visit.  We start at the root and add every downlink whose
 * key is consistent with the value being checked; matching leaf entries are
 * candidate conflicts.  The queue is FIFO, so the tree is searched breadth
 * first; nothing depends on that order.  A GiST index tuple carries no
 * visibility information, so for each candidate we visit the heap to see
 * whether the row is live, and if the opclass told us that the index-level
 * test was lossy we re-test the heap values with the equality operator
 * itself.  We do both after unlocking the leaf page, since either can run
 * user code.
 *
 * A WITHOUT OVERLAPS key is a unique index too, and is enforced here the same
 * way; its last column just uses the overlaps operator rather than equality.
 * Such a key also forbids empty ranges, which is not something an operator
 * can express, so that is checked separately with
 * ExecCheckWithoutOverlapsNotEmpty().
 *
 *
 * Portions Copyright (c) 1996-2026, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *	  src/backend/access/gist/gistunique.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/genam.h"
#include "access/gist_private.h"
#include "access/tableam.h"
#include "access/xact.h"
#include "catalog/index.h"
#include "executor/executor.h"
#include "miscadmin.h"
#include "storage/lmgr.h"
#include "storage/predicate.h"
#include "utils/injection_point.h"
#include "utils/memutils.h"
#include "utils/rel.h"
#include "utils/relcache.h"
#include "utils/snapmgr.h"

/*
 * An index page we still have to search, and the LSN its parent had when we
 * read the downlink.  We need the latter to notice that the page was split
 * after we saw the downlink, in which case we must follow its rightlink too.
 */
typedef struct GISTUniqueItem
{
	BlockNumber blkno;
	GistNSN		parentlsn;
} GISTUniqueItem;

/*
 * A leaf entry that matched the value we are checking.  We collect these with
 * the page locked and look at them after unlocking it.
 */
typedef struct GISTUniqueCandidate
{
	ItemPointerData htid;
	OffsetNumber offnum;
	bool		recheck;		/* must confirm the match on the heap values */
} GISTUniqueCandidate;

/* Working state for one uniqueness check */
typedef struct GISTUniqueState
{
	Relation	rel;			/* the index */
	Relation	heapRel;
	MemoryContext checkCxt;		/* lives for the whole check */
	MemoryContext tupCxt;		/* reset for each index tuple examined */
	GISTSTATE  *giststate;
	IndexInfo  *indexInfo;
	int			nkeyatts;
	bool		is_build;

	/* The value we are checking, in index-attribute order */
	const Datum *newvals;
	const bool *newnulls;

	/* Scan keys built from newvals/newnulls, calling the consistent method */
	ScanKeyData scankeys[INDEX_MAX_KEYS];

	/* Pages left to search, oldest first */
	GISTUniqueItem *queue;
	int			qhead;			/* next one to visit */
	int			nqueue;			/* next free slot */
	int			maxqueue;

	/* The current page's matching leaf entries, and those found to be dead */
	GISTUniqueCandidate *cands;
	OffsetNumber *killed;

	/* For looking at the heap */
	SnapshotData snapshot;
	IndexFetchTableData *fetchstate;
	TupleTableSlot *slot;

	/* Lazily created, only needed to re-evaluate expression index keys */
	EState	   *estate;
	List	   *save_exprstate;
} GISTUniqueState;

static void gistUniquePush(GISTUniqueState *state, BlockNumber blkno,
						   GistNSN parentlsn);
static void gistUniqueKillItems(Buffer buffer, GistNSN pagelsn,
								const OffsetNumber *killed, int nkilled);
static bool gistUniqueKeyTest(GISTUniqueState *state, IndexTuple tuple,
							  Page page, OffsetNumber offset, bool *recheck);
static void gistUniqueFormValues(GISTUniqueState *state,
								 Datum *oldvals, bool *oldnulls);
static bool gistUniqueConflicts(GISTUniqueState *state,
								const Datum *oldvals, const bool *oldnulls);
pg_noreturn static void gistUniqueReport(GISTUniqueState *state,
										 const Datum *oldvals,
										 const bool *oldnulls);


/*
 * gistneedsuniquecheck() -- must a build of this index validate it itself?
 *
 * Inserts always check (see gistinsert()).  A build validates the finished
 * index with a second pass over the table (see gistBuildValidateUnique()),
 * but it can leave that to somebody else: index_build() already makes such a
 * pass with IndexCheckExclusion() for any index backing an exclusion
 * constraint, and a second one would only repeat it.
 *
 * An index that carries WITHOUT OVERLAPS without a constraint attached has no
 * such second pass, so it gets checked here like any other unique index.
 */
bool
gistneedsuniquecheck(Relation r, IndexInfo *indexInfo)
{
	Assert(r->rd_index->indisunique);

	return indexInfo->ii_ExclusionOps == NULL;
}

/*
 * gistcheckunique() -- check that a row does not conflict with anything else
 *		in the index.
 *
 * The index entry for heapTid must already be in the index -- we insert first
 * and search afterwards, for the reasons at the top of this file.  values and
 * isnull are that row's index column values before compression, in
 * index-attribute order.
 *
 * Throws an error if a conflict is found.  If the conflicting row was created
 * or removed by a transaction that hasn't finished yet, we wait for that
 * transaction and try again, unless checkUnique is UNIQUE_CHECK_PARTIAL, in
 * which case we report the potential conflict to the caller instead.
 *
 * The return value is only significant for UNIQUE_CHECK_PARTIAL: it is true
 * if the entry is known unique, false if it might not be.
 */
bool
gistcheckunique(Relation r, GISTSTATE *giststate, Relation heapRel,
				IndexInfo *indexInfo, ItemPointer heapTid,
				const Datum *values, const bool *isnull,
				IndexUniqueCheck checkUnique, bool is_build)
{
	GISTUniqueState state;
	MemoryContext checkCxt;
	MemoryContext oldCxt;
	bool		is_unique = true;
	bool		found_self;
	TransactionId xwait;
	uint32		speculativeToken;
	int			i;

	Assert(checkUnique != UNIQUE_CHECK_NO);
	Assert(r->rd_index->indisunique);
	Assert(ItemPointerIsValid(heapTid));

	/* Our entry is in the index; the search hasn't started yet. */
	INJECTION_POINT("gist-unique-before-search", NULL);

	/*
	 * A WITHOUT OVERLAPS key also forbids empty ranges and multiranges.  That
	 * isn't something the conflict operators can express, so it is a separate
	 * test -- and it has to come before the NULL check below, or a row could
	 * sneak an empty range in beside a NULL scalar part.
	 */
	ExecCheckWithoutOverlapsNotEmpty(heapRel, r, indexInfo, values, isnull);

	/*
	 * If any of the values is NULL and the index uses the default
	 * nulls-are-distinct mode, the row cannot conflict with anything: the
	 * search operators are strict, so nothing compares equal to it.  (For a
	 * NULLS NOT DISTINCT index we do search, using IS NULL for the null
	 * columns.)
	 */
	if (!r->rd_index->indnullsnotdistinct)
	{
		for (i = 0; i < IndexRelationGetNumberOfKeyAttributes(r); i++)
		{
			if (isnull[i])
				return true;
		}
	}

	/*
	 * Do all our work in a context of our own.  We are called from a
	 * short-lived context, but the consistent and equality methods can
	 * allocate a fair amount per index tuple examined and we may examine a
	 * lot of them.
	 */
	checkCxt = AllocSetContextCreate(CurrentMemoryContext,
									 "GiST unique check context",
									 ALLOCSET_DEFAULT_SIZES);
	oldCxt = MemoryContextSwitchTo(checkCxt);

	memset(&state, 0, sizeof(state));
	state.checkCxt = checkCxt;
	state.tupCxt = AllocSetContextCreate(checkCxt,
										 "GiST unique check temporary context",
										 ALLOCSET_DEFAULT_SIZES);
	state.rel = r;
	state.heapRel = heapRel;
	state.giststate = giststate;
	state.indexInfo = indexInfo;
	state.nkeyatts = IndexRelationGetNumberOfKeyAttributes(r);
	state.is_build = is_build;
	state.newvals = values;
	state.newnulls = isnull;
	state.maxqueue = 32;
	state.queue = palloc_array(GISTUniqueItem, state.maxqueue);
	state.cands = palloc_array(GISTUniqueCandidate, MaxIndexTuplesPerPage);
	state.killed = palloc_array(OffsetNumber, MaxIndexTuplesPerPage);

	/*
	 * Build the scan keys.  Like gistrescan() we put the opclass's consistent
	 * method into the key: the strategy number tells it which operator we
	 * actually mean, namely the one initGISTstateExclude() looked up for this
	 * column -- equality, or overlaps for the last column of a WITHOUT
	 * OVERLAPS key.
	 */
	for (i = 0; i < state.nkeyatts; i++)
	{
		Assert(OidIsValid(giststate->excludeFn[i].fn_oid));
		ScanKeyEntryInitializeWithInfo(&state.scankeys[i],
									   isnull[i] ? (SK_ISNULL | SK_SEARCHNULL) : 0,
									   i + 1,
									   giststate->uniqueStratnum[i],
									   InvalidOid,	/* no subtype */
									   r->rd_indcollation[i],
									   &giststate->consistentFn[i],
									   values[i]);
	}

	/*
	 * Tuples that aren't visible to anybody are not conflicts, but tuples
	 * that a not-yet-finished transaction inserted or deleted are, at least
	 * potentially.  A dirty snapshot tells us about both, and leaves the
	 * responsible xid behind in SnapshotDirty.xmin/xmax.
	 */
	InitDirtySnapshot(state.snapshot);

	state.fetchstate = table_index_fetch_begin(heapRel, SO_NONE);
	state.slot = table_slot_create(heapRel, NULL);

	/*
	 * If we have to wait for another transaction we start the search over
	 * from the root, because we release every buffer before waiting.
	 */
retry:
	found_self = false;
	xwait = InvalidTransactionId;
	speculativeToken = 0;
	state.qhead = state.nqueue = 0;
	gistUniquePush(&state, GIST_ROOT_BLKNO, InvalidXLogRecPtr);

	while (state.qhead < state.nqueue)
	{
		GISTUniqueItem item = state.queue[state.qhead++];
		Buffer		buffer;
		Page		page;
		GistNSN		pagelsn;
		OffsetNumber maxoff;
		OffsetNumber off;
		int			ncands;
		int			nkilled;

		CHECK_FOR_INTERRUPTS();

		buffer = ReadBuffer(r, item.blkno);
		LockBuffer(buffer, GIST_SHARE);
		gistcheckpage(r, buffer);
		page = BufferGetPage(buffer);

		/* Follow the rightlink if the page was split; see gistScanPage() */
		if (gistPageNeedsFollowRight(page, item.parentlsn))
			gistUniquePush(&state, GistPageGetOpaque(page)->rightlink,
						   item.parentlsn);

		/*
		 * A deleted page has nothing of interest on it.  Note we must check
		 * this after the NSN check above: the page may have held tuples that
		 * were moved to its right sibling before it was deleted.
		 */
		if (GistPageIsDeleted(page))
		{
			UnlockReleaseBuffer(buffer);
			continue;
		}

		/*
		 * The LSN of this page is the parent LSN for any child we push.  We
		 * only hold a shared lock, so read it atomically.
		 */
		pagelsn = BufferGetLSNAtomic(buffer);

		/*
		 * Collect the entries on this page that match.  Only the consistent
		 * methods run while we hold the lock.  Everything else -- visiting
		 * the heap, re-evaluating index expressions, calling the equality
		 * operator, building an error message -- can run user code or touch
		 * the catalogs, and waits until we have unlocked the page, as in an
		 * ordinary GiST scan.  We keep the pin, so that we can come back and
		 * set LP_DEAD hints.
		 */
		ncands = 0;
		maxoff = PageGetMaxOffsetNumber(page);
		for (off = FirstOffsetNumber; off <= maxoff; off = OffsetNumberNext(off))
		{
			ItemId		iid = PageGetItemId(page, off);
			IndexTuple	it;
			bool		match;
			bool		recheck;

			/*
			 * An entry that somebody already found to be dead cannot be a
			 * conflict.
			 */
			if (ItemIdIsDead(iid))
				continue;

			it = (IndexTuple) PageGetItem(page, iid);

			/*
			 * The consistent methods allocate as they go, and there can be a
			 * lot of tuples to look at, so give them a context of their own.
			 */
			MemoryContextSwitchTo(state.tupCxt);
			match = gistUniqueKeyTest(&state, it, page, off, &recheck);
			MemoryContextSwitchTo(checkCxt);
			MemoryContextReset(state.tupCxt);

			if (!match)
				continue;

			if (!GistPageIsLeaf(page))
			{
				gistUniquePush(&state,
							   ItemPointerGetBlockNumber(&it->t_tid),
							   pagelsn);
				continue;
			}

			/* Ignore the entry for the tuple we are checking. */
			if (ItemPointerEquals(&it->t_tid, heapTid))
			{
				found_self = true;
				continue;
			}

			state.cands[ncands].htid = it->t_tid;
			state.cands[ncands].offnum = off;
			state.cands[ncands].recheck = recheck;
			ncands++;
		}

		LockBuffer(buffer, GIST_UNLOCK);

		nkilled = 0;
		for (i = 0; i < ncands; i++)
		{
			GISTUniqueCandidate *cand = &state.cands[i];
			bool		match;
			bool		call_again = false;
			bool		all_dead = false;
			Datum		oldvals[INDEX_MAX_KEYS];
			bool		oldnulls[INDEX_MAX_KEYS];

			/*
			 * Is there a live (or in-doubt) row behind this entry?  We need
			 * the heap tuple anyway if the index-level test was lossy, so
			 * fetch it into a slot rather than using
			 * table_index_fetch_tuple_check().
			 */
			ExecClearTuple(state.slot);
			if (!table_index_fetch_tuple(state.fetchstate, &cand->htid,
										 &state.snapshot, state.slot,
										 &call_again, &all_dead))
			{
				/*
				 * Nobody can see this row any more, so we may as well tell
				 * later scans not to bother with the index entry either.
				 *
				 * Not during a build, though: nobody else can use the index
				 * yet, so there is nothing to gain, and the validation pass
				 * has to re-find each row's own entry, which the dead-item
				 * test above would then skip.
				 */
				if (all_dead && !is_build)
					state.killed[nkilled++] = cand->offnum;
				continue;
			}

			/*
			 * If the opclass could not give a definite answer from the index
			 * tuple alone -- multirange_ops, for instance, only stores the
			 * bounding range of each multirange -- apply the real operator to
			 * the real values.
			 */
			if (cand->recheck)
			{
				MemoryContextSwitchTo(state.tupCxt);
				gistUniqueFormValues(&state, oldvals, oldnulls);
				match = gistUniqueConflicts(&state, oldvals, oldnulls);
				MemoryContextSwitchTo(checkCxt);
				MemoryContextReset(state.tupCxt);

				if (!match)
					continue;
			}

			/*
			 * We have a conflict, or at least a potential one.  If the caller
			 * only wants to know whether it might not be unique, we are
			 * usually done; it will check again later.
			 *
			 * The exception is two speculative insertions (INSERT ... ON
			 * CONFLICT) that find each other: we insert before we search, so
			 * each can see the other's tuple, and if both back out then both
			 * retry, and they can meet the same way again indefinitely. Break
			 * the tie as check_exclusion_or_unique_constraint() does in
			 * CEOUC_LIVELOCK_PREVENTING_WAIT mode: the one whose XID is older
			 * waits for the other's speculative insertion to be confirmed or
			 * killed, while the younger backs out.  Like any other wait, it
			 * waits only once the rest of the tree has turned up no settled
			 * conflict.
			 */
			if (checkUnique == UNIQUE_CHECK_PARTIAL)
			{
				if (state.snapshot.speculativeToken &&
					TransactionIdIsValid(state.snapshot.xmin) &&
					TransactionIdPrecedes(GetCurrentTransactionId(),
										  state.snapshot.xmin))
				{
					if (!TransactionIdIsValid(xwait))
					{
						xwait = state.snapshot.xmin;
						speculativeToken = state.snapshot.speculativeToken;
					}
					continue;
				}

				ReleaseBuffer(buffer);
				is_unique = false;
				INJECTION_POINT("gist-unique-partial-conflict", NULL);
				goto done;
			}

			/*
			 * If the row is being inserted or deleted by a transaction that
			 * hasn't finished, we don't know yet whether it is really a
			 * conflict.  Remember it and keep looking: a conflict with a row
			 * that is already committed lets us report the violation right
			 * away instead of waiting on somebody.  That matters here in a
			 * way it doesn't for nbtree, because we have to visit every
			 * consistent page anyway, and because our own tuple is already in
			 * the index while we wait, so waiting risks a deadlock.
			 */
			if (unlikely(TransactionIdIsValid(state.snapshot.xmin) ||
						 TransactionIdIsValid(state.snapshot.xmax)))
			{
				if (!TransactionIdIsValid(xwait))
				{
					xwait = TransactionIdIsValid(state.snapshot.xmin) ?
						state.snapshot.xmin : state.snapshot.xmax;
					speculativeToken = state.snapshot.speculativeToken;
				}
				continue;
			}

			/*
			 * Otherwise this is a definite conflict.  But before complaining,
			 * check whether the row we are inserting is itself already dead;
			 * if it is, there is nothing to complain about.  This is a waste
			 * of time in ordinary operation, but CREATE INDEX CONCURRENTLY
			 * and a build's validation pass (gistBuildValidateUnique()) both
			 * need it.
			 */
			if (!table_index_fetch_tuple_check(heapRel, heapTid,
											   SnapshotSelf, NULL))
			{
				ReleaseBuffer(buffer);
				goto done;
			}

			/*
			 * Check for a conflict-in as we would if we were about to write
			 * to this page.  We aren't going to write, but we want a chance
			 * to report an SSI conflict that would otherwise be masked by the
			 * constraint violation.
			 */
			CheckForSerializableConflictIn(r, NULL, item.blkno);

			/*
			 * A WITHOUT OVERLAPS key's message describes the row we conflict
			 * with as well as our own.  Recompute its key values rather than
			 * reusing anything the recheck above produced, which lived in the
			 * per-tuple context and is gone by now.  We still hold the heap
			 * pin, so the slot is good.
			 */
			if (RelationIndexHasWithoutOverlaps(r))
				gistUniqueFormValues(&state, oldvals, oldnulls);

			ReleaseBuffer(buffer);

			gistUniqueReport(&state, oldvals, oldnulls);
		}

		if (nkilled > 0)
			gistUniqueKillItems(buffer, pagelsn, state.killed, nkilled);

		ReleaseBuffer(buffer);
	}

	/*
	 * We got through the whole tree without finding a settled conflict.  If
	 * some other transaction has one in flight, wait for it to commit or roll
	 * back and then look again.  We hold no buffers at this point, and the
	 * tree can change while we wait, so we simply start over.
	 */
	if (unlikely(TransactionIdIsValid(xwait)))
	{
		/*
		 * If it's a speculative insertion, wait for that insertion to be
		 * confirmed or killed rather than for the whole transaction.  Don't
		 * sleep holding a pin on the heap page we looked at last.
		 */
		ExecClearTuple(state.slot);
		table_index_fetch_reset(state.fetchstate);
		if (speculativeToken)
			SpeculativeInsertionWait(xwait, speculativeToken);
		else
			XactLockTableWait(xwait, r, heapTid, XLTW_InsertIndex);

		goto retry;
	}

	if (checkUnique == UNIQUE_CHECK_EXISTING && !found_self)
		elog(ERROR, "failed to re-find tuple within index \"%s\"",
			 RelationGetRelationName(r));

done:
	ExecDropSingleTupleTableSlot(state.slot);
	table_index_fetch_end(state.fetchstate);
	if (state.estate != NULL)
	{
		FreeExecutorState(state.estate);

		/*
		 * FormIndexDatum() caches the compiled index expressions in the
		 * IndexInfo.  If it compiled them into the EState we just threw away
		 * (which shouldn't happen, since our caller had to evaluate them to
		 * get here, but let's not depend on that) we must not leave the
		 * dangling pointer behind.
		 */
		indexInfo->ii_ExpressionsState = state.save_exprstate;
	}

	MemoryContextSwitchTo(oldCxt);
	MemoryContextDelete(checkCxt);

	return is_unique;
}

/*
 * Add a page to the list of pages we still have to search.
 */
static void
gistUniquePush(GISTUniqueState *state, BlockNumber blkno, GistNSN parentlsn)
{
	if (state->nqueue >= state->maxqueue)
	{
		/* Reclaim the space taken by the pages we have already visited */
		if (state->qhead > state->maxqueue / 2)
		{
			memmove(state->queue, state->queue + state->qhead,
					(state->nqueue - state->qhead) * sizeof(GISTUniqueItem));
			state->nqueue -= state->qhead;
			state->qhead = 0;
		}
		else
		{
			state->maxqueue *= 2;
			state->queue = repalloc_array(state->queue, GISTUniqueItem,
										  state->maxqueue);
		}
	}

	state->queue[state->nqueue].blkno = blkno;
	state->queue[state->nqueue].parentlsn = parentlsn;
	state->nqueue++;
}

/*
 * Mark index entries whose heap rows are dead to everyone, as gistkillitems()
 * does for a scan.  We unlocked the page after reading it, so the entries may
 * have moved since; only touch the page if its LSN says it hasn't changed.
 * The caller holds a pin on the buffer, and still does afterwards.
 */
static void
gistUniqueKillItems(Buffer buffer, GistNSN pagelsn,
					const OffsetNumber *killed, int nkilled)
{
	Page		page = BufferGetPage(buffer);

	LockBuffer(buffer, GIST_SHARE);

	if (BufferGetLSNAtomic(buffer) == pagelsn &&
		BufferBeginSetHintBits(buffer))
	{
		for (int i = 0; i < nkilled; i++)
			ItemIdMarkDead(PageGetItemId(page, killed[i]));
		GistMarkPageHasGarbage(page);
		BufferFinishSetHintBits(buffer, true, true);
	}

	LockBuffer(buffer, GIST_UNLOCK);
}

/*
 * Does this index tuple match the value we are checking?
 *
 * gistindex_qualtest() does the work.  *recheck is set if any consistent
 * method said its answer was only approximate, in which case a leaf match has
 * to be confirmed against the heap values.
 */
static bool
gistUniqueKeyTest(GISTUniqueState *state, IndexTuple tuple, Page page,
				  OffsetNumber offset, bool *recheck)
{
	/*
	 * A leftover invalid tuple from pre-9.1 tells us nothing about its
	 * subtree, so we have to look at the whole subtree.
	 */
	if (GistTupleIsInvalid(tuple))
	{
		if (GistPageIsLeaf(page))	/* shouldn't happen */
			elog(ERROR, "invalid GiST tuple found on leaf page");
		*recheck = false;
		return true;
	}

	return gistindex_qualtest(state->giststate, state->rel, state->scankeys,
							  state->nkeyatts, tuple, page, offset, recheck);
}

/*
 * Extract the index column values of the heap tuple in state->slot.
 */
static void
gistUniqueFormValues(GISTUniqueState *state, Datum *oldvals, bool *oldnulls)
{
	if (state->indexInfo->ii_Expressions != NIL)
	{
		if (state->estate == NULL)
		{
			MemoryContext oldcxt;

			/* The EState has to outlive our per-tuple context */
			oldcxt = MemoryContextSwitchTo(state->checkCxt);
			state->estate = CreateExecutorState();
			MemoryContextSwitchTo(oldcxt);
			state->save_exprstate = state->indexInfo->ii_ExpressionsState;
			GetPerTupleExprContext(state->estate)->ecxt_scantuple = state->slot;
		}
		ResetPerTupleExprContext(state->estate);
	}

	FormIndexDatum(state->indexInfo, state->slot, state->estate,
				   oldvals, oldnulls);
}

/*
 * Do the given values really conflict with the ones we are checking?
 *
 * We ask the opfamily's equality operator itself.  All of the columns have to
 * be equal for the rows to conflict.
 */
static bool
gistUniqueConflicts(GISTUniqueState *state,
					const Datum *oldvals, const bool *oldnulls)
{
	int			i;

	for (i = 0; i < state->nkeyatts; i++)
	{
		if (oldnulls[i] || state->newnulls[i])
		{
			/*
			 * We only get here with NULLs at all for a NULLS NOT DISTINCT
			 * index, where two NULLs conflict but a NULL and a non-NULL do
			 * not.
			 */
			if (oldnulls[i] != state->newnulls[i])
				return false;
			continue;
		}

		if (!DatumGetBool(FunctionCall2Coll(&state->giststate->excludeFn[i],
											state->rel->rd_indcollation[i],
											oldvals[i],
											state->newvals[i])))
			return false;
	}

	return true;
}

/*
 * Complain about a conflict.  Never returns.
 *
 * For an ordinary unique index the wording matches nbtree's, including the
 * different message a build uses ("could not create unique index"), so that
 * the two access methods are interchangeable from the user's point of view.
 *
 * An index that is unique and an exclusion constraint at the same time is a
 * WITHOUT OVERLAPS key, and users expect the exclusion constraint wording for
 * those, naming the existing key as well as ours -- so oldvals/oldnulls
 * describe the row we conflicted with.
 */
pg_noreturn static void
gistUniqueReport(GISTUniqueState *state,
				 const Datum *oldvals, const bool *oldnulls)
{
	Relation	rel = state->rel;
	Relation	heapRel = state->heapRel;
	char	   *key_desc;

	key_desc = BuildIndexValueDescription(rel, state->newvals, state->newnulls);

	if (RelationIndexHasWithoutOverlaps(rel))
	{
		char	   *old_key_desc;
		bool		isconstraint = rel->rd_index->indisexclusion;

		/*
		 * Overlapping rows are not "duplicates", so name both of them.  An
		 * index that backs an exclusion constraint gets that constraint's
		 * usual wording; one that carries WITHOUT OVERLAPS on its own is
		 * still just a unique index as far as the user is concerned.
		 */
		old_key_desc = BuildIndexValueDescription(rel, oldvals, oldnulls);

		if (state->is_build)
		{
			/*
			 * index_build() validates an exclusion constraint's index itself,
			 * so only a standalone WITHOUT OVERLAPS index gets here (see
			 * gistneedsuniquecheck()).
			 */
			Assert(!isconstraint);
			ereport(ERROR,
					(errcode(ERRCODE_EXCLUSION_VIOLATION),
					 errmsg("could not create unique index \"%s\"",
							RelationGetRelationName(rel)),
					 key_desc && old_key_desc ?
					 errdetail("Key %s conflicts with key %s.",
							   key_desc, old_key_desc) :
					 errdetail("Key conflicts exist."),
					 errtableconstraint(heapRel,
										RelationGetRelationName(rel))));
		}
		else
			ereport(ERROR,
					(errcode(ERRCODE_EXCLUSION_VIOLATION),
					 isconstraint ?
					 errmsg("conflicting key value violates exclusion constraint \"%s\"",
							RelationGetRelationName(rel)) :
					 errmsg("conflicting key value violates unique constraint \"%s\"",
							RelationGetRelationName(rel)),
					 key_desc && old_key_desc ?
					 errdetail("Key %s conflicts with existing key %s.",
							   key_desc, old_key_desc) :
					 errdetail("Key conflicts with existing key."),
					 errtableconstraint(heapRel,
										RelationGetRelationName(rel))));
	}
	else if (state->is_build)
		ereport(ERROR,
				(errcode(ERRCODE_UNIQUE_VIOLATION),
				 errmsg("could not create unique index \"%s\"",
						RelationGetRelationName(rel)),
				 key_desc ? errdetail("Key %s is duplicated.", key_desc) :
				 errdetail("Duplicate keys exist."),
				 errtableconstraint(heapRel,
									RelationGetRelationName(rel))));
	else
		ereport(ERROR,
				(errcode(ERRCODE_UNIQUE_VIOLATION),
				 errmsg("duplicate key value violates unique constraint \"%s\"",
						RelationGetRelationName(rel)),
				 key_desc ? errdetail("Key %s already exists.", key_desc) : 0,
				 errtableconstraint(heapRel,
									RelationGetRelationName(rel))));

	pg_unreachable();
}
