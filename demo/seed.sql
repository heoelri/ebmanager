SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
START TRANSACTION;

SET @demo_name = 'Freiwillige Feuerwehr Musterstadt';
SET @old_org = (SELECT id FROM organizations WHERE name=@demo_name ORDER BY id LIMIT 1);

DELETE rc FROM report_crew rc JOIN reports r ON r.id=rc.report_id JOIN incidents i ON i.id=r.incident_id WHERE i.organization_id=@old_org;
DELETE rt FROM report_transitions rt JOIN reports r ON r.id=rt.report_id JOIN incidents i ON i.id=r.incident_id WHERE i.organization_id=@old_org;
DELETE r FROM reports r JOIN incidents i ON i.id=r.incident_id WHERE i.organization_id=@old_org;
DELETE di FROM divera_imports di JOIN units u ON u.id=di.unit_id WHERE u.organization_id=@old_org;
DELETE iu FROM incident_units iu JOIN incidents i ON i.id=iu.incident_id WHERE i.organization_id=@old_org;
DELETE FROM incidents WHERE organization_id=@old_org;
DELETE mq FROM member_qualifications mq JOIN members m ON m.id=mq.member_id WHERE m.organization_id=@old_org;
DELETE mu FROM member_units mu JOIN members m ON m.id=mu.member_id WHERE m.organization_id=@old_org;
DELETE FROM members WHERE organization_id=@old_org;
DELETE q FROM qualifications q JOIN units u ON u.id=q.unit_id WHERE u.organization_id=@old_org;
DELETE v FROM vehicles v JOIN units u ON u.id=v.unit_id WHERE u.organization_id=@old_org;
DELETE pr FROM password_resets pr JOIN users u ON u.id=pr.user_id WHERE u.organization_id=@old_org;
DELETE s FROM sessions s JOIN users u ON u.id=s.user_id WHERE u.organization_id=@old_org;
DELETE h FROM login_history h JOIN users u ON u.id=h.user_id WHERE u.organization_id=@old_org;
DELETE uu FROM user_units uu JOIN users u ON u.id=uu.user_id WHERE u.organization_id=@old_org;
DELETE FROM users WHERE organization_id=@old_org;
DELETE FROM units WHERE organization_id=@old_org;
DELETE FROM organizations WHERE id=@old_org;

INSERT INTO organizations(name) VALUES(@demo_name);
SET @org = LAST_INSERT_ID();

INSERT INTO units(organization_id,name) VALUES
  (@org,'Löschzug Mitte'),
  (@org,'Löschgruppe Nord'),
  (@org,'Löschgruppe Süd');
SET @mitte = (SELECT id FROM units WHERE organization_id=@org AND name='Löschzug Mitte');
SET @nord = (SELECT id FROM units WHERE organization_id=@org AND name='Löschgruppe Nord');
SET @sued = (SELECT id FROM units WHERE organization_id=@org AND name='Löschgruppe Süd');

SET @password = '$2y$12$ouANxbKroADL.mxsXE/Swu35xWQBnBg2YK2af6nPP4QgPIe73Fyp2';
INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) VALUES
  (@org,NULL,'Alexandra Brandt','wehrleitung@demo.local',@password,'wehrleitung'),
  (@org,@mitte,'Martin Berger','leitung.mitte@demo.local',@password,'einheitsleitung'),
  (@org,@nord,'Nora Hansen','leitung.nord@demo.local',@password,'einheitsleitung'),
  (@org,@sued,'Stefan Krüger','leitung.sued@demo.local',@password,'einheitsleitung'),
  (@org,@mitte,'Franziska Roth','fuehrung.mitte@demo.local',@password,'fuehrungskraft'),
  (@org,@nord,'Nils Weber','fuehrung.nord@demo.local',@password,'fuehrungskraft'),
  (@org,@sued,'Sophie König','fuehrung.sued@demo.local',@password,'fuehrungskraft'),
  (@org,@mitte,'Daniel Winter','fuehrung.springer@demo.local',@password,'fuehrungskraft');
