#!/bin/bash

# By SleepyNinja
THIS=$(basename $0)

# Define JSON URL and Output Path
URL="https://services.swpc.noaa.gov/json/ovation_aurora_latest.json"
OUT="/opt/hamclock-backend/htdocs/ham/HamClock/aurora/aurora.txt"

# 1. Fetch the JSON data and find the MAX coordinate
MAX_VALUE=$(curl -s "$URL" | jq '.coordinates | map(.[2]) | max')

# 2. Get the current UNIX epoch time
EPOCH_TIME=$(date +%s)

# if this is a fresh install, we won't have the history. It seems like
# hamclock doesn't like old timestamps so we can't keep a seed file in git.
# Instead what we'll do is take the last value and save it 48 times to meet
# the hamclock requirement of 48 data points. It will be just a straight line
# but eventually it will fill in.
if [ -e "$OUT" ]; then
    # 3. Append the new data to the file
    echo "$EPOCH_TIME $MAX_VALUE" >> "$OUT"

    # 4. Trim the file to keep only the last 48 lines
    # This keeps the file size constant by slicing off the oldest entry
    TRIMMED_DATA=$(tail -n 48 "$OUT")
    echo "$TRIMMED_DATA" > "$OUT"

else
    TMPFILE=$(mktemp /opt/hamclock-backend/cache/$THIS-XXXXX)
    # if the file doesn't exist, go backwards for 48 samples every
    # 30 minutes
    for i in {0..47}; do
        echo "$(($EPOCH_TIME - 30 * 60 * $i)) $MAX_VALUE" >> "$TMPFILE"
    done
    # needs to be increasing
    sort -V -o $OUT $TMPFILE
    rm -f $TMPFILE
fi
