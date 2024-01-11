#!/bin/bash

# at the beginning of the month, select all logs that are above the size threshold of an "empty" file 
# and save them in an archive with their names simplified to l%day-of-month%hour-of-day.log

if [ $# -lt 1 ]; then
    echo "usage: $0 --min-filesize [kilobytes]"
elif [ $# -eq 2 ]; then
    cd "$(dirname "$0")"
    if [ $1 = "--min-filesize" ]; then
        FLDR=$(date -d "$(date) 1 month ago" +%G%b)
        if ! [ -d $FLDR ]; then
            mkdir $FLDR
        fi
        for f in $(du ./*.log --apparent-size -t $2K | cut -d '	' -f 2); do
            mv "$f" "$FLDR/$(date -r $f +l%d%H.log)"
        done
        tar -cf "$FLDR.tar" "$FLDR"
        gzip "$FLDR.tar"
        # cleanup
        rm -rf "$FLDR"
        rm "*.log"
    else
        echo "bad argument"
    fi
else
    echo "too many arguments"
fi