SET @wehr = (SELECT id FROM users WHERE organization_id=@org AND email='wehrleitung@demo.local');
SET @leitung_mitte = (SELECT id FROM users WHERE organization_id=@org AND email='leitung.mitte@demo.local');
SET @leitung_nord = (SELECT id FROM users WHERE organization_id=@org AND email='leitung.nord@demo.local');
SET @leitung_sued = (SELECT id FROM users WHERE organization_id=@org AND email='leitung.sued@demo.local');
SET @fuehrung_mitte = (SELECT id FROM users WHERE organization_id=@org AND email='fuehrung.mitte@demo.local');
SET @fuehrung_nord = (SELECT id FROM users WHERE organization_id=@org AND email='fuehrung.nord@demo.local');
SET @fuehrung_sued = (SELECT id FROM users WHERE organization_id=@org AND email='fuehrung.sued@demo.local');
SET @fuehrung_springer = (SELECT id FROM users WHERE organization_id=@org AND email='fuehrung.springer@demo.local');

INSERT INTO user_units(user_id,unit_id) VALUES
  (@leitung_mitte,@mitte),(@leitung_nord,@nord),(@leitung_sued,@sued),
  (@fuehrung_mitte,@mitte),(@fuehrung_nord,@nord),(@fuehrung_sued,@sued),
  (@fuehrung_springer,@mitte),(@fuehrung_springer,@nord);

INSERT INTO qualifications(unit_id,divera_id,name,shortname) VALUES
  (@mitte,'demo-mitte-gf','Gruppenführer','GF'),
  (@mitte,'demo-mitte-ma','Maschinist','MA'),
  (@mitte,'demo-mitte-agt','Atemschutzgeräteträger','AGT'),
  (@mitte,'demo-mitte-san','Sanitäter','SAN'),
  (@nord,'demo-nord-gf','Gruppenführer','GF'),
  (@nord,'demo-nord-ma','Maschinist','MA'),
  (@nord,'demo-nord-agt','Atemschutzgeräteträger','AGT'),
  (@nord,'demo-nord-san','Sanitäter','SAN'),
  (@sued,'demo-sued-gf','Gruppenführer','GF'),
  (@sued,'demo-sued-ma','Maschinist','MA'),
  (@sued,'demo-sued-agt','Atemschutzgeräteträger','AGT'),
  (@sued,'demo-sued-san','Sanitäter','SAN');

INSERT INTO members(organization_id,divera_id,name) VALUES
  (@org,'demo-mitte-01','Alina Becker'),(@org,'demo-mitte-02','Ben Lorenz'),
  (@org,'demo-mitte-03','Clara Neumann'),(@org,'demo-mitte-04','David Schmitt'),
  (@org,'demo-mitte-05','Elena Vogt'),(@org,'demo-mitte-06','Felix Werner'),
  (@org,'demo-mitte-07','Greta Baum'),(@org,'demo-mitte-08','Hannes Wolf'),
  (@org,'demo-nord-01','Ida Franke'),(@org,'demo-nord-02','Jonas Hartmann'),
  (@org,'demo-nord-03','Kira Peters'),(@org,'demo-nord-04','Lukas Krause'),
  (@org,'demo-nord-05','Mara Seidel'),(@org,'demo-nord-06','Noah Fuchs'),
  (@org,'demo-nord-07','Olivia Busch'),(@org,'demo-nord-08','Paul Lindner'),
  (@org,'demo-sued-01','Quirin Scholz'),(@org,'demo-sued-02','Romy Graf'),
  (@org,'demo-sued-03','Simon Keller'),(@org,'demo-sued-04','Tina Arnold'),
  (@org,'demo-sued-05','Uwe Sommer'),(@org,'demo-sued-06','Vera Lang'),
  (@org,'demo-sued-07','Wilma Ernst'),(@org,'demo-sued-08','Yannick Böhm');

INSERT INTO member_units(member_id,unit_id)
SELECT id,
  CASE
    WHEN divera_id LIKE 'demo-mitte-%' THEN @mitte
    WHEN divera_id LIKE 'demo-nord-%' THEN @nord
    ELSE @sued
  END
FROM members WHERE organization_id=@org;

INSERT INTO member_qualifications(member_id,qualification_id)
SELECT m.id,q.id
FROM members m
JOIN member_units mu ON mu.member_id=m.id
JOIN qualifications q ON q.unit_id=mu.unit_id
WHERE m.organization_id=@org AND (
  (q.shortname='GF' AND RIGHT(m.divera_id,2) IN ('01','05'))
  OR (q.shortname='MA' AND RIGHT(m.divera_id,2) IN ('02','06'))
  OR (q.shortname='AGT' AND RIGHT(m.divera_id,2) IN ('03','04','05','06'))
  OR (q.shortname='SAN' AND RIGHT(m.divera_id,2) IN ('07','08'))
);

