ALTER TABLE reports
  ADD COLUMN report_year SMALLINT UNSIGNED NULL AFTER author_id,
  ADD COLUMN running_number VARCHAR(50) NULL AFTER report_year,
  ADD COLUMN damaged_party JSON NULL AFTER running_number,
  ADD COLUMN damaging_party JSON NULL AFTER damaged_party,
  ADD COLUMN incident_command JSON NULL AFTER damaging_party,
  ADD UNIQUE KEY reports_unit_year_number (unit_id, report_year, running_number);
