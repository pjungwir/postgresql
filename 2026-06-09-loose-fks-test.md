I want you to test my implementation of "loose" foreign keys under `REPEATABLE READ`.

Loose foreign keys are a trigger-based solution that doesn't require a unique constraint on the referenced table.
They are helpful to link a non-temporal table to a temporal one.
Under `~/src/billitate/site` see commit `b4292c8ff0445bf4c2ecb05864a9a0d64c73c9ed`.

You are in the postgres repo on the `master` branch (for `19devel`).
First do a build & install to `~/local` (using the existing `configure` settings)
and make a new cluster at `~/pgdata`. Start it on some port.

I want you to add a new isolation test (in `src/test/isolation`).
It should set up two tables: one temporal and one not.
It should create a loose foreign key from the non-temporal table to the temporal one.
Then under `REPEATABLE READ`, see if it exhibits any isolation anomalies.
See the tests' README for how to run individual tests against your running cluster.
In particular, test the same scenario as `specs/fk-snapshot-2.spec`.
Just test that for now. Perhaps we'll add more scenarios later.