INSERT INTO vehicles(unit_id,divera_id,name,shortname,fullname) VALUES
  (@mitte,'demo-mitte-elw','ELW 1','ELW 1','Einsatzleitwagen 1'),
  (@mitte,'demo-mitte-hlf','HLF 20','HLF 20','Hilfeleistungslöschgruppenfahrzeug 20'),
  (@mitte,'demo-mitte-dlk','DLK 23','DLK 23','Drehleiter mit Korb 23'),
  (@nord,'demo-nord-lf','LF 10','LF 10','Löschgruppenfahrzeug 10'),
  (@nord,'demo-nord-mtf','MTF Nord','MTF','Mannschaftstransportfahrzeug'),
  (@sued,'demo-sued-tsf','TSF-W Süd','TSF-W','Tragkraftspritzenfahrzeug mit Wasser'),
  (@sued,'demo-sued-gwl','GW-L Süd','GW-L','Gerätewagen Logistik'),
  (@sued,'demo-sued-mtf','MTF Süd','MTF','Mannschaftstransportfahrzeug');

INSERT INTO incidents(organization_id,divera_id,foreign_id,divera_date,title,started_at,message,address,lat,lng,remark,patient,caller,consolidated_text,consolidated_at) VALUES
  (@org,'demo-001','D-2026-001',UNIX_TIMESTAMP(UTC_TIMESTAMP()-INTERVAL 1 DAY),'Kleinbrand Müllbehälter',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 1 DAY,'%Y-%m-%dT%H:%i:%s.000Z'),'Brennender Müllbehälter','Musterstraße 1, Musterstadt',50.1001,8.6001,'Demo: Entwurf noch offen','','Leitstelle','',NULL),
  (@org,'demo-002','D-2026-002',UNIX_TIMESTAMP(UTC_TIMESTAMP()-INTERVAL 3 DAY),'Technische Hilfeleistung',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 3 DAY,'%Y-%m-%dT%H:%i:%s.000Z'),'Wasser im Keller','Nordweg 12, Musterstadt',50.1102,8.6102,'Demo: Prüfung durch Einheitsführung','','Leitstelle','',NULL),
  (@org,'demo-003','D-2026-003',UNIX_TIMESTAMP(UTC_TIMESTAMP()-INTERVAL 5 DAY),'Ausgelöste Brandmeldeanlage',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 5 DAY,'%Y-%m-%dT%H:%i:%s.000Z'),'Brandmeldeanlage ausgelöst','Südallee 8, Musterstadt',50.0903,8.6203,'Demo: bei Wehrführung','','Automatische Meldung','',NULL),
  (@org,'demo-004','D-2026-004',UNIX_TIMESTAMP(UTC_TIMESTAMP()-INTERVAL 8 DAY),'Wohnungsbrand',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 8 DAY,'%Y-%m-%dT%H:%i:%s.000Z'),'Rauch aus Wohnung','Marktplatz 4, Musterstadt',50.1014,8.6044,'Demo: konsolidierter Einsatz','','Leitstelle','Brand auf Küche begrenzt; zwei Einheiten eingesetzt.',UTC_TIMESTAMP()-INTERVAL 7 DAY),
  (@org,'demo-005','D-2026-005',UNIX_TIMESTAMP(UTC_TIMESTAMP()-INTERVAL 12 DAY),'Scheunenbrand',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 12 DAY,'%Y-%m-%dT%H:%i:%s.000Z'),'Feuerschein an Scheune','Feldstraße 20, Musterstadt',50.1225,8.6335,'Demo: alle Einheiten','','Leitstelle','Umfassender Löschangriff aller drei Einheiten; Einsatzstelle an Eigentümer übergeben.',UTC_TIMESTAMP()-INTERVAL 11 DAY),
  (@org,'demo-006','D-2026-006',UNIX_TIMESTAMP(UTC_TIMESTAMP()-INTERVAL 16 DAY),'Verkehrsunfall',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 16 DAY,'%Y-%m-%dT%H:%i:%s.000Z'),'Zwei Fahrzeuge kollidiert','Landstraße 7, Musterstadt',50.1326,8.6446,'Demo: Rückgabe und erneute Übergabe','','Leitstelle','',NULL),
  (@org,'demo-007','D-2026-007',UNIX_TIMESTAMP(UTC_TIMESTAMP()-INTERVAL 20 DAY),'Sturmschaden',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 20 DAY,'%Y-%m-%dT%H:%i:%s.000Z'),'Ast blockiert Fahrbahn','Nordring 31, Musterstadt',50.1427,8.6557,'Demo: Bericht fehlt','','Bürgertelefon','',NULL),
  (@org,'demo-008','D-2026-008',UNIX_TIMESTAMP(UTC_TIMESTAMP()-INTERVAL 24 DAY),'Flächenbrand',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 24 DAY,'%Y-%m-%dT%H:%i:%s.000Z'),'Böschung brennt','Am Sportplatz, Musterstadt',50.1528,8.6668,'Demo: mehrere Einheiten, unvollständig','','Leitstelle','',NULL),
  (@org,'demo-009','D-2026-009',UNIX_TIMESTAMP(UTC_TIMESTAMP()-INTERVAL 29 DAY),'Tragehilfe Rettungsdienst',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 29 DAY,'%Y-%m-%dT%H:%i:%s.000Z'),'Unterstützung angefordert','Südweg 5, Musterstadt',50.0829,8.6779,'Demo: in Einheitsprüfung','','Rettungsdienst','',NULL),
  (@org,'demo-010','D-2026-010',UNIX_TIMESTAMP(UTC_TIMESTAMP()-INTERVAL 35 DAY),'Garagenbrand',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 35 DAY,'%Y-%m-%dT%H:%i:%s.000Z'),'Rauchentwicklung aus Garage','Gartenstraße 17, Musterstadt',50.0930,8.6890,'Demo: Berichte in verschiedenen Stufen','','Leitstelle','',NULL),
  (@org,'demo-011','D-2026-011',UNIX_TIMESTAMP(UTC_TIMESTAMP()-INTERVAL 42 DAY),'Ölspur',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 42 DAY,'%Y-%m-%dT%H:%i:%s.000Z'),'Öl auf Fahrbahn','Hauptstraße 42, Musterstadt',50.1031,8.6901,'Demo: noch ohne Bericht','','Polizei','',NULL),
  (@org,'demo-012','D-2026-012',UNIX_TIMESTAMP(UTC_TIMESTAMP()-INTERVAL 50 DAY),'Tierrettung',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 50 DAY,'%Y-%m-%dT%H:%i:%s.000Z'),'Tier in Notlage','Nordpark, Musterstadt',50.1132,8.6012,'Demo: bei Wehrführung','','Bürgertelefon','',NULL),
  (@org,'demo-013','D-2026-013',UNIX_TIMESTAMP(UTC_TIMESTAMP()-INTERVAL 61 DAY),'Unklare Rauchentwicklung',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 61 DAY,'%Y-%m-%dT%H:%i:%s.000Z'),'Rauch im Freien','Industrieweg 9, Musterstadt',50.1233,8.6123,'Demo: ein Bericht fehlt','','Leitstelle','',NULL),
  (@org,'demo-014','D-2026-014',UNIX_TIMESTAMP(UTC_TIMESTAMP()-INTERVAL 73 DAY),'Wasserschaden',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 73 DAY,'%Y-%m-%dT%H:%i:%s.000Z'),'Rohrbruch im Gebäude','Nordplatz 3, Musterstadt',50.1334,8.6234,'Demo: Entwurf','','Hausverwaltung','',NULL),
  (@org,'demo-015','D-2026-015',UNIX_TIMESTAMP(UTC_TIMESTAMP()-INTERVAL 88 DAY),'Brandnachschau',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 88 DAY,'%Y-%m-%dT%H:%i:%s.000Z'),'Kontrolle nach Kleinbrand','Mühlenweg 6, Musterstadt',50.1435,8.6345,'Demo: abgeschlossener Einheitsbericht','','Leitstelle','',NULL);

