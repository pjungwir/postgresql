# Review: `dba318893f8` — Add OR REPLACE option to CREATE MATERIALIZED VIEW

**Author:** Erik Wienhold <ewie@ewie.name>
**Branch:** `create-or-replace-matview` (on top of `dd62a71013c`)
**Diff:** 12 files, +813 / −27

---

## Summary

The feature is a genuinely useful one and the overall shape is right: reuse the
relation, run the column compatibility check that `CREATE OR REPLACE VIEW`
already does, drive the metadata changes through `AlterTableInternal()`, then
`StoreViewQuery()` the new rule. Doing it this way preserves the matview's OID,
ACLs, comments, indexes, and dependents, which is the whole point of `OR
REPLACE`. `WITH OLD DATA` is a sensible addition and the motivation (staying
populated so a later `REFRESH ... CONCURRENTLY` is legal) is real.

But it is not committable as-is. There is **one reproducible server crash**, one
**user-visible protocol regression** (wrong command tag), and a set of silent
side effects on matview storage properties that are neither documented nor, in
my opinion, defensible as designed.

**Verdict: needs another round.** Items 1 and 2 are blockers. Item 3 turns out to
be settled thread policy, not an open question — see §3 and §10, where I withdraw
my original recommendation.

Everything below was verified against an assert-enabled build of this commit
(`gcc 14.2.0`, `USE_ASSERT_CHECKING`). `make -C src/test/regress check` passes on
the unmodified commit: **245/245** — which is itself part of the problem, since
nothing exercises the crash in §1.

**Items 1 and 2 now have tests and fixes in the working tree** (§11).

---

## 1. Blocker: server crash when a `ddl_command_end` event trigger exists — *fixed, §11*

`create_ctas_replace()` calls `AlterTableInternal()` at
`src/backend/commands/createas.c:341`, under this comment:

```c
/* EventTriggerAlterTableStart called by ProcessUtilitySlow */
AlterTableInternal(matviewOid, atcmds, true);
```

The comment was copied from `src/backend/commands/view.c:164,197`, where it is
true — `ProcessUtilitySlow()` wraps `T_ViewStmt` in
`EventTriggerAlterTableStart()` / `EventTriggerAlterTableEnd()`
(`src/backend/tcop/utility.c:1649-1657`). It is **not** true for
`T_CreateTableAsStmt`, which has no such wrapper
(`src/backend/tcop/utility.c:1681-1684`). So
`currentEventTriggerState->currentCommand` is still NULL when
`AlterTableInternal()` dereferences it.

Reproducer:

```sql
CREATE FUNCTION noop_et() RETURNS event_trigger LANGUAGE plpgsql AS
  $$ BEGIN RAISE NOTICE 'et fired: %', tg_tag; END $$;
CREATE EVENT TRIGGER et_end ON ddl_command_end EXECUTE FUNCTION noop_et();

CREATE MATERIALIZED VIEW m1 AS SELECT 1 AS a;
CREATE OR REPLACE MATERIALIZED VIEW m1 AS SELECT 2 AS a;   -- crash
```

```
LOG:  client backend (PID 2335482) was terminated by signal 11: Segmentation fault
DETAIL:  Failed process was running: CREATE OR REPLACE MATERIALIZED VIEW m1 AS SELECT 2 AS a;
```

Backtrace:

```
#0  EventTriggerAlterTableRelid (objectId=16386) at event_trigger.c:1803
        currentEventTriggerState->currentCommand->d.alterTable.objectId = objectId;
#1  AlterTableInternal (relid=16386, ...)          at tablecmds.c:4662
#2  create_ctas_replace (..., matviewOid=16386)    at createas.c:341
#3  create_ctas_nodata (...)                       at createas.c:228
#4  ExecCreateTableAs (...)                        at createas.c:388
#5  ProcessUtilitySlow (...)                       at utility.c:1682
```

A trigger on `ddl_command_start` alone does not crash — it is specifically the
command-collection state set up for `ddl_command_end` / `sql_drop` /
`table_rewrite`.

