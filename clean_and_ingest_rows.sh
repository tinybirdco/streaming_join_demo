#!/usr/bin/bash

tb --no-version-warning datasource ls --format json | jq -r '.datasources[].name' | while read -r name; do
  tb datasource truncate $name --yes
  echo "Truncating $name"
done

TOKEN=$(cat .tinyb | jq -r .token)

HOST=$(cat .tinyb | jq -r .host )

curl \
      -X POST "$HOST/v0/events?name=vehicle_data" \
      -H "Authorization: Bearer $TOKEN" \
      -d $'{"timestamp":"2022-10-27T11:43:02","vehicle_id":"8d1e1533-6071-4b10-9cda-b8429c1c7a67", "speed":91, "fuel_level_percentage": 85}'

sleep 3

curl \
      -X POST "$HOST/v0/events?name=gps_data" \
      -H "Authorization: Bearer $TOKEN" \
      -d $'{"timestamp":"2022-10-27T11:43:02","vehicle_id":"8d1e1533-6071-4b10-9cda-b8429c1c7a67", "latitude":40.4169866, "longitude":-3.7034816}'

sleep 5

curl \
      -X POST "$HOST/v0/events?name=gps_data" \
      -H "Authorization: Bearer $TOKEN" \
      -d $'{"timestamp":"2022-10-27T11:44:03","vehicle_id":"8d1e1533-6071-4b10-9cda-b8429c1c7a67", "latitude":40.4169867, "longitude":-3.7034818}'

sleep 3

curl \
      -X POST "$HOST/v0/events?name=vehicle_data" \
      -H "Authorization: Bearer $TOKEN" \
      -d $'{"timestamp":"2022-10-27T11:44:03","vehicle_id":"8d1e1533-6071-4b10-9cda-b8429c1c7a67", "speed":89, "fuel_level_percentage": 84}'
