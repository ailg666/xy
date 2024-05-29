#!/bin/bash

target_sql=$2
source_sql=$1

exec 3>"${target_sql}"

while IFS= read -r line
do
    # 检查行是否包含特定的表名
    if [[ $line == *"AncestorIds2"* ]]; then
        echo $line | awk -F'[(),]' '{if ($3 < 10) {$2=$2+1000000} else {$2=$2+1000000;$3=$3+1000000};printf "%s(%d,%d,%d);\n", $1, $2, $3, $4}' >&3
    elif [[ $line == *"ItemLinks2"* ]]; then
        echo $line | awk -F'[(,)]' '{if ($4 >= $2+1) {$4=$4+1000000}; $2=$2+1000000; printf "%s(%d,%d,%d,%d);\n", $1, $2, $3, $4, $5}' >&3
    elif [[ $line == *"MediaStreams2"* ]]; then
        echo $line | awk -F'[(,)]' '{$2=$2+1000000; printf "%s(%d,%d,%s", $1, $2, $3, $4; for(i=5;i<NF;i++) printf ",%s", $i; printf ")%s\n",$NF}' >&3
    elif [[ $line == *"MediaItems"* ]]; then
        echo $line | awk -F'[(),]' '{if ($5 < 10) {$2=$2+1000000} else {$2=$2+1000000;$5=$5+1000000};printf "%s(%d,%s,%d,%d",$1, $2, $3, $4,$5;for(i=6;i<NF;i++) printf ",%s", $i; printf ")%s\n",$NF}' >&3
    elif [[ $line == *"ItemPeople2"* ]]; then
        echo $line | awk -F'[(),]' '{$2=$2+1000000; printf"%s(%d,%d,%s,%d,%d);\n", $1, $2, $3, $4,$5,$6}' >&3
    else
        echo $line >&3
    fi
done < "${source_sql}"

exec 3>&-

