#!/bin/bash
for i in $(seq 1 "$1")
do
  echo $i
  echo "{\"fee\": \"$i\"}" | kcat -P -b 127.0.0.1:9094 -t baz_topic -H headerone=headeronevalue -H headertwo=headertwovalue -H headerone=headerthreevalue
done
