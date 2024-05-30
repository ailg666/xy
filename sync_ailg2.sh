#!/bin/bash
#container_name=$1
#config_dir=$2

rm -f /emby/config/*.sql
mount_paths=()
while IFS= read -r line; do
    mount_paths+=("$line")
done < /emby/config/mount_paths.txt
#IFS=' ' read -r -a mount_paths < /emby/config/mount_paths.txt
echo ${mount_paths[@]}

echo "正在转换数据库……"
db_path="/emby/config/data/library.db"
index=0
for path in "${mount_paths[@]}"; do
    output_file="/emby/config/MediaItems_$index.sql"
    > $output_file  # 清空或创建文件
    sqlite3 $db_path <<EOF
.mode insert
.output $output_file
SELECT * FROM MediaItems WHERE path LIKE '$path%';
EOF
    sed -i "s/table/MediaItems/g" $output_file
tables=("AncestorIds2" "ItemLinks2" "ItemPeople2" "MediaStreams2")
for table in ${tables[@]}; do
    output_file="/emby/config/${table}_$index.sql"
    > $output_file  # 清空或创建文件
    if sqlite3 $db_path ".tables $table" | grep "^$table$" > /dev/null; then
        sqlite3 $db_path <<EOF
.mode insert
.output $output_file
SELECT * FROM $table WHERE ItemId IN (SELECT Id FROM MediaItems WHERE path LIKE '$path%');
EOF
        sed -i "s/table/$table/g" $output_file
    else
        echo "Table $table does not exist in the database."
    fi
done
index=$((index+1))
done

#可以通过以下方法获取小雅实时媒体库id，以下library.db指不包含用户媒体库的数据库，需要先提前有这个文件才能用以下方法获取。
exclude_ids=$(sqlite3 ./library.db "SELECT ItemId FROM ItemExtradata;")
exclude_ids_pattern=$(echo $exclude_ids | sed 's/ /|/g')
ids=$(sqlite3 $db_path "SELECT ItemId FROM ItemExtradata" | grep -v -E "$exclude_ids_pattern")
#将ids字符串转换为数组
ids=(${ids})

exclude_ids=(113247 111388 113755 108733 77300 1425692 112823 113637 115892 112652 112908 112521 111752 394560 112395 740118 15569 118566 117147 1649163 1616971 394489 118322 1425690 589279 1316551 539213 114140 775355 949309 118860 118755 1613320)
IFS='|'
exclude_ids_pattern="^($(echo "${exclude_ids[*]}"))$"
ids=$(sqlite3 $db_path "SELECT ItemId FROM ItemExtradata" | grep -v -E "$exclude_ids_pattern")
echo ${ids[@]}
unset IFS

tables=("AncestorIds2" "ItemLinks2" "MediaStreams2" "MediaItems")
for id in $ids; do
    for table in ${tables[@]}; do
        output_file="/emby/config/${table}_$id.sql"
        > $output_file  # 清空或创建文件
        if sqlite3 $db_path ".tables $table" | grep "^$table$" > /dev/null; then
            if [ "$table" == "MediaItems" ]; then
                sqlite3 $db_path <<EOF
.mode insert
.output $output_file
SELECT * FROM $table WHERE Id = '$id';
EOF
            else
                sqlite3 $db_path <<EOF
.mode insert
.output $output_file
SELECT * FROM $table WHERE ItemId = '$id';
EOF
            fi
            sed -i "s/table/$table/g" $output_file
        else
            echo "Table $table does not exist in the database."
        fi
    done
done


temp_file="/tmp/temp.sql"
echo "PRAGMA foreign_keys = OFF;" > $temp_file
cat /emby/config/*.sql >> $temp_file
echo "PRAGMA foreign_keys = ON;" >> $temp_file
sed -E 's/replace\(//g;s/,'\''\\n'\'',char\(10\)\)//g' $temp_file > ${temp_file%.sql}_1.sql
temp_file="/tmp/temp_1.sql"
#mv $temp_file /emby/config/media_items_all.sql
bash -c "$(curl -sSLf https://xy.ggbond.org/xy/itrans_emby_sql.sh)" -s "${temp_file}" "/emby/config/media_items_all.sql"
chmod 777 /emby/config/*.sql
read -p 'check'