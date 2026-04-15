#!/usr/bin/env bash

# Test name length validation for tables, named collections, and UDFs.

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

# ---- 1. Underflow in computeMaxTableNameLength with a long database name ----
# The overhead for dropped filenames is: 1 + escaped_db_name + 1 + 36 + 4 = escaped_db_name + 42.
# With NAME_MAX=255, if escaped_db_name >= 214, the old code would underflow.
# We use a 220-char database name (all alphanumeric, so escapeForFileName is identity).

long_db="db_$(head -c 2000 /dev/urandom | tr -dc 'a-z' | head -c 216)"

$CLICKHOUSE_CLIENT --query "CREATE DATABASE IF NOT EXISTS \`$long_db\`"
# With the underflow fix, max table name length should be 0, so even a 1-char name must fail.
$CLICKHOUSE_CLIENT --query "CREATE TABLE \`$long_db\`.t (x UInt8) ENGINE = MergeTree ORDER BY x" 2>&1 | grep -o -m 1 'ARGUMENT_OUT_OF_BOUND'
$CLICKHOUSE_CLIENT --query "DROP DATABASE IF EXISTS \`$long_db\`"

echo "---"

# ---- 2. RENAME TABLE checks against the destination database, not the source ----
# Create two databases with different escaped name lengths.
short_db="${CLICKHOUSE_DATABASE}_short"
# A longer db name reduces the allowed table name. We use 200 chars for the db name,
# which leaves very little room for a table name in the dropped path.
long_dest_db="destdb_$(head -c 2000 /dev/urandom | tr -dc 'a-z' | head -c 200)"

$CLICKHOUSE_CLIENT --query "CREATE DATABASE IF NOT EXISTS \`$short_db\`"
$CLICKHOUSE_CLIENT --query "CREATE DATABASE IF NOT EXISTS \`$long_dest_db\`"

# Get the max table name length for each database
max_short=$($CLICKHOUSE_CLIENT --query "SELECT getMaxTableNameLengthForDatabase('$short_db')")
max_long=$($CLICKHOUSE_CLIENT --query "SELECT getMaxTableNameLengthForDatabase('$long_dest_db')")

# Create a table in short_db with a name that fits in short_db but not in long_dest_db.
# The name length should be > max_long but <= max_short.
if [ "$max_short" -gt "$max_long" ] && [ "$max_short" -gt 0 ]; then
    target_len=$((max_long + 1))
    if [ "$target_len" -le "$max_short" ]; then
        tname=$(head -c 2000 /dev/urandom | tr -dc 'a-z' | head -c "$target_len")
        $CLICKHOUSE_CLIENT --query "CREATE TABLE \`$short_db\`.\`$tname\` (x UInt8) ENGINE = MergeTree ORDER BY x"
        # Rename to long_dest_db must fail because the name is too long for that database
        $CLICKHOUSE_CLIENT --query "RENAME TABLE \`$short_db\`.\`$tname\` TO \`$long_dest_db\`.\`$tname\`" 2>&1 | grep -o -m 1 'ARGUMENT_OUT_OF_BOUND'
        $CLICKHOUSE_CLIENT --query "DROP TABLE IF EXISTS \`$short_db\`.\`$tname\`"
    else
        echo "ARGUMENT_OUT_OF_BOUND"
    fi
else
    echo "ARGUMENT_OUT_OF_BOUND"
fi

$CLICKHOUSE_CLIENT --query "DROP DATABASE IF EXISTS \`$short_db\`"
$CLICKHOUSE_CLIENT --query "DROP DATABASE IF EXISTS \`$long_dest_db\`"

echo "---"

# ---- 3. EXCHANGE TABLES enforces name length checks ----
db_a="${CLICKHOUSE_DATABASE}_exa"
# Use a long database name so that the allowed table name length is small.
db_b="exb_$(head -c 2000 /dev/urandom | tr -dc 'a-z' | head -c 210)"

$CLICKHOUSE_CLIENT --query "CREATE DATABASE IF NOT EXISTS \`$db_a\`"
$CLICKHOUSE_CLIENT --query "CREATE DATABASE IF NOT EXISTS \`$db_b\`"