**Fix direction:** wrap the `T_CreateTableAsStmt` case in `ProcessUtilitySlow()`
the same way `T_ViewStmt` is wrapped, or call
`EventTriggerAlterTableStart()`/`End()` around the `AlterTableInternal()` call in
`create_ctas_replace()` itself. The first is more consistent with existing
practice, but it changes event-trigger output for *all* CTAS, so it needs a
deliberate decision about what `pg_event_trigger_ddl_commands()` should report
for a replaced matview — right now it would surface a stashed `alter table`
subcommand list for something the user typed as `CREATE MATERIALIZED VIEW`.
Please also decide whether the internal `ALTER TABLE` bookkeeping should be
hidden from event triggers entirely, the way `ExecRefreshMatView()`'s internal
DDL is (`utility.c:1686-1705` inhibits collection around it).

Whatever the resolution: **`src/test/regress/sql/event_trigger.sql` must cover
`CREATE OR REPLACE MATERIALIZED VIEW`.** The full regression suite passes today
precisely because nothing exercises this combination.

---

## 2. Blocker: wrong command completion tag — *fixed, §11*

`ExecCreateTableAs()` hands off to `ExecRefreshMatView()` at
`src/backend/commands/createas.c:405` and lets it write the `QueryCompletion`.
The result is three different tags for what is nominally one command:

```
CREATE MATERIALIZED VIEW m2 AS SELECT 1 AS a;                          -> SELECT 1
CREATE OR REPLACE MATERIALIZED VIEW m2 AS SELECT 2 AS a;               -> REFRESH MATERIALIZED VIEW
CREATE OR REPLACE MATERIALIZED VIEW m2 AS SELECT 3 AS a WITH NO DATA;  -> REFRESH MATERIALIZED VIEW
CREATE OR REPLACE MATERIALIZED VIEW m2 AS SELECT 4 AS a WITH OLD DATA; -> CREATE MATERIALIZED VIEW
```

Reporting `REFRESH MATERIALIZED VIEW` for a statement the client sent as
`CREATE OR REPLACE MATERIALIZED VIEW` is a wire-protocol lie; drivers and
poolers that key off the tag will get it wrong. (The `WITH OLD DATA` case only
looks right by accident — nothing sets `qc` at all there, so it falls back to
`CreateCommandTag()`.)

The existing `SELECT n` tag for plain `CREATE MATERIALIZED VIEW` is
long-standing behavior and shouldn't change here, but the new paths need to
produce something consistent and deliberate. At minimum, pass a scratch
`QueryCompletion` to `ExecRefreshMatView()` and discard it, then set the tag
yourself.

Related: `address = ExecRefreshMatView(...)` at line 405 also overwrites the
address returned by `create_ctas_nodata()`. They happen to be the same relation
today, but the overwrite is gratuitous and obscures that.

---

## 3. Replacing a matview silently resets and rewrites its storage

> **Revised after reading the thread.** My original recommendation here — that
> unspecified clauses should preserve the existing access method, tablespace and
> reloptions — is **wrong**, and I withdraw it. Tom Lane ruled the opposite way
> on 2025-04-05, and the current code is the deliberate result of that feedback
> (v7/v8 changed *from* preserve *to* reset). See §10. What survives is the
> documentation gap and the stranded-index problem, neither of which the thread
> touches.

`create_ctas_replace()` unconditionally issues `AT_SetAccessMethod`,
`AT_SetTableSpace`, and `AT_ReplaceRelOptions`, filling in the *global defaults*
whenever the statement didn't name one (`createas.c:284-337`). The comment says
this is intentional — "the defaults apply as if they have not been specified at
all" — and it does mirror `CREATE OR REPLACE VIEW`'s treatment of reloptions.

The semantics are correct and settled. But they are **not documented at all**,
and they are more expensive and more surprising on a matview than on a view.

