#!/bin/bash

# Get the year and month for a month ago
YEAR=$(date -d "last month" +%Y)
MONTH=$(date -d "last month" +%m)
TARGET_MONTH="${YEAR}${MONTH}"

OUTPUT="/opt/hamclock-backend/htdocs/ham/HamClock/solar-flux/solarflux-history.txt"

URL="https://www.spaceweather.gc.ca/solar_flux_data/daily_flux_values/fluxtable.txt"

curl -s "$URL" | awk -v m="$MONTH" -v y="$YEAR" -v target="$TARGET_MONTH" '
    # Skip headers
    /^[a-zA-Z]/ || /^-/ { next }

    {
        # Check if the row matches our target yyyyMM
        if (substr($1, 1, 6) == target) {
            sum += $5
            count++
        }
    }

    END {
        if (count > 0) {
            # Calculate fractional year: Year + (Month - 1) / 12
            frac_year = y + ((m - 1) / 12)
            avg_flux = sum / count

            # %.2f ensures exactly two decimal places for both values
            printf "%.2f %.2f\n", frac_year, avg_flux
        }
    }
' >> "$OUTPUT"
