CREATE TABLE IF NOT EXISTS report_additional_vehicles (
  report_id BIGINT UNSIGNED NOT NULL,
  vehicle VARCHAR(200) NOT NULL,
  PRIMARY KEY (report_id, vehicle),
  CONSTRAINT report_additional_vehicles_report_fk FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