```sql
CREATE MATERIALIZED VIEW m7 WITH (autovacuum_enabled=false, fillfactor=70)
  TABLESPACE ts1 AS SELECT g AS a FROM generate_series(1,5) g;
--  reloptions                               | in_ts
--  {autovacuum_enabled=false,fillfactor=70} | t

CREATE OR REPLACE MATERIALIZED VIEW m7 AS
  SELECT g AS a FROM generate_series(1,99) g WITH OLD DATA;
--  reloptions | in_ts
--             | f
```

A user editing the query text of a matview, without mentioning storage at all,
gets their `autovacuum_enabled=false` dropped and their multi-terabyte matview
**physically relocated to the default tablespace**. For a view that costs
nothing; for a matview it is an unbounded amount of I/O nobody asked for.

It also leaves the relation internally inconsistent, because
`ALTER ... SET TABLESPACE` does not follow indexes:

```sql
CREATE MATERIALIZED VIEW m8 TABLESPACE ts1 AS SELECT g AS a FROM generate_series(1,3) g;
CREATE INDEX m8_idx ON m8(a) TABLESPACE ts1;
CREATE OR REPLACE MATERIALIZED VIEW m8 AS SELECT g AS a FROM generate_series(1,3) g;

--  relname | relkind |  tblspc
-- ---------+---------+-----------
--  m8      | m       | <default>     <- moved
--  m8_idx  | i       | ts1           <- left behind
```

What I'd still ask for, all of it compatible with the agreed semantics:

- **Document it.** `create_materialized_view.sgml` should state plainly that a
  bare `CREATE OR REPLACE MATERIALIZED VIEW` resets access method, tablespace,
  and storage parameters to their defaults, and that doing so can rewrite and
  relocate the entire matview. Right now a user has to read `createas.c` to find
  this out. Tom's contract argument is a good rationale and deserves to appear
  in the docs, not just the archives.
- **The stranded index is arguably a bug even under the contract.** Tom's rule
  is that C.O.R. produces the object definition you'd have gotten from plain
  `CREATE`. A plain `CREATE MATERIALIZED VIEW` has no indexes at all, so indexes
  are outside the contract — which means there is no principled reason for the
  replace to move the heap out from under them. Leaving a matview and its
  indexes in different tablespaces is a state the user cannot reach with any
  single command, and it silently doubles their tablespace footprint. Worth
  raising on-list; it may need `ATExecSetTableSpace`-style index handling, or an
  explicit decision that this is acceptable.
- The regression test only checks `pg_class.reltablespace` of the matview
  itself; it should check the indexes too, whatever the resolution.

---

## 4. Correctness: the existence check is done twice, and the first one is unlocked

`ExecCreateTableAs()` calls `CreateTableAsRelReplaceable()`
(`createas.c:385`), which resolves the name with a bare `get_relname_relid()`
and **no lock** (`createas.c:628`). The real, locked lookup happens later in
`create_ctas_nodata()` via `RangeVarGetAndCheckCreationNamespace(...,
AccessExclusiveLock, &matviewOid)` (`createas.c:221`).

Two windows follow from that:

- The matview is dropped concurrently between the two lookups. `matviewOid`
  comes back invalid, we silently fall into `create_ctas_internal()` and create
  a fresh matview — **including when `WITH OLD DATA` was specified**, which
  `ExecCreateTableAs()` is supposed to reject for a new matview
  (`createas.c:449`). That check is on the other branch, so it never fires. The
  user gets a matview marked populated with no rows and no error.
- The matview is created concurrently between the two lookups. We take the
  create path and fail with `relation "x" already exists` despite `OR REPLACE`.

Both are narrow, but they're avoidable: do the lookup once, under
`AccessExclusiveLock`, and branch on the result — which is how
`DefineVirtualRelation()` handles the same problem for views.

---

## 5. Code duplication

Three pieces of this patch are near-verbatim copies of existing code:

