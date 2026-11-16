## CASE 1 - YoY
### Extract https://cloud.google.com/bigquery/docs/reference/standard-sql/date_functions#extract
### Window Functions https://cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls
### Lag https://cloud.google.com/bigquery/docs/reference/standard-sql/navigation_functions#lag

WITH yoy_extract_iso_date_parts AS(
SELECT
  datum,
  EXTRACT(ISOYEAR FROM datum) AS isoYear,
  EXTRACT(ISOWEEK FROM datum) AS isoWeek,
  EXTRACT(DAYOFWEEK FROM datum) AS dayOfWeek,
  wert
FROM
  `project.dataset.table` 
)

SELECT
  *,
  LAG(wert) OVER (PARTITION BY isoWeek, dayOfWeek  ORDER BY isoYear) AS wertLastYear,
FROM
  yoy_extract_iso_date_parts


## CASE 2 - Distribution

### Approach 1: Calculate the Number of Pageviews for Every Session
WITH pageviews_per_session_table AS(
SELECT
  CONCAT((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id'), user_pseudo_id) AS session_id, 
  COUNT(*) AS pageviews_per_session 
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_20210131`
WHERE
    event_name = 'page_view'
GROUP BY
  1)

Select
  *
FROM
  pageviews_per_session_table


### Approach 2: Fixed Cut Off
WITH pageviews_per_session_table AS(
SELECT
  CONCAT((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id'), user_pseudo_id) AS session_id, 
  COUNT(*) AS pageviews_per_session 
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_20210131`
WHERE
    event_name = 'page_view'
GROUP BY
  1)

SELECT
  pageviews_per_session,
  IF(pageviews_per_session >= 10, "10+", CAST(pageviews_per_session AS STRING)) AS cut_off_label_fixed,
  COUNT(*) AS count_pageviews_per_session
FROM
  pageviews_per_session_table
GROUP BY
  1,
  2
ORDER BY
    pageviews_per_session DESC



### Approach 2: Variable Cut Off
WITH pageviews_per_session_table AS(
SELECT
  CONCAT((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id'), user_pseudo_id) AS session_id, 
  COUNT(*) AS pageviews_per_session 
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_20210131`
WHERE
    event_name = 'page_view'
GROUP BY
  1),

percentile_table AS(
SELECT
  session_id,
  pageviews_per_session,
  PERCENTILE_CONT(pageviews_per_session, 0.96) OVER() AS percentile
FROM
  pageviews_per_session_table
)

SELECT
  pageviews_per_session,
  IF(pageviews_per_session >= percentile, CONCAT(CAST(percentile AS STRING), "+"), CAST(pageviews_per_session AS STRING)) AS cut_off_label_percentil,
  COUNT(*) AS count_pageviews_per_session
FROM
  percentile_table
GROUP BY
  1,
  2
ORDER BY
    pageviews_per_session DESC


## CASE 3: Retention

# user_pseudo_ids
WITH user_pseudo_ids AS(

SELECT
  DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK) AS date, # Trunc to Week
  user_pseudo_id AS user_pseudo_id
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

GROUP BY
  1,
  2),
 
min_date AS(
   
SELECT
    date,
    user_pseudo_id,
    min(date) OVER (PARTITION BY user_pseudo_id) as minDate,
    DATE_DIFF(date, min(date) OVER (PARTITION BY user_pseudo_id), WEEK) AS deltaWeek
FROM
    user_pseudo_ids),
   
cohorts AS (
   
SELECT
    minDate,
    deltaWeek,
    COUNT(*) as users
FROM
    min_date
GROUP BY
    minDate,
    deltaWeek)
  
SELECT
    *,
    MAX(users) OVER(PARTITION BY minDate) AS baseusers,
    (users / MAX(users) OVER(PARTITION BY minDate)) AS rationusers
FROM
    cohorts


## CASE 4: Overlap

WITH apparel AS(
SELECT
  user_pseudo_id
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_20210131`
WHERE
  event_name = 'page_view'
  AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') LIKE 'https://shop.googlemerchandisestore.com/Google+Redesign/Apparel%'
GROUP BY
  1),

lifestyle AS(
SELECT
  user_pseudo_id
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_20210131`
WHERE
  event_name = 'page_view'
  AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') LIKE 'https://shop.googlemerchandisestore.com/Google+Redesign/Lifestyle%'
GROUP BY
  1
),

stationary AS(
SELECT
  user_pseudo_id
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_20210131`
WHERE
  event_name = 'page_view'
  AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') LIKE 'https://shop.googlemerchandisestore.com/Google+Redesign/Stationery%'
GROUP BY
  1
),

# Calculate apparel
apparel_users AS(
SELECT
  'apparel' AS dimension,
  COUNT(DISTINCT user_pseudo_id) AS metric
FROM
  apparel
),

# Calculate lifestyle
lifestyle_users AS(
SELECT
  'lifestyle' AS dimension,
  COUNT(DISTINCT user_pseudo_id) AS metric
FROM
  lifestyle
),

# Calculate stationary
stationary_users AS(
SELECT
  'stationary' AS dimension,
  COUNT(DISTINCT user_pseudo_id) AS metric
FROM
  stationary
),

# Calculate intersection apparel, lifestyle
apparel_lifestyle_users AS(
SELECT
  'apparel,lifestyle' AS dimension,
  COUNT(DISTINCT user_pseudo_id) AS metric
FROM
  apparel
WHERE
  user_pseudo_id IN (SELECT user_pseudo_id FROM lifestyle)
  ),

# Calculate intersection apparel, stationary
apparel_stationary_users AS(
SELECT
  'apparel,stationary' AS dimension,
  COUNT(DISTINCT user_pseudo_id) AS metric
FROM
  apparel
WHERE
  user_pseudo_id IN (SELECT user_pseudo_id FROM stationary)),

# Calculate intersection lifestyle, stationary
lifestyle_stationary_users AS(
SELECT
  'lifestyle,stationary' AS dimension,
  COUNT(DISTINCT user_pseudo_id) AS metric
FROM
  lifestyle
WHERE
  user_pseudo_id IN (SELECT user_pseudo_id FROM stationary)),

# Calculate intersection apparel, lifestyle, stationary
apparel_lifestyle_stationary_users AS(
SELECT
  'apparel,lifestyle,stationary' AS dimension,
  COUNT(DISTINCT user_pseudo_id) AS metric
FROM
  apparel
WHERE
  user_pseudo_id IN (SELECT user_pseudo_id FROM lifestyle)
  AND user_pseudo_id IN (SELECT user_pseudo_id FROM stationary))

# Union all counts
 
SELECT
  *
FROM
  apparel_lifestyle_stationary_users
UNION ALL
SELECT
  *
FROM
  lifestyle_stationary_users
UNION ALL
SELECT
  *
FROM
  apparel_stationary_users
UNION ALL
SELECT
  *
FROM
  apparel_lifestyle_users
UNION ALL
SELECT
  *
FROM
  stationary_users
UNION ALL
SELECT
  *
FROM
  lifestyle_users
UNION ALL
SELECT
  *
FROM
  apparel_users


### YTD Bonus

WITH page_views_daily AS(

SELECT
  PARSE_DATE("%Y%m%d", event_date) AS date,
  COUNT(*) AS pageviews
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE
  event_name = 'page_view'
GROUP BY
  1
ORDER BY  
  date ASC)

SELECT
  *,
  SUM(pageviews) OVER (PARTITION BY EXTRACT(YEAR FROM date) ORDER BY date ASC) AS page_views_ytd
FROM
  page_views_daily