ALTER TABLE reports ADD COLUMN author_name VARCHAR(200) NULL;
ALTER TABLE report_crew ADD COLUMN member_name VARCHAR(200) NULL;
ALTER TABLE incidents ADD COLUMN report_data_frozen TINYINT(1) NOT NULL DEFAULT 0;

UPDATE reports r
JOIN incidents i ON i.id=r.incident_id
LEFT JOIN users u ON u.id=r.author_id AND u.organization_id=i.organization_id
SET r.author_name=COALESCE(u.name,'');

UPDATE report_crew rc
JOIN reports r ON r.id=rc.report_id
JOIN incidents i ON i.id=r.incident_id
LEFT JOIN members m ON m.id=rc.member_id AND m.organization_id=i.organization_id
SET rc.member_name=COALESCE(m.name,'');

SET @previous_group_concat_max_len=@@SESSION.group_concat_max_len;
SET SESSION group_concat_max_len=4294967295;
UPDATE reports r
SET r.personnel=COALESCE((
  SELECT GROUP_CONCAT(rc.member_name ORDER BY rc.member_id SEPARATOR ', ')
  FROM report_crew rc JOIN members m ON m.id=rc.member_id
  JOIN incidents i ON i.id=r.incident_id AND i.organization_id=m.organization_id
  WHERE rc.report_id=r.id
),''),
r.revision=r.revision+1;
SET SESSION group_concat_max_len=@previous_group_concat_max_len;

UPDATE incidents i SET i.report_data_frozen=1,i.revision=i.revision+1
WHERE EXISTS(SELECT 1 FROM reports r WHERE r.incident_id=i.id);

ALTER TABLE reports MODIFY COLUMN author_name VARCHAR(200) NOT NULL;
ALTER TABLE report_crew MODIFY COLUMN member_name VARCHAR(200) NOT NULL;