- **`checkMatviewColumns()`** (`matview.c:978`) vs. **`checkViewColumns()`**
  (`view.c:266`). These are the same function modulo the word "view" →
  "materialized view" in five error messages, and the copy carries over the
  `/* XXX msg not right ... */` comment verbatim. Please factor into one
  function parameterized by relkind (or by an error-message noun) rather than
  forking it.
- **`CreateTableAsRelReplaceable()`** (`createas.c:619`) vs.
  **`CreateTableAsRelExists()`** (`createas.c:571`). Identical except
  `ctas->if_not_exists` → `into->replace` and the trailing NOTICE. One function
  with a flag would do.
- The new `CreateMatViewStmt` grammar production (`gram.y:5089`) duplicates the
  existing one. That may be unavoidable given the `IF NOT EXISTS` interaction,
  but see below.

---

## 6. `IntoClause` now carries the same information twice

`gram.y:5100-5101`:

```c
$7->skipData = $10 == WITHDATA_NONE;
$7->data = $10;
```

`skipData` and `data` are redundant, and only the new `OR REPLACE` production
sets `data` at all. Every other producer of an `IntoClause` — plain
`CREATE MATERIALIZED VIEW` (`gram.y:5086`), `CREATE TABLE AS`
(`gram.y:5004,5018,5072`), `SELECT INTO` (`gram.y:5141`), `EXECUTE ... INTO`
(`gram.y:12954,12972`) — leaves `data` at its zero value, `WITHDATA_DEFAULT`.
So after `CREATE TABLE AS ... WITH NO DATA`, the node claims `data ==
WITHDATA_DEFAULT` while `skipData == true`. The field lies about the statement
in every path but one.

Nothing in this patch reads it incorrectly, but it is a trap for the next
person. Either replace `skipData` with the enum everywhere (my preference —
`WithDataOption` is a good abstraction and the mechanical churn is small), or
don't add the field and derive `WITH OLD DATA` some other way.

Minor, in the same area: `WITHDATA_DEFAULT` is a confusing name for "WITH DATA",
given it also means "clause omitted". `WITHDATA_YES` or `WITHDATA_DATA` reads
better against `WITHDATA_NONE` / `WITHDATA_OLD`.

---

## 7. Documentation

- The synopsis reads `CREATE [ OR REPLACE ] MATERIALIZED VIEW [ IF NOT EXISTS ]
  ...`, which implies the two are combinable. They are not — it's a hard syntax
  error from the grammar. The prose says so a few lines later, but the synopsis
  should show two forms, or at least not present the impossible one.
- Nothing documents what `OR REPLACE` *preserves* — the OID, owner, ACLs,
  comments, indexes, and dependent views. That's the main reason to use it over
  `DROP` + `CREATE`, and it should be stated.
- Nothing documents the storage-property reset described in §3.
- `WITH OLD DATA` should say explicitly that the retained rows are the output of
  the *old* query and may not match the new definition until a refresh, and that
  columns added by the replace are NULL-filled in the retained rows.
- "Replaces a materialized view if it already exists." — worth adding that the
  new query's output columns must match the old ones by name, type, typmod, and
  collation, and may only be added to at the end. That restriction is the first
  thing users will hit.

---

## 8. Test coverage

The new tests in `matview.sql` are good on the column-compatibility rules and
the `WITH OLD DATA` semantics — the ninth-column `t_bits` case and the domain
NOT NULL violation are nice catches. Gaps:

- **Event triggers** (§1) — a crash today.
- **Command tags** (§2) — nothing checks them.
- **Permissions.** Ownership *is* correctly enforced, via `ATSimplePermissions()`
  on the generated subcommands (verified: a non-owner with `CREATE` on the
  schema gets `ERROR: must be owner of materialized view mv`). But that's an
  incidental consequence of routing through `AlterTableInternal()`, not an
  explicit check — exactly the kind of thing that should be pinned by a test.
- **Index tablespace divergence** (§3).
- No isolation test for concurrent `CREATE OR REPLACE` / `DROP` / `REFRESH`
  against the same matview (§4).
