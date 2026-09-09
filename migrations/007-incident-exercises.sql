ALTER TABLE incidents ADD COLUMN is_exercise BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE incident_exercise_changes (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  incident_id BIGINT UNSIGNED NOT NULL,
  old_value BOOLEAN NOT NULL,
  new_value BOOLEAN NOT NULL,
  actor_id BIGINT UNSIGNED,
  actor_name VARCHAR(200) NOT NULL,
  actor_role ENUM('wehrleitung','einheitsleitung','fuehrungskraft') NOT NULL,
  created_at DATETIME NOT NULL,
  KEY incident_exercise_changes_incident_time (incident_id, created_at, id),
  CONSTRAINT incident_exercise_changes_incident_fk FOREIGN KEY (incident_id) REFERENCES incidents(id),
  CONSTRAINT incident_exercise_changes_actor_fk FOREIGN KEY (actor_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
