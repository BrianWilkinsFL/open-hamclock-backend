#!/bin/bash

# By SleepyNinja
THIS=$(basename $0)

# 1. Generate Year and Month for the URL
# %y = last 2 digits of year (e.g., 26)
# %m = 2 digit month (e.g., 02)
YY=$(date -u +%y)
MM=$(date -u +%m)

URL="https://wdc.kugi.kyoto-u.ac.jp/dst_realtime/presentmonth/dst${YY}${MM}.for.request"
TMP_FILE="$(mktemp "/opt/hamclock-backend/tmp/dst_data.XXXXX")"
OUTPUT="/opt/hamclock-backend/htdocs/ham/HamClock/dst/dst.txt"

# 1. Download the file
if ! curl -s --fail "$URL" -o "$TMP_FILE"; then
    EPOCH_TIME=$(date -u +%s)
    echo "$EPOCH_TIME Error: Download failed (possibly 404 Not Found). Exiting." >&2
    exit 1
fi

# 2. Parse, find the last valid entry, and save to dst.txt
NEW_ROW=$( awk '
/^DST/ {
    yy = substr($0, 4, 2);
    mm = substr($0, 6, 2);
    dd = substr($0, 9, 2);

    base_str = substr($0, 17, 4);
    gsub(/ /, "", base_str);
    base = base_str + 0;

    for (i = 0; i < 24; i++) {
        val_str = substr($0, 21 + (i * 4), 4);
        clean_val = val_str;
        gsub(/ /, "", clean_val);

        # Ignore empty strings and the 9999 filler
        if (clean_val != "" && clean_val !~ /99/) {
            actual_value = (base * 100) + clean_val;
            printf "20%s-%s-%sT%02d:00:00 %d\n", yy, mm, dd, i, actual_value;
        }
    }
}' $TMP_FILE | tail -n 1)

# 3. Trim the file to keep only the last 24 lines
# if this is a fresh install, we won't have the history. It seems like
# hamclock doesn't like old timestamps so we can't keep a seed file in git.
# Instead what we'll do is take the last value and save it 24 times to mimic 
# what we see in CSI. It will be just a straight line but eventually it will fill in.
if [ -e "$OUTPUT" ]; then
    cp "$OUTPUT" "$TMP_FILE"
    echo "$NEW_ROW" >> "$TMP_FILE"
    tail -n 24 "$TMP_FILE" > "$OUTPUT"
else
    # if the file doesn't exist, go backwards every 5 minutes which is a rough
    # approximation of what we see in real data
    TIME=$(echo $NEW_ROW | cut -d " " -f 1)
    EPOCH_TIME=$(date -ud "$TIME" +%s)
    ROW_TAIL=$(echo $NEW_ROW | cut -d " " -f 2-)
    rm -f $TMP_FILE
    for i in {0..23}; do
        echo "$(date -ud @$(($EPOCH_TIME - 5 * 60 * $i)) +%Y-%m-%dT%H:%M:%S) $ROW_TAIL" >> "$TMP_FILE"
    done
    sort -V -o $OUTPUT $TMP_FILE
fi

rm -f "$TMP_FILE"