- The new tests leave `mvtest_replace` and domain `mvtest_dom` behind. Harmless,
  and arguably useful for the `pg_upgrade` test, but it's a departure from the
  rest of the file — worth a word in the commit message if intentional.

Also, `-- Cannot use OR REPLACE with IF NOT EXISTS` has no `-- error` marker,
unlike the neighboring negative cases.

---

## 9. Smaller items

- `createas.c:68`: the prototype names the first parameter `tlist`; the
  definition at line 243 calls it `attrList`. The definition is right.
- `createas.c:631`: `if (!into->replace) ereport(ERROR, ...)` inside
  `CreateTableAsRelReplaceable()` is dead — the sole caller only enters when
  `into->replace` is true.
- `create_ctas_nodata()` now dispatches to the replace path, so its name and
  header comment no longer describe what it does. Either rename it or hoist the
  replace decision up into `ExecCreateTableAs()` (which would also fix §4).
- The replace path returns at `createas.c:407`, before the
  `JumbleQuery()` / `post_parse_analyze_hook` block at `createas.c:418-422`. So
  extensions hooking `post_parse_analyze` never see the CTAS query for a
  replace. I checked `pg_stat_statements` specifically and normalization still
  works (utility-statement jumbling covers it — `CREATE OR REPLACE MATERIALIZED
  VIEW m6 AS SELECT $1 AS a`, 2 calls), so there's no user-visible bug I can
  demonstrate. The asymmetry still looks unintentional.
- `parsenodes.h`: the patch deletes a blank line at the end of the file, which
  is unrelated to the feature. Drop that hunk.
- `tab-complete.in.c`: the completion arms are now paired
  `Matches(...) || Matches("CREATE", "OR", "REPLACE", ...)` five times over. If
  there's an existing idiom for optional `OR REPLACE` prefixes it'd read better;
  if not, this is acceptable, just verbose. `"MATERIALIZED VIEW"` is appended to
  the end of the `CREATE OR REPLACE` list rather than near `"VIEW"` — minor
  placement nit.
- No handling in `src/test/modules/test_ddl_deparse` — `matviews.sql` there
  covers `CREATE`/`REFRESH` only. Once §1 is resolved this will need attention.

---

## 10. Cross-check against the pgsql-hackers thread

Thread: <https://www.postgresql.org/message-id/flat/3c86a16f-4272-4df3-9959-70a9a7d88a71%40ewie.name>
(started 2024-07-02, last message Rafia Sabih 2026-07-23, still awaiting review).

**Already settled on-list — I was wrong:**

- **§3, storage-property reset.** Tom Lane, 2025-04-05:
  > "The contract for any form of C.O.R. is that it will either fail, or produce
  > exactly the same object definition that you would have gotten from plain
  > CREATE with no conflicting object. The v6 code is visibly not doing that for
  > properties such as tablespace --- if the command doesn't mention that, you
  > don't get the default tablespace, you get whatever the old object had."

  The current behavior is what he asked for. My "preserve the old values"
  suggestion is exactly the v6 behavior he rejected. Withdrawn.

- **`WITH OLD DATA` on a new matview.** Same message:
  > "BTW, I'm inclined to think that WITH OLD DATA ought to fail if the command
  > isn't replacing an existing matview. It seems inconsistent to silently
  > reinterpret it as WITH DATA [...]"

  Already implemented (`createas.c:449`). Note this makes the race in §4 a
  *correctness* problem, not just a tidiness one: losing the race silently
  re-enables the behavior Tom explicitly asked to be rejected.

- **`IF NOT EXISTS` deprecation.** Proposed as patch 0002, ruled a "nonstarter"
  by Tom, dropped by the author. Correctly absent from this commit.

**Already reported by others:**

- §4 (unlocked existence check / race) and the dead `if (!into->replace)` branch
  in §9 were both raised by Rafia Sabih on 2026-07-23 — the most recent message,
  and still open. My §4 adds the specific consequence that the `WITH OLD DATA`
  guard can be bypassed.
