CREATE TABLE divera_imports (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  unit_id BIGINT UNSIGNED NOT NULL,
  incident_id BIGINT UNSIGNED NOT NULL,
  imported_by BIGINT UNSIGNED,
  imported_at DATETIME NOT NULL,
  KEY divera_imports_unit_time (unit_id, imported_at),
  CONSTRAINT divera_imports_unit_fk FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE CASCADE,
  CONSTRAINT divera_imports_incident_fk FOREIGN KEY (incident_id) REFERENCES incidents(id) ON DELETE CASCADE,
  CONSTRAINT divera_imports_user_fk FOREIGN KEY (imported_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
