-- GPS lookup uses the live city catalogue, including orders created before GPS support.
CREATE INDEX IF NOT EXISTS records_city_name_active ON records(country,(data->>'name'))
WHERE kind='city' AND data->>'status'='active';
