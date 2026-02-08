#!/usr/bin/env bash
set -uo pipefail

# Get our directory locations in order
HERE="$(realpath -s "$(dirname "$0")")"
THIS="$(basename "$0")"

# the file with the list of paths to pull is the same as this script
SOURCE_FILE=$HERE/"${THIS%.*}".txt

# the root URL source and the root file location
REMOTE_HOST="http://clearskyinstitute.com"
OUT="/opt/hamclock-backend/htdocs"

# refresh the list of artifacts based on recent 404 errors:
grep ' 404 ' /var/log/lighttpd/access.log | \
awk -v Date="$(date -d'1 hour ago' +'%d/%b/%Y:%H:%M:%S')" '{
  if ($4" "$5 >= Date) {
    print $0
  }
}' | cut -d\"  -f2 | cut -d " " -f 2 | sort | uniq | \
while IFS= read -r url || [[ -n "$url" ]]; do
    # skip if it was calling a cgi script
    [[ "$url" == *".pl"* ]] || [[ "$url" == *".sh"* ]] && continue
    echo $url >> $SOURCE_FILE
done
sort -uo $SOURCE_FILE $SOURCE_FILE

# check if the current file exists and was pulled by this script or generate
# if not, remove from filelist and remove the md5 file
cat /dev/null > $SOURCE_FILE.tmp
while IFS= read -r line || [[ -n "$line" ]]; do
    KEEP_FILE=yes
    OUT_FILE=${OUT}${line}
    if [ -e $OUT_FILE -a -e $OUT_FILE.md5 ]; then
        LAST_MD5="$(cat $OUT_FILE.md5)"
        CURRENT_MD5="$(stat -c "%a %u %g %s %Y" $OUT_FILE | md5sum)"
        if [ "$LAST_MD5" != "$CURRENT_MD5" ]; then
            KEEP_FILE=no
        fi
    elif [ ! -e $OUT_FILE -a ! -e $OUT_FILE.md5 ]; then
        KEEP_FILE=yes
    elif [ ! -e $OUT_FILE -o ! -e $OUT_FILE.md5 ]; then
        KEEP_FILE=no
    fi
    if [ $KEEP_FILE == yes ]; then
        echo $line >> $SOURCE_FILE.tmp
    else
        rm -f $OUT_FILE.md5
    fi
done < $SOURCE_FILE
mv $SOURCE_FILE.tmp $SOURCE_FILE

# get the file
while IFS= read -r line || [[ -n "$line" ]]; do
    URL=${REMOTE_HOST}${line}
    OUT_FILE=${OUT}${line}
    curl -fsS --retry 3 --retry-delay 2 "$URL" -o "$OUT_FILE"
    RETVAL=$?
    if [ $RETVAL -ne 0 ]; then
        echo "Failed to download from $URL" >&2
    else
        stat -c "%a %u %g %s %Y" $OUT_FILE | md5sum > $OUT_FILE.md5
    fi
done < $SOURCE_FILE