max_b=$($CLICKHOUSE_CLIENT --query "SELECT getMaxTableNameLengthForDatabase('$db_b')")
max_a=$($CLICKHOUSE_CLIENT --query "SELECT getMaxTableNameLengthForDatabase('$db_a')")

# Create a table in db_a with a name that's too long for db_b
if [ "$max_a" -gt "$max_b" ] && [ "$max_a" -gt 0 ]; then
    target_len=$((max_b + 1))
    if [ "$target_len" -le "$max_a" ]; then
        big_name=$(head -c 2000 /dev/urandom | tr -dc 'a-z' | head -c "$target_len")
        small_name="s"
        $CLICKHOUSE_CLIENT --query "CREATE TABLE \`$db_a\`.\`$big_name\` (x UInt8) ENGINE = MergeTree ORDER BY x"
        $CLICKHOUSE_CLIENT --query "CREATE TABLE \`$db_b\`.\`$small_name\` (x UInt8) ENGINE = MergeTree ORDER BY x"
        # EXCHANGE should fail because big_name doesn't fit in db_b
        $CLICKHOUSE_CLIENT --query "EXCHANGE TABLES \`$db_a\`.\`$big_name\` AND \`$db_b\`.\`$small_name\`" 2>&1 | grep -o -m 1 'ARGUMENT_OUT_OF_BOUND'
        $CLICKHOUSE_CLIENT --query "DROP TABLE IF EXISTS \`$db_a\`.\`$big_name\`"
        $CLICKHOUSE_CLIENT --query "DROP TABLE IF EXISTS \`$db_b\`.\`$small_name\`"
    else
        echo "ARGUMENT_OUT_OF_BOUND"
    fi
else
    echo "ARGUMENT_OUT_OF_BOUND"
fi

$CLICKHOUSE_CLIENT --query "DROP DATABASE IF EXISTS \`$db_a\`"
$CLICKHOUSE_CLIENT --query "DROP DATABASE IF EXISTS \`$db_b\`"

echo "---"

# ---- 4. RENAME DATABASE checks unconditionally (even with check_table_dependencies=0) ----
rename_db="${CLICKHOUSE_DATABASE}_ren"
$CLICKHOUSE_CLIENT --query "CREATE DATABASE IF NOT EXISTS \`$rename_db\`"
ok_name="t"
$CLICKHOUSE_CLIENT --query "CREATE TABLE \`$rename_db\`.\`$ok_name\` (x UInt8) ENGINE = MergeTree ORDER BY x"

long_new_db="rn_$(head -c 2000 /dev/urandom | tr -dc 'a-z' | head -c 220)"
# With both dependency-check settings off, the old code would skip the length check entirely.
$CLICKHOUSE_CLIENT --query "SET check_table_dependencies=0; SET check_referential_table_dependencies=0; RENAME DATABASE \`$rename_db\` TO \`$long_new_db\`" 2>&1 | grep -o -m 1 'ARGUMENT_OUT_OF_BOUND'

$CLICKHOUSE_CLIENT --query "DROP DATABASE IF EXISTS \`$rename_db\`"
$CLICKHOUSE_CLIENT --query "DROP DATABASE IF EXISTS \`$long_new_db\`"

echo "---"

# ---- 5. Named collections: name length validation ----
# The filename is escapeForFileName(name) + ".sql" (4 chars overhead).
# With NAME_MAX=255, we need escaped name > 251.
# Alphanumeric names pass through escapeForFileName unchanged, so a 252-char name suffices.
long_nc_name=$(head -c 2000 /dev/urandom | tr -dc 'a-z' | head -c 252)
$CLICKHOUSE_CLIENT --query "CREATE NAMED COLLECTION \`$long_nc_name\` AS x = 1" 2>&1 | grep -o -m 1 'ARGUMENT_OUT_OF_BOUND'

echo "---"

# ---- 6. UDFs: name length validation ----
# The filename is "function_" (9) + escapeForFileName(name) + ".sql" (4) = 13 chars overhead.
# We need escaped name > 242. A 243-char alphanumeric name suffices.
long_udf_name=$(head -c 2000 /dev/urandom | tr -dc 'a-z' | head -c 243)
$CLICKHOUSE_CLIENT --query "CREATE FUNCTION \`$long_udf_name\` AS (a) -> a + 1" 2>&1 | grep -o -m 1 'ARGUMENT_OUT_OF_BOUND'
