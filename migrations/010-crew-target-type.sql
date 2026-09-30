ALTER TABLE report_crew
  ADD COLUMN target_type ENUM('vehicle','without_vehicle','on_scene') NOT NULL DEFAULT 'vehicle' AFTER vehicle;

UPDATE report_crew
SET target_type = CASE WHEN vehicle = '' THEN 'without_vehicle' ELSE 'vehicle' END;
