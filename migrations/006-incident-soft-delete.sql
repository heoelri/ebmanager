ALTER TABLE incidents ADD COLUMN deleted_at DATETIME NULL;

CREATE TABLE incident_deletions (
  incident_id BIGINT UNSIGNED PRIMARY KEY,
  actor_id BIGINT UNSIGNED,
  actor_name VARCHAR(200) NOT NULL,
  actor_role ENUM('wehrleitung','einheitsleitung') NOT NULL,
  created_at DATETIME NOT NULL,
  CONSTRAINT incident_deletions_incident_fk FOREIGN KEY (incident_id) REFERENCES incidents(id),
  CONSTRAINT incident_deletions_actor_fk FOREIGN KEY (actor_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
