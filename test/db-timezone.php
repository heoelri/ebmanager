<?php
declare(strict_types=1);

require __DIR__ . '/../support.php';

assert(one('SELECT @@session.time_zone AS zone')['zone'] === '+00:00');
$suffix = bin2hex(random_bytes(6));
$organizationId = $unitId = $userId = $incidentId = null;
try {
    query('INSERT INTO organizations(name) VALUES(?)', ["UTC-Test $suffix"]);
    $organizationId = (int)db()->lastInsertId();
    query('INSERT INTO units(organization_id,name) VALUES(?,?)', [$organizationId, "UTC-Einheit $suffix"]);
    $unitId = (int)db()->lastInsertId();
    query(
        "INSERT INTO users(organization_id,name,email,password_hash,role) VALUES(?,?,?,?, 'wehrleitung')",
        [$organizationId, 'UTC-Test', "$suffix@example.test", 'x']
    );
    $userId = (int)db()->lastInsertId();
    query(
        'INSERT INTO password_resets(user_id,token_hash,expires_at) VALUES(?,?,UTC_TIMESTAMP()+INTERVAL 30 MINUTE)',
        [$userId, hash('sha256', "UTC-Reset $suffix")]
    );
    $resetTime = one(
        'SELECT ABS(TIMESTAMPDIFF(SECOND,requested_at,UTC_TIMESTAMP())) requested_delta,
                requested_at>UTC_TIMESTAMP()-INTERVAL 5 MINUTE recent
         FROM password_resets WHERE user_id=?',
        [$userId]
    );
    assert((int)$resetTime['requested_delta'] <= 5);
    assert((int)$resetTime['recent'] === 1);
    query('UPDATE password_resets SET requested_at=UTC_TIMESTAMP()-INTERVAL 5 MINUTE WHERE user_id=?', [$userId]);
    assert((int)one(
        'SELECT requested_at>UTC_TIMESTAMP()-INTERVAL 5 MINUTE recent FROM password_resets WHERE user_id=?',
        [$userId]
    )['recent'] === 0);
    query(
        "INSERT INTO incidents(organization_id,title,started_at,address,message,remark,patient,caller,consolidated_text)
         VALUES(?,?,'2026-01-01T00:00:00.000Z','','','','','','')",
        [$organizationId, "UTC-Einsatz $suffix"]
    );
    $incidentId = (int)db()->lastInsertId();
    query('INSERT INTO incident_units(incident_id,unit_id,vehicles) VALUES(?,?,JSON_ARRAY())', [$incidentId, $unitId]);
    query(
        "INSERT INTO reports(incident_id,unit_id,author_id,author_name,narrative,vehicles,personnel,classification)
         VALUES(?,?,?,'UTC-Test','','','',JSON_OBJECT())",
        [$incidentId, $unitId, $userId]
    );
    $reportId = (int)db()->lastInsertId();
    query("UPDATE reports SET narrative='geändert' WHERE id=?", [$reportId]);
    $times = one(
        'SELECT ABS(TIMESTAMPDIFF(SECOND,created_at,UTC_TIMESTAMP())) created_delta,
                ABS(TIMESTAMPDIFF(SECOND,updated_at,UTC_TIMESTAMP())) updated_delta
         FROM reports WHERE id=?',
        [$reportId]
    );
    assert((int)$times['created_delta'] <= 5);
    assert((int)$times['updated_delta'] <= 5);
} finally {
    if ($incidentId) query('DELETE FROM incidents WHERE id=?', [$incidentId]);
    if ($userId) query('DELETE FROM users WHERE id=?', [$userId]);
    if ($unitId) query('DELETE FROM units WHERE id=?', [$unitId]);
    if ($organizationId) query('DELETE FROM organizations WHERE id=?', [$organizationId]);
}
