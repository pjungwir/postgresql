# Did v8 address our 2026-02-03 review?

Assessing Erik Wienhold's reply
([6d710ac3-3a66-4b31-b35a-0b4d9afdda42@ewie.name](https://www.postgresql.org/message-id/6d710ac3-3a66-4b31-b35a-0b4d9afdda42%40ewie.name))
against the review you and Yan Haibo posted on 2026-02-03
([CA+renyW6-7aH74o-Gv2k+6emEXwznXxg=GkmTaKhDcresQQ9bg@mail.gmail.com](https://www.postgresql.org/message-id/CA%2BrenyW6-7aH74o-Gv2k%2B6emEXwznXxg%3DGkmTaKhDcresQQ9bg%40mail.gmail.com)).

Line numbers refer to `dba318893f8`. Everything below is checked against the **code as committed** (`dba318893f8` = v8),
not against Erik's description of it. Where the two disagree I went with the code.

---

## Bottom line

He took the review seriously. Of your ~22 distinct points, **11 are fully
addressed**, several of them adopting your exact wording or your exact suggested
construct (`for_each_from`, `opt_with_no_or_old_data`, the `t_bits` test, the
"unlike when using OR REPLACE" doc phrasing). Two of the three patch files
disappeared entirely because he took your advice, which is why a chunk of the
review is now moot rather than ignored.

**One point he skipped outright, and it is a live bug**: you asked about
`ExplainOneUtility`, and `EXPLAIN CREATE OR REPLACE MATERIALIZED VIEW` on an
existing matview currently fails with `ERROR: relation already exists` (§A).

Beyond that, the pattern worth flagging is that **three of his partial fixes each
left the second half undone**, and in two cases the leftover half is what later
reviewers tripped over — Rafia Sabih's 2026-07-23 race report is a direct
consequence of how your "check should happen in the caller" point was
implemented (§B) — the refactor moved the check you objected to without
collapsing the redundant lookup underneath it. That's the thing I'd push on in a
reply: not that he ignored you, but that the follow-through stopped one step
short, in the exact spot you were pointing at.

---

## Scorecard

| # | Your point | Status | Verified how |
|---|---|---|---|
| 1 | Doc wording: "unless … instead" reads badly | **Done** — your exact "unlike when using `OR REPLACE`" | `create_materialized_view.sgml` |
| 2 | Replace should be its own function | **Done** — `create_ctas_replace()`, `create_ctas_internal()` untouched | `createas.c:243` |
| 3 | `RangeVarGetAndCheckCreationNamespace` shouldn't run without `OR REPLACE` | **Done** — now `if (is_matview && into->replace)` | `createas.c:220` |
| 4 | Replace branch needs the `DefineVirtualRelation` comments | **Done** — incl. "Relation is already locked, but we must build a relcache entry." | `createas.c:252` |
| 5 | Use `for_each_from` instead of manual skipping | **Done**, exactly as suggested | `createas.c:285` |
| 6 | Are the AT subcommands no-ops when unchanged? | **Answered, half the question** | §D |
| 7 | Add an `else` for parallel indentation | **Partial** — restructured, still subtle | §E |
| 8 | Changed `CreateTableAsRelExists` contract without changing its comment | **Done** — function left alone | `createas.c:571` |
| 9 | Existence check should live in the caller | **Partial — race left in place** | §B |
| 10 | `ExplainOneUtility` needs `OR REPLACE` handling | **Not addressed — live bug** | §A |
| 11 | Don't repeat all those error messages | **Done differently — by forking the function** | §C |
| 12–13 | Parser / tab completion look fine | n/a | |
| 14 | Roll 0002 into 0001 | **Done** — single patch | |
| 15 | `""` as a magic tablespace value | **Done well** — real name resolved in `createas.c`; the `tablecmds.c` change is gone | `createas.c:307-337` |
| 16 | Should happen during analysis | **Moot** — no analysis change any more | |
| 17 | Locking questions around `GetDefaultTablespace` | **Moot**, small residue | §F |
| 18 | What about partitions? | **Moot** — matviews can't be partitioned | |
| 19 | `elog` → `ereport`, or a comment | **Done** (`ereport`); comment still worth having | §G |
| 20 | Fourth `CreateMatViewStmt` production is a lot | **Partial — added alongside, not instead** | §H |
| 21 | Want a WITH OLD DATA + new column test | **Done** — your exact test | `matview.sql:466-478` |
| 22 | Unique index / domain / other constraints + WITH OLD DATA | **Mostly answered; one gap, one now-definitive answer** | §I |

---

## §A. `ExplainOneUtility` — not addressed, and it's broken

You wrote:

> Does this require a change to ExplainOneUtility, which also calls this
> function? At least we probably need to handle OR REPLACE there.

His reply does not mention `EXPLAIN`, `ExplainOneUtility`, or `explain.c`
anywhere. And `explain.c:417` still reads:

```c
if (CreateTableAsRelExists(ctas))
{
    if (ctas->objtype == OBJECT_TABLE)
        ExplainDummyGroup("CREATE TABLE AS", NULL, es);
    else if (ctas->objtype == OBJECT_MATVIEW)
        ExplainDummyGroup("CREATE MATERIALIZED VIEW", NULL, es);
    ...
```

`CreateTableAsRelExists()` throws when the relation exists and
`ctas->if_not_exists` is false — and the `OR REPLACE` production sets
`if_not_exists = false`. So:

```sql
CREATE MATERIALIZED VIEW mx AS SELECT 1 AS a;

EXPLAIN (COSTS OFF) CREATE OR REPLACE MATERIALIZED VIEW mx AS SELECT 2 AS a;
-- ERROR:  relation "mx" already exists

EXPLAIN (ANALYZE, COSTS OFF) CREATE OR REPLACE MATERIALIZED VIEW mx AS SELECT 3 AS a;
-- ERROR:  relation "mx" already exists
```

Reproduced on a build of `dba318893f8`. `EXPLAIN` of a *non-existent* matview
with `OR REPLACE` works fine, so the failure is specifically the case the whole
feature exists to serve.

This is not obscure. `matview.sql:308-321` — the fourteen lines immediately above
the new `OR REPLACE` section — is a block of `EXPLAIN (ANALYZE ...)` tests added
for the `IF NOT EXISTS` feature, covering both the plain and `IF NOT EXISTS`
forms, with and without `WITH NO DATA`. The `OR REPLACE` section adds no
`EXPLAIN` coverage at all. The template was sitting right there.

Fix is small — `ExplainOneUtility` needs to take the replace path into account
rather than treating "relation exists" as "nothing to plan". `EXPLAIN` without
`ANALYZE` should presumably plan and print the new query without touching the
matview; `EXPLAIN ANALYZE` should presumably do the replace. That choice is worth
stating explicitly on-list, because `EXPLAIN ANALYZE CREATE OR REPLACE
MATERIALIZED VIEW` performing a full rewrite and tablespace move (§3 of the main
review) is a sharp edge either way.

**This is the one point I'd lead a reply with.**

---

## §B. The existence check moved to the caller — but the old call stayed

You wrote:

> But is this really factored correctly? Maybe the check should happen in the
> caller instead.

He did add it to the caller. `ExecCreateTableAs()` now calls
`CreateTableAsRelReplaceable()` (`createas.c:385`). What he did *not* do is
remove the lookup further down: `create_ctas_nodata()` still resolves the same
name a second time (`createas.c:220`), and that second lookup is the one that
takes `AccessExclusiveLock`.

So the name is still resolved twice — **unlocked** first, then locked in the
callee. That is precisely the gap Rafia Sabih reported on 2026-07-23, the most
recent message in the thread and still open.

To be fair to Erik: v7 had the same double lookup (`CreateTableAsRelExists()`
did an unlocked `get_relname_relid()`, then `create_ctas_internal()` took the
lock), so v8 did not *introduce* the race. But your point was aimed squarely at
this factoring, and the refactor moved the check without collapsing the two
lookups — so the race survived a round of review that was specifically about
where that check belongs.

It also has a consequence Rafia didn't mention. Tom asked for `WITH OLD DATA` to
*fail* rather than be silently reinterpreted, and that check lives on the
non-replace branch (`createas.c:452`). If the matview is dropped concurrently
between the two lookups, control falls into the create path with
`matviewOid == InvalidOid` — and the guard is never reached. You get a matview
marked populated with no rows and no error: exactly the silent reinterpretation
Tom rejected.

The clean answer is the one you originally asked for: resolve once, under
`AccessExclusiveLock`, in the caller, and pass the OID down.

---

## §C. Error-message duplication — solved by making more of it

You wrote:

> Instead of repeating so much, perhaps `errmsg("cannot drop columns from %s",
> is_matview ? …)`? Or since that is probably bad for translators, at least this:
> `errmsg(is_matview ? … : …)`. Likewise with more error messages in this
> function. (There are a lot of them.)

His answer was to avoid the conditionals entirely by giving matviews their own
`checkMatviewColumns()` in `matview.c`. That does remove the branching you
objected to, and it's defensible for translators.

But it is a straight fork. Normalising the noun and diffing the two functions,
they are the same code — same five checks in the same order, same `XXX msg not
right` comment carried over, differing only in the noun, the `ALTER
MATERIALIZED VIEW` hint text, and brace/paren style (63 vs 72 lines).

So the total repetition went *up*, and it's now the kind that can drift silently:
a future fix to `checkViewColumns()` will not reach matviews, and nothing in
either file points at the other. If he prefers two functions, they should at
minimum cross-reference each other in comments. A shared helper taking the
relkind (or a noun string) would still be my preference and would satisfy your
original point properly.

---

## §D. The no-op question — answered for half the cases

You asked:

> Just to confirm, this is a noop if the access method is already the same? And
> likewise with the other AT subcommands?

He answered precisely and correctly: no-op for `AT_SetAccessMethod`
(`ATPrepSetAccessMethod` skips phase 3 — confirmed at `tablecmds.c:17212`),
no-op for `AT_SetTableSpace` (via `CheckRelationTableSpaceMove`), *not* a no-op
for `AT_ReplaceRelOptions`.

What neither of you came back to is the case where the values are **not** the
same — which, given the reset-to-defaults semantics Tom mandated, is the common
case for anyone who ever specified a tablespace or access method. Then it is a
full rewrite and a physical relocation, triggered by a command that never
mentioned storage. I measured this in §3 of the main review: a bare `CREATE OR
REPLACE` silently drops `autovacuum_enabled=false`, moves the matview back to the
default tablespace, and strands its indexes in the old one.

Your question got a true answer that happens to describe the reassuring half.
Worth re-asking about the other half — and it's still undocumented.

---

## §E. The `else` — restructured, but the control flow is subtler than it looks

You asked for parallel indentation. What v8 has:

```c
if (is_matview && into->replace)
{
    if (CreateTableAsRelReplaceable(stmt))
    {
        ...
        return address;
    }
}
else if (CreateTableAsRelExists(stmt))
    return InvalidObjectAddress;
```

The two arms are now parallel, so the letter of the request is met. But when
`CreateTableAsRelReplaceable()` returns false the code falls out of the `if` and
skips `CreateTableAsRelExists()` entirely. That is *correct* — the relation
doesn't exist, and `CreateTableAsRelReplaceable()` has already raised the
duplicate-relation error if it did — but it's correct by a chain of reasoning
that isn't written down anywhere. A comment on the fall-through would earn its
keep.

---

## §F. Residual from the tablespace locking questions

Your P16–P18 evaporated with the `tablecmds.c` patch, correctly. Small leftover:
`create_ctas_replace()` now resolves the default tablespace to an OID
(`GetDefaultTablespace`), converts it to a **name** (`get_tablespace_name`), and
hands the name to `ALTER TABLE`, which converts it straight back to an OID
(`get_tablespace_oid`). The round trip is pointless work and reopens a narrow
window in which the tablespace could vanish between the two lookups. Not worth
blocking on, but if `AlterTableCmd` ever grows an OID field for this, it should
use it.

---

## §G. `WITH OLD DATA` on a new matview

`elog` → `ereport`: done. But note your parenthetical no longer holds — you
guessed "the current parser productions should prevent us from reaching this
code", and in v8 they *don't*: `CREATE OR REPLACE … WITH OLD DATA` against a
non-existent matview reaches it, and Tom explicitly wants it to. So it's a real
user-facing error now, which makes the comment you asked for *more* valuable, not
less. Two small things while he's there: `ERRCODE_SYNTAX_ERROR` is a stretch for
what is a semantic condition, and per §B this error is exactly what the race can
skip.

---

## §I. Constraints and `WITH OLD DATA` — his reasoning holds; here's the rest of the answer

You asked three things. His reply:

> "But besides that I don't see how keeping the old data could violate a unique
> index or any other constraint on a domain type. During the execution of the
> matview replacement the unique index and domain types remain unaltered. So the
> old data will still satisfy any pre-existing constraints."

> "Adding a column of a domain type with NOT NULL constraint can indeed cause
> WITH OLD DATA to fail since we're setting new columns to NULL in that case."

The reasoning is sound and he found the one exception to his own general claim.
Filling in what's left:

**Unique index — safe, but untested.** Verified: retained rows are unchanged, so
a pre-existing unique index cannot be violated by the replace itself. A new query
that *would* produce duplicates fails cleanly at the next `REFRESH`
(`could not create unique index … Key (a)=(1) is duplicated`) with the old
contents left intact. Also verified this survives the storage rewrite from §D:
matview in a non-default tablespace, unique index, replace with `WITH OLD DATA`
adding a column — data retained, new column NULL, index rebuilt and still chosen
by the planner, `relispopulated` still true. Worth a short test, since it's
cheap and pins behavior that currently rests on an argument in a mailing-list
post.

**"Any other constraints?" — the answer is no, and it's now definitive.**
Matviews reject every constraint type except indexes:

```
ALTER MATERIALIZED VIEW mc ALTER COLUMN a SET NOT NULL;
-- ERROR:  ALTER action ALTER COLUMN ... SET NOT NULL cannot be performed on relation "mc"
ALTER TABLE mc ADD CONSTRAINT mc_chk CHECK (a > 0);        -- same error
ALTER TABLE mc ADD CONSTRAINT mc_pk PRIMARY KEY (a);       -- same error
ALTER TABLE mc ADD CONSTRAINT mc_ex EXCLUDE USING btree (a WITH =);  -- same error
```

So the surface is exactly **indexes + domain constraints**, and both are now
accounted for. That's worth saying on-list so the question is closed rather than
left hanging.

---

## §H. The parser suggestion, taken halfway

You suggested:

> Perhaps **instead of** `opt_with_data` we add a new production
> `opt_with_no_or_old_data` that can return 3 alternatives (WITH [{NO|OLD}] DATA)?

He added `opt_with_no_or_old_data` and the `WithDataOption` enum — good, and it
does collapse the fourth production. But he added it *alongside* `opt_with_data`
rather than instead of it. Only the `OR REPLACE` production uses the new one;
plain `CREATE MATERIALIZED VIEW`, `CREATE TABLE AS`, `SELECT INTO` and
`EXECUTE … INTO` all still use `opt_with_data` and the old `skipData` bool.

Result: `IntoClause` now carries the same fact twice, and the new field is wrong
almost everywhere. After `CREATE TABLE AS … WITH NO DATA` the node says
`data == WITHDATA_DEFAULT` while `skipData == true`. Nothing in this patch reads
it wrongly, but it's a trap, and it's the direct consequence of doing "add"
instead of "instead of". Converting the remaining producers is mechanical and
small. (This is §6 of the main review.)

---

## What I'd ask for in a reply

Ranked by what actually blocks the patch:

1. **`ExplainOneUtility` (§A)** — unaddressed from your review, currently a
   user-visible error, and it needs a design decision about what
   `EXPLAIN ANALYZE CREATE OR REPLACE MATERIALIZED VIEW` should *do*.
2. **Resolve the name once under lock (§B)** — closes Rafia's open race, and
   closes the hole through which `WITH OLD DATA` can bypass Tom's requested error.
3. **Finish the parser conversion (§H)** — retire `skipData` in favour of
   `WithDataOption` everywhere, so the new field stops lying.
4. **Document the storage reset, and re-ask the other half of the no-op question
   (§D)** — including whether stranding indexes in the old tablespace is
   intended.
5. **De-duplicate or at least cross-reference the two column checks (§C).**
6. Small: fall-through comment (§E), comment + errcode on the `WITH OLD DATA`
   error (§G), unique-index test (§I).

Plus the two items from the main review that nobody in the thread has raised at
all: the `ddl_command_end` crash and the `REFRESH MATERIALIZED VIEW` command tag.
Both now have tests and fixes in the working tree.
