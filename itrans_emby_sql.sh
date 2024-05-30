#!/bin/bash

target_sql=$2
source_sql=$1

exec 3>"${target_sql}"

while IFS= read -r line
do
    if [[ $line == *"AncestorIds2"* ]]; then
        echo $line | awk -F'VALUES' '{match($2, /\((.*)\)/, a); split(a[1],b,","); if (b[2] < 10) {b[1]=b[1]+1000000} else {b[1]=b[1]+1000000; b[2]=b[2]+1000000}; printf "%sVALUES(%d,%d,%d);\n", $1, b[1], b[2], b[3]}' >&3
    elif [[ $line == *"ItemLinks2"* ]]; then
        echo $line | awk -F'VALUES' '{match($2, /\((.*)\)/, a); split(a[1],b,","); if (b[3] >= b[1]+1) {b[3]=b[3]+1000000}; b[1]=b[1]+1000000; printf "%sVALUES(%d,%d,%d,%d);\n", $1, b[1], b[2], b[3], b[4]}' >&3
    elif [[ $line == *"MediaStreams2"* ]]; then
        echo $line | awk -F'VALUES' '{
            match($2, /\((.*)\)/, a);
            split(a[1],b,",");
            if (b[1] != "NULL") b[1]=b[1]+1000000;
            fmt = ("%d,%d,%d,%s,%s,%s,%s,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%f,%f,%f,%s,%d,%d,%d,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%d,%s,%d,%d,%d");
            split(fmt, f, ",");
            printf "%sVALUES(", $1;
            for(i=1;i<length(b);i++) {
                if (b[i] != "NULL" && f[i] ~ /%d/) {
                    printf f[i] ",", b[i];
                } else {
                    printf "%s,", b[i];
                }
            }
            printf f[length(b)] ");\n", b[length(b)]
        }' >&3
    elif [[ $line == *"MediaItems"* ]]; then
        echo $line | awk -F'VALUES' '{
            match($2, /\((.*)\)/, a);
            split(a[1],b,",");
            if (b[4] > 10) b[4]=b[4]+1000000;
            b[1]=b[1]+1000000;
            fmt = ("%d,%s,%d,%d,%s,%d,%d,%d,%d,%d,%d,%f,%s,%d,%d,%s,%s,%s,%d,%d,%d,%s,%d,%d,%d,%d,%d,%s,%s,%d,%d,%d,%s,%d,%d,%f,%s,%s,%d,%s,%s,%d,%d,%s,%s,%s,%s,%d,%d,%s,%s,%d,%d,%d,%d,%s,%d,%d,%d,%d,%d,%d,%d,%s,%s,%d");
            split(fmt, f, ",");
            printf "%sVALUES(", $1;
            for(i=1;i<length(b);i++) {
                if (b[i] != "NULL" && f[i] ~ /%d/) {
                    printf f[i] ",", b[i];
                } else {
                    printf "%s,", b[i];
                }
            }
            if (b[length(b)] != "NULL" && f[length(b)] ~ /%d/) {
                printf f[length(b)] ");\n", b[length(b)];
            } else {
                printf "%s);\n", b[length(b)];
            }
        }' >&3
    elif [[ $line == *"ItemPeople2"* ]]; then
        echo $line | awk -F'VALUES' '{match($2, /\((.*)\)/, a); split(a[1],b,","); b[1]=b[1]+1000000; printf "%sVALUES(%d,%d,%s,%d,%d);\n", $1,b[1],b[2],b[3],b[4],b[5]}' >&3
    else
        echo $line >&3
    fi
done < "${source_sql}"

exec 3>&-