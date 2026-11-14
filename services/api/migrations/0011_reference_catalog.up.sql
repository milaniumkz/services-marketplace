CREATE INDEX IF NOT EXISTS records_category_parent ON records(country,(data->'payload'->>'parent_id')) WHERE kind='category' AND data->>'status'='effective';
CREATE INDEX IF NOT EXISTS records_city_geonames ON records(country,(data->>'geonames_id')) WHERE kind='city';