INSERT INTO incident_units(incident_id,unit_id,vehicles)
SELECT i.id,@mitte,JSON_ARRAY(
  JSON_OBJECT('id','demo-mitte-elw','name','ELW 1','own',TRUE),
  JSON_OBJECT('id','demo-mitte-hlf','name','HLF 20','own',TRUE),
  JSON_OBJECT('id','demo-mitte-dlk','name','DLK 23','own',TRUE)
) FROM incidents i WHERE i.organization_id=@org AND i.divera_id IN ('demo-001','demo-004','demo-005','demo-006','demo-008','demo-010','demo-011','demo-013','demo-015')
UNION ALL
SELECT i.id,@nord,JSON_ARRAY(
  JSON_OBJECT('id','demo-nord-lf','name','LF 10','own',TRUE),
  JSON_OBJECT('id','demo-nord-mtf','name','MTF Nord','own',TRUE)
) FROM incidents i WHERE i.organization_id=@org AND i.divera_id IN ('demo-002','demo-004','demo-005','demo-007','demo-008','demo-012','demo-014')
UNION ALL
SELECT i.id,@sued,JSON_ARRAY(
  JSON_OBJECT('id','demo-sued-tsf','name','TSF-W Süd','own',TRUE),
  JSON_OBJECT('id','demo-sued-gwl','name','GW-L Süd','own',TRUE),
  JSON_OBJECT('id','demo-sued-mtf','name','MTF Süd','own',TRUE)
) FROM incidents i WHERE i.organization_id=@org AND i.divera_id IN ('demo-003','demo-005','demo-009','demo-010','demo-013');