- Several §5/§6 points (the `checkMatviewColumns()` split, `WithDataOption`,
  `for_each_from`, the `create_ctas_replace()` extraction) came out of the
  2026-02-03 review round — i.e. this commit is already a response to them. The
  duplication I flag in §5 is what that refactoring left behind, so treat it as a
  follow-on suggestion rather than a new complaint.

**Not raised by anyone, including me until now:**

- **§1 (crash) and §2 (command tag) appear nowhere in the thread.** I searched it
  for event triggers, `ddl_command_end`, `pg_event_trigger_ddl_commands`, crashes,
  assertion failures, completion tags, `QueryCompletion`, and `RefreshMatViewByOid`
  — no hits. Two years of review, and neither has been looked at.
- §3's stranded-index consequence and the missing documentation of the reset
  semantics are likewise undiscussed. The thread argued about *what* the
  semantics should be and never came back to writing them down.

Worth noting for §2 that the fix is *implied* by Tom's own contract: plain
`CREATE MATERIALIZED VIEW` reports `SELECT n`, so under "produce exactly what
plain CREATE would" the replace must too. That argument is worth making on-list.

---

## 11. Tests and fixes (applied in the working tree)

Six files, +103/−11. Full suite green afterwards: regress **245/245**,
isolation **131/131**, `test_ddl_deparse` **22/22**.

### Test for §2 — `src/test/regress/sql/matview.sql`

Completion tags aren't visible under `pg_regress` because psql runs with `-q`.
`\set QUIET false` re-enables them, an idiom already used by `triggers.sql`,
`psql.sql`, and `for_portion_of.sql`. All four variants are covered.

Before the fix:

```
CREATE MATERIALIZED VIEW mvtest_tag AS ...           -> SELECT 3
CREATE OR REPLACE MATERIALIZED VIEW mvtest_tag AS ...-> REFRESH MATERIALIZED VIEW   <- wrong
  ... WITH NO DATA;                                  -> REFRESH MATERIALIZED VIEW   <- wrong
  ... WITH OLD DATA;                                 -> CREATE MATERIALIZED VIEW
```

After:

```
CREATE MATERIALIZED VIEW mvtest_tag AS ...           -> SELECT 3
CREATE OR REPLACE MATERIALIZED VIEW mvtest_tag AS ...-> SELECT 5
  ... WITH NO DATA;                                  -> CREATE MATERIALIZED VIEW
  ... WITH OLD DATA;                                 -> CREATE MATERIALIZED VIEW
```

The two `WITH ... DATA` forms now match plain
`CREATE MATERIALIZED VIEW ... WITH NO DATA`, which reports
`CREATE MATERIALIZED VIEW` because it runs no refresh at all.

### Test for §1 — `src/test/regress/sql/event_trigger.sql`

Added directly beneath the existing `-- View with column additions` case, under
the same `regress_event_trigger_report_end` trigger, so the matview path is
tested exactly where the view path already is. On the unfixed tree this test
takes the server down:

```
+CREATE OR REPLACE MATERIALIZED VIEW evttrig.one_matview AS
+  SELECT * FROM evttrig.two, evttrig.id;
+server closed the connection unexpectedly
```

### Fix for §2 — `src/backend/commands/createas.c`

The patch built a fake `RefreshMatViewStmt` and called `ExecRefreshMatView()`,
which hardcodes `is_create = false`. But master already grew
`RefreshMatViewByOid(..., bool is_create, ...)` for exactly this purpose —
`matview.c:388` picks `CMDTAG_SELECT` vs `CMDTAG_REFRESH_MATERIALIZED_VIEW` off
that flag, and the plain `CREATE MATERIALIZED VIEW` path at `createas.c:474`
already uses it. The replace path just needs to do the same:

