-- Enable trigram similarity for fuzzy audio search (typo-tolerant matching
-- on series/track titles, speakers, and descriptions).

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- GIN trigram indexes over the searchable text fields.
CREATE INDEX "AudioSeries_title_trgm_idx" ON "AudioSeries" USING GIN ("title" gin_trgm_ops);
CREATE INDEX "AudioSeries_speaker_trgm_idx" ON "AudioSeries" USING GIN ("speaker" gin_trgm_ops);
CREATE INDEX "AudioSeries_description_trgm_idx" ON "AudioSeries" USING GIN ("description" gin_trgm_ops);
CREATE INDEX "AudioTrack_title_trgm_idx" ON "AudioTrack" USING GIN ("title" gin_trgm_ops);
CREATE INDEX "AudioTrack_speaker_trgm_idx" ON "AudioTrack" USING GIN ("speaker" gin_trgm_ops);