-- Eligible videos for the YouTube processor (services/youtube-processor/worker.py).
-- Read from disk on every batch so it can be edited at any time, without a restart.
--
-- The worker substitutes exactly four tokens before execution, in this order:
--   1. status_ph      -> the IN-list for audioUploadStatus
--   2. retry_clause   -> optional retry-count filter (empty when not retrying failed)
--   3. channel_clause -> optional channel-name ILIKE filter (empty when unset)
--   4. priority_clause-> optional "priority channels first" ORDER BY tier (empty when unset)
-- Each token is written in the query as left-brace + name + right-brace.
--
-- WARNING: comment lines must not contain those token names, nor the psycopg2
-- parameter marker (single percent followed by the letter s) or doubled
-- percent, because they would be counted as extra query parameters.
SELECT v.id, v.title, COALESCE(v."channelName", c.name, 'Unknown'), v."publishedAt", v.description, c.language, v."channelId", v."duration", v."thumbnail"
FROM "Video" v
JOIN "Channel" c ON c.id = v."channelId"
LEFT JOIN (
    SELECT "channelId", COUNT(*) AS video_count
    FROM "Video"
    GROUP BY "channelId"
) vc ON vc."channelId" = v."channelId"
WHERE (c."isActive" = true OR c."isActive" IS NULL)
  AND c.id != 'UC_ChristianTubeOfficial'
  AND (v."duration" IS NULL OR (v."duration" != '0:00' AND v."duration" NOT LIKE '0:0%%'))
  AND (v."audioUploadStatus" IS NULL OR v."audioUploadStatus" IN ({status_ph}))
  {retry_clause}
  {channel_clause}
ORDER BY{priority_clause}
         CASE c.language
           WHEN 'Tamil' THEN 0
           WHEN 'English' THEN 1
           ELSE 2
         END,
         vc.video_count DESC,
         v."publishedAt" DESC
LIMIT %s