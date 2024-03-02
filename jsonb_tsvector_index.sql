CREATE INDEX ON dataclips
   USING gin ( jsonb_to_tsvector('english',"body", '"all"') );
