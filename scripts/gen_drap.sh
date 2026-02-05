#!/bin/bash

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
}' >> "$OUTPUT"

# 5. Save the new timestamp and trim the log
echo "$CURRENT_VALID_DATE" > "$LAST_DATE_FILE"
TRIMMED_DATA=$(tail -n 424 "$OUTPUT")
echo "$TRIMMED_DATA" > "$OUTPUT"