ALTER TABLE login_history ADD KEY login_history_time (logged_in_at, id);

CREATE TABLE auth_cleanup_state (
  id TINYINT UNSIGNED PRIMARY KEY,
  last_run_at DATETIME NOT NULL,
  CONSTRAINT auth_cleanup_singleton CHECK (id=1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO auth_cleanup_state(id,last_run_at) VALUES(1,'1970-01-01 00:00:00');