INSERT INTO reports(
  incident_id,unit_id,author_id,report_year,running_number,damaged_party,damaging_party,incident_command,narrative,
  vehicles,personnel,alarmed_at,departed_at,arrived_at,ended_at,incident_type,classification,status,created_at,released_at
)
SELECT
  i.id,d.unit_id,d.author_id,YEAR(UTC_DATE()),d.running_number,JSON_OBJECT(),JSON_OBJECT(),
  JSON_OBJECT('rank','BI','name',d.command_name,'additionalRank','BM','additionalName',d.command_name),
  d.narrative,'','',i.started_at,
  DATE_FORMAT(STR_TO_DATE(i.started_at,'%Y-%m-%dT%H:%i:%s.000Z')+INTERVAL 8 MINUTE,'%Y-%m-%dT%H:%i:%s.000Z'),
  DATE_FORMAT(STR_TO_DATE(i.started_at,'%Y-%m-%dT%H:%i:%s.000Z')+INTERVAL 15 MINUTE,'%Y-%m-%dT%H:%i:%s.000Z'),
  DATE_FORMAT(STR_TO_DATE(i.started_at,'%Y-%m-%dT%H:%i:%s.000Z')+INTERVAL 90 MINUTE,'%Y-%m-%dT%H:%i:%s.000Z'),
  d.incident_type,JSON_OBJECT('site',JSON_ARRAY(d.classification),'cause',JSON_ARRAY(),'technical',JSON_ARRAY()),d.status,
  STR_TO_DATE(i.started_at,'%Y-%m-%dT%H:%i:%s.000Z')+INTERVAL 2 HOUR,
  IF(d.status='wehr_review',STR_TO_DATE(i.started_at,'%Y-%m-%dT%H:%i:%s.000Z')+INTERVAL 5 HOUR,NULL)
