SET NAMES utf8mb4;

CREATE TABLE organizations (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(200) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE units (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  organization_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(200) NOT NULL,
  divera_access_key VARCHAR(500),
  UNIQUE KEY units_org_name (organization_id, name),
  CONSTRAINT units_org_fk FOREIGN KEY (organization_id) REFERENCES organizations(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE users (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  organization_id BIGINT UNSIGNED NOT NULL,
  unit_id BIGINT UNSIGNED,
  name VARCHAR(200) NOT NULL,
  email VARCHAR(320) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  role ENUM('wehrleitung','einheitsleitung','fuehrungskraft') NOT NULL,
  CONSTRAINT users_role_unit CHECK (role = 'wehrleitung' OR unit_id IS NOT NULL),
  CONSTRAINT users_org_fk FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT users_unit_fk FOREIGN KEY (unit_id) REFERENCES units(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE user_units (
  user_id BIGINT UNSIGNED NOT NULL,
  unit_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (user_id, unit_id),
  CONSTRAINT user_units_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT user_units_unit_fk FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE sessions (
  token CHAR(64) PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  expires_at DATETIME NOT NULL,
  KEY sessions_expires (expires_at),
  CONSTRAINT sessions_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE login_history (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  logged_in_at DATETIME NOT NULL,
  KEY login_history_user_time (user_id, logged_in_at),
  CONSTRAINT login_history_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE password_resets (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  token_hash CHAR(64) NOT NULL,
  requested_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME NOT NULL,
  UNIQUE KEY password_resets_user (user_id),
  UNIQUE KEY password_resets_token (token_hash),
  KEY password_resets_expires (expires_at),
  CONSTRAINT password_resets_user_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE incidents (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  organization_id BIGINT UNSIGNED NOT NULL,
  divera_id VARCHAR(200),
  foreign_id VARCHAR(200) NOT NULL DEFAULT '',
  divera_date BIGINT,
  title VARCHAR(300) NOT NULL,
  started_at VARCHAR(100) NOT NULL,
  message TEXT NOT NULL,
  address VARCHAR(500) NOT NULL DEFAULT '',
  lat DOUBLE,
  lng DOUBLE,
  remark TEXT NOT NULL,
  patient TEXT NOT NULL,
  caller TEXT NOT NULL,
  consolidated_text TEXT NOT NULL,
  consolidated_at DATETIME,
  UNIQUE KEY incidents_org_divera (organization_id, divera_id),
  CONSTRAINT incidents_org_fk FOREIGN KEY (organization_id) REFERENCES organizations(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE incident_units (
  incident_id BIGINT UNSIGNED NOT NULL,
  unit_id BIGINT UNSIGNED NOT NULL,
  vehicles JSON NOT NULL,
  PRIMARY KEY (incident_id, unit_id),
  CONSTRAINT incident_units_incident_fk FOREIGN KEY (incident_id) REFERENCES incidents(id) ON DELETE CASCADE,
  CONSTRAINT incident_units_unit_fk FOREIGN KEY (unit_id) REFERENCES units(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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

CREATE TABLE members (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  organization_id BIGINT UNSIGNED NOT NULL,
  divera_id VARCHAR(200) NOT NULL,
  name VARCHAR(200) NOT NULL,
  UNIQUE KEY members_org_divera (organization_id, divera_id),
  CONSTRAINT members_org_fk FOREIGN KEY (organization_id) REFERENCES organizations(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE member_units (
  member_id BIGINT UNSIGNED NOT NULL,
  unit_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (member_id, unit_id),
  CONSTRAINT member_units_member_fk FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE,
  CONSTRAINT member_units_unit_fk FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE qualifications (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  unit_id BIGINT UNSIGNED NOT NULL,
  divera_id VARCHAR(200) NOT NULL,
  name VARCHAR(200) NOT NULL,
  shortname VARCHAR(100) NOT NULL DEFAULT '',
  UNIQUE KEY qualifications_unit_divera (unit_id, divera_id),
  CONSTRAINT qualifications_unit_fk FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE member_qualifications (
  member_id BIGINT UNSIGNED NOT NULL,
  qualification_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (member_id, qualification_id),
  CONSTRAINT member_qualifications_member_fk FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE,
  CONSTRAINT member_qualifications_qualification_fk FOREIGN KEY (qualification_id) REFERENCES qualifications(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE vehicles (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  unit_id BIGINT UNSIGNED NOT NULL,
  divera_id VARCHAR(200) NOT NULL,
  name VARCHAR(200) NOT NULL,
  shortname VARCHAR(100) NOT NULL DEFAULT '',
  fullname VARCHAR(200) NOT NULL DEFAULT '',
  UNIQUE KEY vehicles_unit_divera (unit_id, divera_id),
  CONSTRAINT vehicles_unit_fk FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE reports (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  incident_id BIGINT UNSIGNED NOT NULL,
  unit_id BIGINT UNSIGNED NOT NULL,
  author_id BIGINT UNSIGNED NOT NULL,
  report_year SMALLINT UNSIGNED,
  running_number VARCHAR(50),
  damaged_party JSON,
  damaging_party JSON,
  incident_command JSON,
  narrative TEXT NOT NULL,
  vehicles TEXT NOT NULL,
  personnel TEXT NOT NULL,
  alarmed_at VARCHAR(100),
  departed_at VARCHAR(100),
  arrived_at VARCHAR(100),
  ended_at VARCHAR(100),
  incident_type VARCHAR(100) NOT NULL DEFAULT '',
  classification JSON NOT NULL,
  status ENUM('author_draft','unit_review','wehr_review') NOT NULL DEFAULT 'author_draft',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  released_at DATETIME,
  UNIQUE KEY reports_incident_unit (incident_id, unit_id),
  UNIQUE KEY reports_unit_year_number (unit_id, report_year, running_number),
  CONSTRAINT reports_incident_fk FOREIGN KEY (incident_id) REFERENCES incidents(id) ON DELETE CASCADE,
  CONSTRAINT reports_unit_fk FOREIGN KEY (unit_id) REFERENCES units(id),
  CONSTRAINT reports_author_fk FOREIGN KEY (author_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE report_transitions (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  report_id BIGINT UNSIGNED NOT NULL,
  from_status ENUM('author_draft','unit_review','wehr_review'),
  to_status ENUM('author_draft','unit_review','wehr_review') NOT NULL,
  actor_id BIGINT UNSIGNED,
  actor_name VARCHAR(200) NOT NULL,
  actor_role ENUM('wehrleitung','einheitsleitung','fuehrungskraft') NOT NULL,
  comment VARCHAR(2000) NOT NULL DEFAULT '',
  created_at DATETIME NOT NULL,
  KEY report_transitions_report_time (report_id, created_at, id),
  CONSTRAINT report_transitions_report_fk FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE,
  CONSTRAINT report_transitions_actor_fk FOREIGN KEY (actor_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE report_crew (
  report_id BIGINT UNSIGNED NOT NULL,
  member_id BIGINT UNSIGNED NOT NULL,
  vehicle VARCHAR(200) NOT NULL DEFAULT '',
  role ENUM('maschinist','einheitsfuehrer','besatzung') NOT NULL DEFAULT 'besatzung',
  PRIMARY KEY (report_id, member_id),
  CONSTRAINT report_crew_report_fk FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE,
  CONSTRAINT report_crew_member_fk FOREIGN KEY (member_id) REFERENCES members(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE schema_migrations (
  name VARCHAR(255) PRIMARY KEY,
  applied_at DATETIME NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO schema_migrations(name,applied_at) VALUES('001-report-workflow-and-vehicles.sql',UTC_TIMESTAMP());
