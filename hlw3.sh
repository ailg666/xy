#!/bin/bash
USER_URL="http://192.168.0.105/Users?api_key=e825ed6f7f8f44ffa0563cddaddce14d"  
response=$(curl -s "$USER_URL")
read -r name <<< "$(echo "$response" | jq -r ".[0].Name")"  
read -r id <<< "$(echo "$response" | jq -r ".[0].Id")"
read -r policy <<< "$(echo "$response" | jq -r ".[0].Policy | to_entries | from_entries | tojson")"
USER_URL_2="${EMBY_URL}/Users/$id/Policy?api_key=e825ed6f7f8f44ffa0563cddaddce14d"
curl -i -H "Content-Type: application/json" -X POST -d "$policy" "$USER_URL_2"