FROM incidents i
JOIN (
  SELECT 'demo-001' incident_key,@mitte unit_id,@fuehrung_mitte author_id,'1/2026' running_number,'Der Kleinbrand wurde mit einem Kleinlöschgerät abgelöscht. Nachkontrolle ohne Feststellung.' narrative,'Brandeinsatz' incident_type,'Brand im Freien' classification,'author_draft' status,'Martin Berger' command_name
  UNION ALL SELECT 'demo-002',@nord,@fuehrung_nord,'1/2026','Das Wasser wurde mit einer Tauchpumpe aus dem Keller entfernt.','Technische Hilfe','Wasserschaden','unit_review','Nora Hansen'
  UNION ALL SELECT 'demo-003',@sued,@fuehrung_sued,'1/2026','Die Anlage wurde kontrolliert. Ursache war Wasserdampf; kein Feuer feststellbar.','Brandeinsatz','Brandmeldeanlage','wehr_review','Stefan Krüger'
  UNION ALL SELECT 'demo-004',@mitte,@fuehrung_mitte,'2/2026','Ein Trupp ging unter Atemschutz zur Brandbekämpfung vor. Die Wohnung wurde belüftet.','Brandeinsatz','Wohngebäude','wehr_review','Martin Berger'
  UNION ALL SELECT 'demo-004',@nord,@fuehrung_nord,'2/2026','Die Einheit stellte die Wasserversorgung her und kontrollierte die Nachbarwohnung.','Brandeinsatz','Wohngebäude','wehr_review','Nora Hansen'
  UNION ALL SELECT 'demo-005',@mitte,@fuehrung_springer,'3/2026','Brandbekämpfung über den Innenhof und Koordination der Einsatzabschnitte.','Brandeinsatz','Landwirtschaftliches Gebäude','wehr_review','Martin Berger'
  UNION ALL SELECT 'demo-005',@nord,@fuehrung_nord,'3/2026','Aufbau einer unabhängigen Wasserversorgung und Riegelstellung an der Nordseite.','Brandeinsatz','Landwirtschaftliches Gebäude','wehr_review','Nora Hansen'
  UNION ALL SELECT 'demo-005',@sued,@fuehrung_sued,'2/2026','Ausleuchten der Einsatzstelle und Unterstützung bei den Nachlöscharbeiten.','Brandeinsatz','Landwirtschaftliches Gebäude','wehr_review','Stefan Krüger'
  UNION ALL SELECT 'demo-006',@mitte,@fuehrung_mitte,'4/2026','Die Einsatzstelle wurde abgesichert, auslaufende Betriebsstoffe wurden aufgenommen.','Technische Hilfe','Verkehrsfläche','wehr_review','Martin Berger'
  UNION ALL SELECT 'demo-008',@mitte,@fuehrung_springer,'5/2026','Die Böschung wurde mit zwei Rohren abgelöscht und abschließend gewässert.','Brandeinsatz','Brand im Freien','author_draft','Martin Berger'
  UNION ALL SELECT 'demo-009',@sued,@fuehrung_sued,'3/2026','Der Rettungsdienst wurde beim schonenden Transport aus dem Obergeschoss unterstützt.','Technische Hilfe','Menschen in Notlage','unit_review','Stefan Krüger'
  UNION ALL SELECT 'demo-010',@mitte,@fuehrung_mitte,'6/2026','Ein Trupp löschte den Entstehungsbrand in der Garage.','Brandeinsatz','Nebengebäude','wehr_review','Martin Berger'
  UNION ALL SELECT 'demo-010',@sued,@fuehrung_sued,'4/2026','Die Einheit stellte den Sicherheitstrupp und belüftete das Gebäude.','Brandeinsatz','Nebengebäude','unit_review','Stefan Krüger'
  UNION ALL SELECT 'demo-012',@nord,@fuehrung_nord,'4/2026','Das Tier wurde aus der Umzäunung befreit und unverletzt übergeben.','Technische Hilfe','Tierrettung','wehr_review','Nora Hansen'
  UNION ALL SELECT 'demo-013',@mitte,@fuehrung_mitte,'7/2026','Die Rauchentwicklung stammte aus einer genehmigten Feuerstelle.','Erkundung','Brand im Freien','unit_review','Martin Berger'
  UNION ALL SELECT 'demo-014',@nord,@fuehrung_nord,'5/2026','Die Wasserzufuhr wurde abgestellt und das ausgetretene Wasser aufgenommen.','Technische Hilfe','Wasserschaden','author_draft','Nora Hansen'
  UNION ALL SELECT 'demo-015',@mitte,@fuehrung_mitte,'8/2026','Die Brandstelle wurde mit der Wärmebildkamera kontrolliert. Keine Glutnester vorhanden.','Brandeinsatz','Wohngebäude','wehr_review','Martin Berger'
) d ON d.incident_key=i.divera_id
WHERE i.organization_id=@org;

INSERT INTO report_crew(report_id,member_id,vehicle,role)
SELECT r.id,c.member_id,
  CASE
    WHEN r.unit_id=@mitte THEN IF(c.position<=2,'HLF 20','DLK 23')
    WHEN r.unit_id=@nord THEN IF(c.position<=2,'LF 10','MTF Nord')
    ELSE IF(c.position<=2,'TSF-W Süd','GW-L Süd')
  END,
  CASE c.position WHEN 1 THEN 'einheitsfuehrer' WHEN 2 THEN 'maschinist' ELSE 'besatzung' END
