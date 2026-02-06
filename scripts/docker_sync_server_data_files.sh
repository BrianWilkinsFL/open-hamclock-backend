#!/bin/bash

# --- Configuration ---
# Ensure this path is correct for your Docker volume
LOCAL_ROOT="/opt/hamclock-backend/htdocs/ham/HamClock"
REMOTE_URL="http://clearskyinstitute.com/ham/HamClock"

# Your specific list with the leading slashes
FILES=(
    "cities2.txt"
    "version.pl"
    "/Bz/Bz.txt"
    "/Bz/swpc-Bz.txt"
    "/NOAASpaceWX/noaaswx.txt"
    "/ONTA/onta.txt"
    "/aurora/aurora.txt"
    "/contests/contests311.txt"
    "/drap/DRAP-LL.txt"
    "/drap/DRAP-NOAA.txt"
    "/drap/last_valid_date.txt"
    "/drap/stats.txt"
    "/dst/dst.txt"
    "/dxpeds/dxpeditions.txt"
    "/esats.subset.txt"
    "/esats.txt"
    "/geomag/kindex.txt"
    "/solar-flux/solarflux-99.txt"
    "/solar-flux/solarflux-history.txt"
    "/solar-flux/solarflux.txt"
    "/solar-wind/swind-24hr.txt"
    "/solar-wind/swind.txt"
    "/ssn/ssn-31.txt"
    "/ssn/ssn-history.txt"
    "/ssn/ssn.txt"
    "/worldwx/wx.txt"
    "/xray/xray-web.txt"
    "/xray/xray.txt"
)

# Create and move to local root
mkdir -p "$LOCAL_ROOT"
cd "$LOCAL_ROOT" || exit

echo "Starting HamClock data file sync with server..."
echo "Server: $REMOTE_URL"

for file in "${FILES[@]}"; do
    # 1. Remove the leading slash so 'mkdir' creates it inside LOCAL_ROOT
    # Example: /Bz/Bz.txt becomes Bz/Bz.txt
    REL_PATH="${file#/}"

    # 2. Extract the directory name (e.g., "Bz")
    DIR_NAME=$(dirname "$REL_PATH")

    # 3. Create the subdirectory locally if it doesn't exist
    if [ "$DIR_NAME" != "." ]; then
        mkdir -p "$DIR_NAME"
		chown -R www-data:www-data "$DIR_NAME"
    fi

    echo "Downloading: $REL_PATH"

    # 4. Download
    # -sSL: Silent, show errors, follow redirects
    # -f: Fail on server errors (don't save 404 pages)
    # -z: Only download if remote is newer than local
    curl -sSLf -z "$REL_PATH" -o "$REL_PATH" "${REMOTE_URL}/${REL_PATH}"
    
	# Change ownership of data file to www-data
    chown www-data:www-data "$REL_PATH" 

    # Check for success
    if [ $? -ne 0 ]; then
        echo "  [!] Skip/Error: Could not fetch $REL_PATH"
    fi
done

echo "Done! HamClock server data files synced to: $LOCAL_ROOT"