# Streaming join demo

## The issue

Let's assume we have two streams of data that are sent independently —to different Kafka topics, or different Data Sources via Events API or whatever:

GPS position:

```json
{
  "timestamp": "2022-10-27T11:43:02",
  "vehicle_id": "8d1e1533-6071-4b10-9cda-b8429c1c7a67",
  "latitude": 40.4169866,
  "longitude": -3.7034816
}

{
  "timestamp": "2022-10-27T11:44:03",
  "vehicle_id": "8d1e1533-6071-4b10-9cda-b8429c1c7a67",
  "latitude": 40.4169867,
  "longitude": -3.7034818
}
```

and Vehicle data:

```json
{
  "timestamp": "2022-10-27T11:43:02",
  "vehicle_id": "8d1e1533-6071-4b10-9cda-b8429c1c7a67",
  "speed": 91,
  "fuel_level_percentage": 85
}

{
  "timestamp": "2022-10-27T11:44:03",
  "vehicle_id": "8d1e1533-6071-4b10-9cda-b8429c1c7a67",
  "speed": 89,
  "fuel_level_percentage": 84
}
```

Sometimes __joining them at query time__, that is, in the pipe whose output is an API Endpoint, is perfectly fine, and we recommend starting there and move to storing the joined data into a different Data Source only when neccessary.

But it is true that sometimes, due to performance needs, we want them joined using _timestamp_ and _vehicle_id_ in another Data Source:

| timestamp | vehicle_id | latitude | longitude | speed | fuel_level_percentage |
| :-| :- | -: | -: | -: | -: |
| 2022-10-27T11:43:02 | 8d1e1533-6071-4b10-9cda-b8429c1c7a67 | 40.4169866 | -3.7034816 | 91 | 85 |
| 2022-10-27T11:44:03 | 8d1e1533-6071-4b10-9cda-b8429c1c7a67 | 40.4169867 | -3.7034818 | 89 | 84 |

