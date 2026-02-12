#!/bin/bash

THIS=$(basename $0)
TMPFILE=$(mktemp /opt/hamclock-backend/cache/$THIS-XXXXX)

# URL and Paths
URL="https://services.swpc.noaa.gov/text/drap_global_frequencies.txt"
OUTPUT="/opt/hamclock-backend/htdocs/ham/HamClock/drap/stats.txt"
LAST_DATE_FILE="/opt/hamclock-backend/htdocs/ham/HamClock/drap/last_valid_date.txt"

# 1. Fetch the data into a variable to avoid multiple downloads
RAW_DATA=$(curl -s "$URL")

# 2. Extract the "Product Valid At" line
# Example line: # Product Valid At : 2026-02-03 23:01 UTC
CURRENT_VALID_DATE=$(echo "$RAW_DATA" | grep "Product Valid At" | cut -d':' -f2- | xargs)

# 3. Check if we've already processed this timestamp
if [ -f "$LAST_DATE_FILE" ]; then
    LAST_VALID_DATE=$(cat "$LAST_DATE_FILE")
    if [ "$CURRENT_VALID_DATE" == "$LAST_VALID_DATE" ]; then
        # Quietly exit if data hasn't changed
        exit 0
    fi
fi

# 4. Process the file using awk
EPOCH=$(date +%s)
NEW_ROW=$(
echo "$RAW_DATA" | awk -v now="$EPOCH" -F'|' '
NF > 1 {
    split($2, values, " ")
    for (i in values) {
        val = values[i]
        if (!initialized) {
            min = max = sum = val
            count = 1
            initialized = 1
            continue
        }
        if (val < min) min = val
        if (val > max) max = val
        sum += val
        count++
    }
}
END {
    if (count > 0) {
        printf "%s : %g %g %.5f\n", now, min, max, sum / count
    }
}')

# 5. Save the new timestamp
echo "$CURRENT_VALID_DATE" > "$LAST_DATE_FILE"

# 6. Save and trim the log
#
# if this is a fresh install, we won't have the history. It seems like
# hamclock doesn't like old timestamps so we can't keep a seed file in git.
# Instead what we'll do is take the last value and save it 440 times to mimic 
# what we see in CSI. It will be just a straight line but eventually it will fill in.
if [ -e "$OUTPUT" ]; then
    # last checked, CSI had 440 lines. Not sure how we maintains the file since the timestamps
    # are not uniformly spaced.
    tail -n 440 "$OUTPUT" > "$TMPFILE"
    echo "$NEW_ROW" >> "$TMPFILE"
else
    # if the file doesn't exist, go backwards every 5 minutes which is a rough
    # approximation of what we see in real data
    EPOCH_TIME=$(echo $NEW_ROW | cut -d " " -f 1)
    ROW_TAIL=$(echo $NEW_ROW | cut -d " " -f 2-)
    for i in {0..439}; do
        echo "$(($EPOCH_TIME - 5 * 60 * $i)) $ROW_TAIL" >> "$TMPFILE"
    done
    sort -V -o $TMPFILE $TMPFILE
fi

cp "$TMPFILE" "$OUTPUT"
rm -f "$TMPFILE"
