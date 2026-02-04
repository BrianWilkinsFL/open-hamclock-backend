#!/bin/bash

# URL of the raw NOAA DRAP grid
URL="https://services.swpc.noaa.gov/text/drap_global_frequencies.txt"
OUTPUT="/opt/hamclock-backend/htdocs/ham/HamClock/drap/stats.txt"
mkdir -p "$(dirname "$OUTPUT")"

# Get current epoch time
EPOCH=$(date +%s)

# Process the file
curl -s "$URL" | awk -v now="$EPOCH" -F'|' '
# Only process lines that contain the pipe symbol "|"
NF > 1 {
    # The actual data is in the second "field" (everything after the |)
    split($2, values, " ")

    for (i in values) {
        val = values[i]

        # Initialize
        if (!initialized) {
            min = max = sum = val
            count = 1
            initialized = 1
            continue
        }

        # Compare and Sum
        if (val < min) min = val
        if (val > max) max = val
        sum += val
        count++
    }
}
END {
    if (count > 0) {
        # Format: Epoch : Min Max Mean
        # Using %g for min/max to keep them concise, and %.5f for mean
        printf "%s : %g %g %.5f\n", now, min, max, sum / count
    }
}' >> "$OUTPUT"

# Trim the file to keep the last 436 lines
TRIMMED_DATA=$(tail -n 436 "$OUTPUT")
echo "$TRIMMED_DATA" > "$OUTPUT"