So, our first thought would be to create a [Materialized View](https://www.tinybird.co/docs/concepts/materialized-views.html) that joins both streams:

```sql
NODE mat_node
SQL >

    SELECT timestamp, vehicle_id, latitude, longitude, speed, fuel_level_percentage
    FROM gps_data g
    JOIN
        (
            SELECT timestamp, vehicle_id, speed, fuel_level_percentage
            FROM vehicle_data
            WHERE (timestamp, vehicle_id) IN (SELECT timestamp, vehicle_id FROM gps_data)
        ) v
        ON g.vehicle_id = v.vehicle_id
        AND g.timestamp = v.timestamp

TYPE materialized
DATASOURCE mat_node_mv
ENGINE "MergeTree"
ENGINE_PARTITION_KEY "toYYYYMM(timestamp)"
ENGINE_SORTING_KEY "vehicle_id, timestamp"
```

But note that __we don't have control ove when data arrives to Tinybird and when it is ingested__. Probably someone would already have spotted the issue with the MV but let's simulate it to see what happens:

```bash
cd dataproject0_the_issue

tb auth 

tb push

. ../clean_and_ingest_rows.sh

tb sql "select * from vehicle_data"
#----------------------------------------------------------------------------------------------
#| timestamp           | vehicle_id                           | speed | fuel_level_percentage |
#----------------------------------------------------------------------------------------------
#| 2022-10-27 11:44:03 | 8d1e1533-6071-4b10-9cda-b8429c1c7a67 |    91 |                    85 |
#| 2022-10-27 11:43:02 | 8d1e1533-6071-4b10-9cda-b8429c1c7a67 |    91 |                    85 |
#----------------------------------------------------------------------------------------------

tb sql "select * from gps_data"
#--------------------------------------------------------------------------------------
#| timestamp           | vehicle_id                           | latitude | longitude  |
#--------------------------------------------------------------------------------------
#| 2022-10-27 11:43:02 | 8d1e1533-6071-4b10-9cda-b8429c1c7a67 | 40.41699 | -3.7034817 |
#| 2022-10-27 11:44:03 | 8d1e1533-6071-4b10-9cda-b8429c1c7a67 | 40.41699 | -3.7034817 |
#--------------------------------------------------------------------------------------

tb sql "select * from mv_joined_data"
#----------------------------------------------------------------------------------------------------------------------
#| timestamp           | vehicle_id                           | latitude | longitude  | speed | fuel_level_percentage |
#----------------------------------------------------------------------------------------------------------------------
#| 2022-10-27 11:43:02 | 8d1e1533-6071-4b10-9cda-b8429c1c7a67 | 40.41699 | -3.7034817 |    91 |                    85 |
#----------------------------------------------------------------------------------------------------------------------
```

What happened here? Why are we missing one row in the _mat_gps_join_vehicle_ Data Source? From the [docs](https://www.tinybird.co/docs/guides/materialized-views.html#limitations:~:text=Materialized%20Views%20generated%20using%20JOIN%20clauses%20are%20tricky.%20The%20resulting%20Data%20Source%20will%20be%20only%20automatically%20updated%20if%20and%20when%20a%20new%20operation%20is%20performed%20over%20the%20Data%20Source%20in%20the%20FROM.):

> Materialized Views generated using JOIN clauses are tricky. The resulting Data Source will be only automatically updated if and when a new operation is performed over the Data Source in the FROM.

## Different alternatives

So, to overcome this issue there are several alternatives, each one with its tradeoffs.

### Two materializing pipes joining data and ending in the same Data Source

The easiest way would be to add another pipe that does the JOIN the other way:

```sql
NODE mat_node
SQL >

    SELECT timestamp, vehicle_id, latitude, longitude, speed, fuel_level_percentage
    FROM vehicle_data v
    JOIN
        (
            SELECT timestamp, vehicle_id, latitude, longitude
            FROM gps_data
            WHERE (timestamp, vehicle_id) IN (SELECT timestamp, vehicle_id FROM vehicle_data)
        ) g
        ON g.vehicle_id = v.vehicle_id
        AND g.timestamp = v.timestamp

TYPE materialized
DATASOURCE mat_node_mv
ENGINE "MergeTree"
ENGINE_PARTITION_KEY "toYYYYMM(timestamp)"
ENGINE_SORTING_KEY "vehicle_id, timestamp"
```

Testing it:

```bash
cd ../dataproject1_two_MVs_join

cp ../dataproject0_the_issue/.tinyb ./

tb push

. ../clean_and_ingest_rows.sh

tb sql "select * from vehicle_data"

tb sql "select * from gps_data"

tb sql "select * from mv_joined_data"
```

Now we do have the expected 2 rows:

```bash
----------------------------------------------------------------------------------------------------------------------
| timestamp           | vehicle_id                           | latitude | longitude  | speed | fuel_level_percentage |
----------------------------------------------------------------------------------------------------------------------
| 2022-10-27 11:44:03 | 8d1e1533-6071-4b10-9cda-b8429c1c7a67 | 40.41699 | -3.703482  |    89 |                    84 |
| 2022-10-27 11:43:02 | 8d1e1533-6071-4b10-9cda-b8429c1c7a67 | 40.41699 | -3.7034817 |    91 |                    85 |
----------------------------------------------------------------------------------------------------------------------
```

However, with high rates of ingest, there may be race conditions that lead to missing or duplicated rows, which may be solved by using a ReplacingMergeTree as the target Data Source.  
Also, depending on your scale and how well queries and sorting keys are defined, the JOIN approach can lead to memory errors.

So, if you face these errors or if you need a lot of accuracy, consider these other 2 options:

### Two materializing pipes ending in a SummingMergeTree Data Source

It seems a bit strange going for a SummingMergeTree, but what we really want from here is its ability to materialize the streams into a DS independently and then the background process and the deduplication at query time would take care of joining them.

```bash
cd ../dataproject2_two_MVs_SummingMT

cp ../dataproject0_the_issue/.tinyb ./

tb push

. ../clean_and_ingest_rows.sh

tb sql "select * from vehicle_data"

tb sql "select * from gps_data"

tb sql "
select 
  timestamp, 
  vehicle_id, 
  argMaxMerge(latitude) latitude, 
  argMaxMerge(longitude) 
  longitude, argMaxMerge(speed) speed, 
  argMaxMerge(fuel_level_percentage) fuel_level_percentage 
from mv_summed_data 
group by timestamp, vehicle_id"
```

### Join with Copy Pipes instead of with MVs

[Copy Pipes](https://www.tinybird.co/docs/publish/copy-pipes.html) can help us overcome some of the limitations of MVs for this use case, but some assumptions are needed.

- We need to define a time window that we think is safe for our usecase. Otherwise we would be scanning the entire Data Source on every copy job and would make the solution prohibitive. In the example in this pipe we are taking 10 mins, so if some messages takes longer we may lose them in the joined target Data Source.

```bash
cd ../dataproject3_using_copy_pipes

cp ../dataproject0_the_issue/.tinyb ./

tb push

. ../clean_and_ingest_rows.sh


tb sql "select * from vehicle_data"

tb sql "select * from gps_data"

tb pipe copy run copy_join --yes

# You can check the copy status with `tb job details` and then query the data source once status is done.

tb sql "select * from ds_joined_data"

#----------------------------------------------------------------------------------------------------------------------
#| timestamp           | vehicle_id                           | latitude | longitude  | speed | fuel_level_percentage |
#----------------------------------------------------------------------------------------------------------------------
#| 2022-10-27 11:43:02 | 8d1e1533-6071-4b10-9cda-b8429c1c7a67 | 40.41699 | -3.7034817 |    91 |                    85 |
#| 2022-10-27 11:44:03 | 8d1e1533-6071-4b10-9cda-b8429c1c7a67 | 40.41699 | -3.703482  |    89 |                    84 |
#----------------------------------------------------------------------------------------------------------------------

```

### Join with Copy pipes and at query time (Kappa architecture)

If freshness is a hard requierement for your API Endpoint —and, in Tinybird, it usually is—, this approach can be combined with joining at query time. But these is way more performant than joining everything at query time since with this approach you only have to join the data that was not processed in the latest copy batch. Also, with this [kappa](https://en.wikipedia.org/wiki/Lambda_architecture#Kappa_architecture) (batch join + realtime join) approach, we could relax the frequency of the scheduled copy operations.

The kappa pipe is equivalent* to _copy_join.pipe_, only that at the end wwe retrieve the data from _ds_joined_data_ too.

```sql

--(... same as copy_join)

NODE endpoint
DESCRIPTION >
    and unioning them with the already processed

SQL >

    SELECT * FROM ds_joined_data
    UNION ALL
    SELECT * FROM inner_join

```

*although applying some filters first if that matches your use case is highly recommended.
