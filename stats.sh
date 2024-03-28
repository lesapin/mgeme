#!/bin/bash

# Read .stat files output by ServerMon plugin. Parse them into a
# gnuplot .dat file. Use gnuplot to create statistics of server activity.

args=("$@")
title=${args[0]}
filename=${title// /_}

LOGS=`ls *.stats`
DATFILE="${filename}.dat"
IMGFILE="${filename}.png"
foldername=`date +%b%g`

IFS=$'\n'

mkdir -p $foldername

# print .dat header
printf "# gnuplot datfile - %s\n" $title > $DATFILE
printf "# DATE\tMANHOURS\tACTIVEHOURS\tMAXCLIENTS\tUNIQUECLIENTS\tCONNECTIONS\n" >> $DATFILE

nLogs=0

# Parse log files
for log in $LOGS;
do
	nLogs=$((nLogs+1))
	
	# Date is used as x-axis key
	printf "${log:5:4}\t" >> $DATFILE

	# Parse all lines except individual player activity
	while IFS=' ' read -ra line
	do
		if [[ "${line[0]}" != PLAYER ]]; then
			printf "${line[1]}\t" >> $DATFILE
		fi
	done < $log

	printf '\n' >> $DATFILE
done

# Plot
gnuplot <<- EOF
set title "$title" tc rgb 0xffffff
set tics font ",9"
set key outside tc rgb 0xffffff
set border lc rgb 0xffffff

set xlabel "Date" tc rgb 0xffffff
set xdata time
set timefmt "%m%d"
set xtics format "%d." time

set ylabel "Man-hours\n[h]" tc rgb 0xffffff
set ytics nomirror tc "yellow"

set y2label "Unique Clients" tc rgb 0xffffff
set y2range [0 : 100]
set y2tics nomirror tc rgb 0xb7f8f1 0,5

set term png size 1200,600 transparent truecolor
set output "$IMGFILE"

plot "$DATFILE" u 1:(column(2)/60/60) t 'Man-hours' w lines lc "yellow", \
     "$DATFILE" u 1:5 axes x1y2 t 'Unique Clients' w boxes lc rgb 0xb7f8f1
EOF
