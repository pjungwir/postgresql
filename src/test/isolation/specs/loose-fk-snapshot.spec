# Loose foreign key RI trigger test
#
# "Loose" foreign keys are a trigger-based form of referential integrity
# that does not require a unique constraint on the referenced table.  This
# lets a non-temporal table reference a temporal one.  The referenced column
# may have "duplicates" (the same key in different periods), so a regular FK
# is impossible; instead two CONSTRAINT TRIGGERs enforce the constraint:
#   - a "ref" trigger on the child  (AFTER INSERT/UPDATE OF fk)
#   - an "inv" trigger on the parent (AFTER UPDATE OF pk/DELETE)
# Both lock the matching rows with SELECT ... FOR KEY SHARE, mirroring how
# built-in RI behaves.
#
# This test mirrors specs/fk-snapshot-2.spec, but the referenced table is a
# temporal table and the FK is a loose FK.  We want to see whether the
# trigger-based implementation exhibits the same (correct) behavior as the
# C-based RI under REPEATABLE READ, or whether it admits an isolation anomaly
# (a dangling reference) because PL/pgSQL queries run under the transaction's
# own MVCC snapshot rather than a fresh crosscheck snapshot.

setup
{
  -- The loose-FK helper functions (from billitate, commit b4292c8).
  CREATE OR REPLACE FUNCTION loose_fk_check_ref()
  RETURNS trigger LANGUAGE plpgsql AS $fn$
  DECLARE
    v_fk_column text := TG_ARGV[0];
    v_to_table  text := TG_ARGV[1];
    v_pk_column text := TG_ARGV[2];
    v_is_null   boolean;
    v_found     integer;
    v_fk_value  text;
  BEGIN
    EXECUTE format('SELECT ($1).%I IS NULL', v_fk_column)
      USING NEW INTO v_is_null;
    IF v_is_null THEN RETURN NULL; END IF;

    EXECUTE format(
      'SELECT 1 FROM %1$s t WHERE t.%2$I = ($1).%3$I FOR KEY SHARE OF t',
      v_to_table, v_pk_column, v_fk_column
    ) USING NEW INTO v_found;

    IF v_found IS NULL THEN
      v_fk_value := to_jsonb(NEW) ->> v_fk_column;
      RAISE foreign_key_violation USING
        MESSAGE = format(
          'insert or update on table "%s" violates loose foreign key constraint',
          TG_TABLE_NAME
        ),
        DETAIL = format(
          'Key (%s)=(%s) is not present in table "%s".',
          v_fk_column, v_fk_value, v_to_table
        );
    END IF;

    RETURN NULL;
  END;
  $fn$;

  CREATE OR REPLACE FUNCTION loose_fk_check_inv()
  RETURNS trigger LANGUAGE plpgsql AS $fn$
  DECLARE
    v_from_table text := TG_ARGV[0];
    v_fk_column  text := TG_ARGV[1];
    v_pk_column  text := TG_ARGV[2];
    v_unchanged  boolean;
    v_is_null    boolean;
    v_found      integer;
    v_pk_value   text;
  BEGIN
    IF TG_OP = 'UPDATE' THEN
      EXECUTE format(
        'SELECT ($1).%1$I IS NOT DISTINCT FROM ($2).%1$I',
        v_pk_column
      ) USING OLD, NEW INTO v_unchanged;
      IF v_unchanged THEN RETURN NULL; END IF;
    END IF;

    EXECUTE format('SELECT ($1).%I IS NULL', v_pk_column)
      USING OLD INTO v_is_null;
    IF v_is_null THEN RETURN NULL; END IF;

    EXECUTE format(
      'SELECT 1 FROM %1$s f WHERE f.%2$I = ($1).%3$I FOR KEY SHARE OF f',
      v_from_table, v_fk_column, v_pk_column
    ) USING OLD INTO v_found;

    IF v_found IS NOT NULL THEN
      v_pk_value := to_jsonb(OLD) ->> v_pk_column;
      RAISE foreign_key_violation USING
        MESSAGE = format(
          'update or delete on table "%s" violates loose foreign key constraint on table "%s"',
          TG_TABLE_NAME, v_from_table
        ),
        DETAIL = format(
          'Key (%s)=(%s) is still referenced from table "%s".',
          v_pk_column, v_pk_value, v_from_table
        );
    END IF;

    RETURN NULL;
  END;
  $fn$;
}

setup
{
  -- btree_gist supplies the GiST opclass for the integer part of the
  -- temporal primary key.
  CREATE EXTENSION IF NOT EXISTS btree_gist;

  -- A temporal "parent" table.  parent_id is not unique on its own (it is
  -- only unique together with the period), so a regular FK is impossible.
  CREATE TABLE parent (
    parent_id integer NOT NULL,
    valid_at  daterange NOT NULL,
    PRIMARY KEY (parent_id, valid_at WITHOUT OVERLAPS)
  );
  -- A non-temporal "child" table that references parent via a loose FK.
  CREATE TABLE child (
    child_id  integer NOT NULL PRIMARY KEY,
    parent_id integer
  );
  INSERT INTO parent VALUES (1, daterange('2020-01-01', '2030-01-01'));

  -- ref trigger on the child side.
  CREATE CONSTRAINT TRIGGER loose_fk_ref
    AFTER INSERT OR UPDATE OF parent_id ON child
    FROM parent
    NOT DEFERRABLE INITIALLY IMMEDIATE
    FOR EACH ROW
    EXECUTE PROCEDURE loose_fk_check_ref('parent_id', 'parent', 'parent_id');

  -- inv trigger on the parent side.
  CREATE CONSTRAINT TRIGGER loose_fk_inv
    AFTER UPDATE OF parent_id OR DELETE ON parent
    FROM child
    NOT DEFERRABLE INITIALLY IMMEDIATE
    FOR EACH ROW
    EXECUTE PROCEDURE loose_fk_check_inv('child', 'parent_id', 'parent_id');
}

teardown { DROP TABLE parent, child; }

session s1
step s1rc	{ BEGIN ISOLATION LEVEL READ COMMITTED; }
step s1rr	{ BEGIN ISOLATION LEVEL REPEATABLE READ; }
step s1ser	{ BEGIN ISOLATION LEVEL SERIALIZABLE; }
step s1del	{ DELETE FROM parent WHERE parent_id = 1; }
step s1c	{ COMMIT; }

session s2
step s2rc	{ BEGIN ISOLATION LEVEL READ COMMITTED; }
step s2rr	{ BEGIN ISOLATION LEVEL REPEATABLE READ; }
step s2ser	{ BEGIN ISOLATION LEVEL SERIALIZABLE; }
step s2ins	{ INSERT INTO child VALUES (1, 1); }
step s2c	{ COMMIT; }

# Under REPEATABLE READ.
# The interesting case: child INSERT goes first, then parent is deleted.
# If the loose FK is correct, the DELETE must block on the child's KEY SHARE
# lock and then fail (the row is still referenced).
permutation s1rr s2rr s2ins s1del s2c s1c
# The reverse order: parent DELETE first, then child INSERT.
permutation s1rr s2rr s1del s2ins s1c s2c

# The same scenarios under READ COMMITTED.
permutation s1rc s2rc s2ins s1del s2c s1c
permutation s1rc s2rc s1del s2ins s1c s2c

# The same scenarios under SERIALIZABLE.
permutation s1ser s2ser s2ins s1del s2c s1c
permutation s1ser s2ser s1del s2ins s1c s2c
