#!/bin/bash

args=("$@")
title=${args[0]}
filename=${title// /_}
foldername=`date +%b%g`
nLogs=0

IFS=$'\n'

LOGS=`ls *.stats`
DATFILE="server.dat"
IMGFILE="${filename}.png"

printf "# gnuplot datfile - %s\n" $title > $DATFILE
printf "# DATE\tMANHOURS\tACTIVEHOURS\tMAXCLIENTS\tUNIQUECLIENTS\tCONNECTIONS\n" >> $DATFILE

mkdir $foldername

for log in $LOGS;
do
	nLogs=$((nLogs+1))

	printf "${log:5:4}\t" >> $DATFILE

	while IFS=' ' read -ra line
	do
		if [[ "${line[0]}" != PLAYER ]]; then
			printf "${line[1]}\t" >> $DATFILE
		fi
	done < $log

	printf '\n' >> $DATFILE
done