FROM reports r
JOIN incidents i ON i.id=r.incident_id
JOIN (
  SELECT mu.unit_id,m.id member_id,ROW_NUMBER() OVER(PARTITION BY mu.unit_id ORDER BY m.divera_id) position
  FROM members m JOIN member_units mu ON mu.member_id=m.id
  WHERE m.organization_id=@org
) c ON c.unit_id=r.unit_id AND c.position<=4
WHERE i.organization_id=@org;

INSERT INTO report_transitions(report_id,from_status,to_status,actor_id,actor_name,actor_role,comment,created_at)
SELECT r.id,NULL,'author_draft',r.author_id,u.name,'fuehrungskraft','',r.created_at
FROM reports r JOIN incidents i ON i.id=r.incident_id JOIN users u ON u.id=r.author_id
WHERE i.organization_id=@org;

INSERT INTO report_transitions(report_id,from_status,to_status,actor_id,actor_name,actor_role,comment,created_at)
SELECT r.id,'author_draft','unit_review',r.author_id,u.name,'fuehrungskraft','',r.created_at+INTERVAL 1 HOUR
FROM reports r JOIN incidents i ON i.id=r.incident_id JOIN users u ON u.id=r.author_id
WHERE i.organization_id=@org AND r.status IN ('unit_review','wehr_review');

INSERT INTO report_transitions(report_id,from_status,to_status,actor_id,actor_name,actor_role,comment,created_at)
SELECT r.id,'unit_review','wehr_review',l.id,l.name,'einheitsleitung','',r.created_at+INTERVAL 2 HOUR
FROM reports r
JOIN incidents i ON i.id=r.incident_id
JOIN users l ON l.id=CASE r.unit_id WHEN @mitte THEN @leitung_mitte WHEN @nord THEN @leitung_nord ELSE @leitung_sued END
WHERE i.organization_id=@org AND r.status='wehr_review';

INSERT INTO report_transitions(report_id,from_status,to_status,actor_id,actor_name,actor_role,comment,created_at)
SELECT r.id,'wehr_review','unit_review',@wehr,'Alexandra Brandt','wehrleitung','Bitte Fahrzeugaufstellung ergänzen.',r.created_at+INTERVAL 3 HOUR
FROM reports r JOIN incidents i ON i.id=r.incident_id
WHERE i.organization_id=@org AND i.divera_id='demo-006';

INSERT INTO report_transitions(report_id,from_status,to_status,actor_id,actor_name,actor_role,comment,created_at)
SELECT r.id,'unit_review','wehr_review',@leitung_mitte,'Martin Berger','einheitsleitung','',r.created_at+INTERVAL 4 HOUR
FROM reports r JOIN incidents i ON i.id=r.incident_id
WHERE i.organization_id=@org AND i.divera_id='demo-006';

COMMIT;

SELECT CONCAT_WS('|',
  (SELECT COUNT(*) FROM units u WHERE u.organization_id=o.id),
  (SELECT COUNT(*) FROM users u WHERE u.organization_id=o.id),
  (SELECT COUNT(*) FROM members m WHERE m.organization_id=o.id),
  (SELECT COUNT(*) FROM vehicles v JOIN units u ON u.id=v.unit_id WHERE u.organization_id=o.id),
  (SELECT COUNT(*) FROM incidents i WHERE i.organization_id=o.id),
  (SELECT COUNT(*) FROM reports r JOIN incidents i ON i.id=r.incident_id WHERE i.organization_id=o.id),
  (SELECT COUNT(DISTINCT u.role) FROM users u WHERE u.organization_id=o.id),
  (SELECT COUNT(DISTINCT r.status) FROM reports r JOIN incidents i ON i.id=r.incident_id WHERE i.organization_id=o.id),
  (SELECT COUNT(*) FROM incidents i WHERE i.organization_id=o.id AND i.consolidated_at IS NOT NULL),
  (SELECT COUNT(*) FROM report_transitions rt JOIN reports r ON r.id=rt.report_id JOIN incidents i ON i.id=r.incident_id
    WHERE i.organization_id=o.id AND rt.from_status='wehr_review' AND rt.to_status='unit_review')
) FROM organizations o WHERE o.name=@demo_name;