```c
if (into->data == WITHDATA_DEFAULT)
    RefreshMatViewByOid(address.objectId, true, false, false,
                        pstate->p_sourcetext, qc);
else if (into->data == WITHDATA_NONE)
    RefreshMatViewByOid(address.objectId, true, true, false,
                        pstate->p_sourcetext, NULL);
/* For WITHDATA_OLD the existing contents are left untouched. */
```

`WITH NO DATA` passes `qc = NULL` so the tag falls back to `CreateCommandTag()`,
matching the plain path. This also drops the fake-statement hack and the
gratuitous overwrite of `address` noted in §2.

One thing to check on-list: `ExecRefreshMatView()` resolves the name through
`RangeVarCallbackMaintainsTable`, which permits the `MAINTAIN` privilege as well
as ownership. Entering by OID skips that. It is not a privilege loosening —
`ATSimplePermissions()` has already demanded full ownership by this point, which
is strictly stronger — but it is a behavior change worth stating rather than
letting a reviewer discover.

### Fix for §1 — `src/backend/tcop/utility.c`

Make the copied comment true rather than deleting it: wrap `T_CreateTableAsStmt`
the way `T_ViewStmt` is already wrapped, twelve cases further down.

```c
case T_CreateTableAsStmt:
    EventTriggerAlterTableStart(parsetree);
    address = ExecCreateTableAs(pstate, (CreateTableAsStmt *) parsetree,
                                params, queryEnv, qc);
    EventTriggerCollectSimpleCommand(address, secondaryObject, parsetree);
    commandCollected = true;
    EventTriggerAlterTableEnd();
    break;
```

This is safe for every other `CreateTableAsStmt` because
`EventTriggerAlterTableEnd()` discards the entry when no subcommands were
collected (`event_trigger.c:1862`), and `EventTriggerCollectSimpleCommand()` is
the same call the generic tail would have made. Verified: plain `CREATE TABLE AS`
and `SELECT INTO` produce unchanged event-trigger output, and no other expected
file moved.

Resulting event-trigger output mirrors the view case exactly — one notice for the
command, one for the stashed `ALTER TABLE`:

```
CREATE OR REPLACE MATERIALIZED VIEW evttrig.one_matview AS ...
NOTICE:  END: command_tag=CREATE MATERIALIZED VIEW type=materialized view identity=evttrig.one_matview
NOTICE:  END: command_tag=CREATE MATERIALIZED VIEW type=materialized view identity=evttrig.one_matview
```

An alternative worth considering: suppress the internal `ALTER TABLE` from
collection entirely, the way `ProcessUtilitySlow()` already inhibits collection
around `ExecRefreshMatView()` (`utility.c:1686-1705`). I chose consistency with
`CREATE OR REPLACE VIEW` instead, but this is a judgement call for the list.

---

## What I verified

| | |
|---|---|
| Build | clean, assert-enabled, no new warnings (before and after fixes) |
| `make -C src/test/regress check` | 245/245 on the commit; 245/245 after fixes |
| `make -C src/test/isolation check` | 131/131 after fixes |
| `make -C src/test/modules/test_ddl_deparse check` | 22/22 after fixes |
| New tests fail on unfixed tree | yes — crash in `event_trigger`, wrong tags in `matview` |
| Plain `CREATE TABLE AS` / `SELECT INTO` event-trigger output | unchanged by the `utility.c` fix |
| Crash (§1) | reproduced, core dumped, backtrace above |
| Command tags (§2) | reproduced, all four variants |
| Storage reset / index divergence (§3) | reproduced |
| Ownership enforcement | confirmed working |
| `CREATE OR REPLACE UNLOGGED MATERIALIZED VIEW` | correctly rejected (`analyze.c:3566`) |
| Replace with a dependent view / dependent matview | works |
| Replace targeting a table or a plain view | correctly rejected |
| Column alias list, `WITH DATA` / `WITH NO DATA` / `WITH OLD DATA` | behave as documented |
| Replace of an unpopulated matview with `WITH OLD DATA` | stays unpopulated, as expected |
| `pg_stat_statements` normalization | unaffected |
