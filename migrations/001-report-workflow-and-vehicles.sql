CREATE TABLE IF NOT EXISTS vehicles (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  unit_id BIGINT UNSIGNED NOT NULL,
  divera_id VARCHAR(200) NOT NULL,
  name VARCHAR(200) NOT NULL,
  shortname VARCHAR(100) NOT NULL DEFAULT '',
  fullname VARCHAR(200) NOT NULL DEFAULT '',
  UNIQUE KEY vehicles_unit_divera (unit_id, divera_id),
  CONSTRAINT vehicles_unit_fk FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE reports MODIFY status ENUM('draft','released','author_draft','unit_review','wehr_review') NOT NULL DEFAULT 'draft';

UPDATE reports r
JOIN users u ON u.id=r.author_id
SET r.status=CASE
  WHEN r.status='released' THEN 'wehr_review'
  WHEN u.role='einheitsleitung' THEN 'unit_review'
  WHEN u.role='wehrleitung' THEN 'wehr_review'
  ELSE 'author_draft'
END
WHERE r.status IN ('draft','released');

ALTER TABLE reports MODIFY status ENUM('author_draft','unit_review','wehr_review') NOT NULL DEFAULT 'author_draft';

CREATE TABLE IF NOT EXISTS report_transitions (
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

INSERT INTO report_transitions(report_id,from_status,to_status,actor_id,actor_name,actor_role,comment,created_at)
SELECT r.id,NULL,r.status,u.id,u.name,u.role,'',COALESCE(r.released_at,r.created_at)
FROM reports r JOIN users u ON u.id=r.author_id
WHERE NOT EXISTS(SELECT 1 FROM report_transitions rt WHERE rt.report_id=r.id);
