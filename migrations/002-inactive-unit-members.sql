ALTER TABLE member_units
  ADD COLUMN active BOOLEAN NOT NULL DEFAULT TRUE AFTER unit_id;

INSERT IGNORE INTO member_units(member_id,unit_id,active)
SELECT DISTINCT rc.member_id,r.unit_id,FALSE
FROM report_crew rc
JOIN reports r ON r.id=rc.report_id;
