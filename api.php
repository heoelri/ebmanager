<?php
declare(strict_types=1);

require __DIR__ . '/support.php';
require __DIR__ . '/constants.php';

function databaseConfigurationError(): ?string
{
    if (empty(config()['dsn'])) return 'Datenbankzugang ist nicht konfiguriert. Prüfen Sie DB_DSN oder config.local.php.';
    try {
        $tables = db()->query(
            "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name IN
             ('organizations','units','users','user_units','sessions','login_history','password_resets','incidents','incident_units',
              'divera_imports','members','member_units','qualifications','member_qualifications','vehicles','reports','report_transitions','report_crew')"
        )->fetchColumn();
        if ((int)$tables !== 18) return 'Datenbankschema ist unvollständig. Importieren Sie schema.sql und alle ausstehenden Migrationen.';
        $reportColumns = db()->query(
            "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='reports'
             AND column_name IN ('report_year','running_number','damaged_party','damaging_party','incident_command')"
        )->fetchColumn();
        if ((int)$reportColumns !== 5) return 'Datenbankschema ist unvollständig. Importieren Sie schema.sql und alle ausstehenden Migrationen.';
    } catch (PDOException $error) {
        error_log((string)$error);
        return 'Datenbankverbindung fehlgeschlagen. Prüfen Sie DSN, Benutzername, Passwort und Erreichbarkeit.';
    }
    return null;
}

function sendPasswordEmail(array $user, string $token, bool $invitation = false, ?DateTimeImmutable $expiresAt = null): bool
{
    $settings = mailSettings();
    ['url' => $url] = $settings;
    $link = "$url/#" . ($invitation ? 'invite' : 'reset') . "=$token";
    $subject = $invitation ? 'Konto aktivieren' : 'Passwort zuruecksetzen';
    $expiry = $expiresAt?->setTimezone(new DateTimeZone('Europe/Berlin'))->format('d.m.Y \u\m H:i \U\h\r');
    $message = $invitation
        ? "Hallo {$user['name']},\n\nüber diesen Link können Sie Ihr Konto aktivieren und ein Passwort vergeben:\n$link\n\nDer Link ist bis zum $expiry (Europe/Berlin) gültig. Nach Ablauf können Sie über „Passwort vergessen“ einen neuen Link anfordern."
        : "Hallo {$user['name']},\n\nüber diesen Link können Sie innerhalb von 30 Minuten ein neues Passwort vergeben:\n$link\n\nFalls Sie dies nicht angefordert haben, ignorieren Sie diese Nachricht.";
    return sendEmail($settings, $user['email'], $subject, $message);
}

function sendWorkflowNotification(string $event, int $incidentId, array $unitIds, array $actor, ?int $recipientId = null, string $comment = ''): ?string
{
    $events = [
        'incident_created' => ['subject' => 'Neuer Einsatz', 'label' => 'Einsatz wurde manuell angelegt', 'role' => 'einheitsleitung'],
        'incident_imported' => ['subject' => 'Neuer DIVERA-Einsatz', 'label' => 'DIVERA-Einsatz wurde erstmals importiert', 'role' => 'einheitsleitung'],
        'report_submitted_unit' => ['subject' => 'Einsatzbericht eingereicht', 'label' => 'Führungskraft hat einen Einsatzbericht zur Prüfung eingereicht', 'role' => 'einheitsleitung'],
        'report_returned_author' => ['subject' => 'Einsatzbericht zurückgegeben', 'label' => 'Einheitsführung hat einen Einsatzbericht zur Überarbeitung zurückgegeben', 'role' => 'author'],
        'report_submitted_command' => ['subject' => 'Einsatzbericht geprüft', 'label' => 'Einheitsführung hat einen Einsatzbericht an die Wehrführung gesendet', 'role' => 'wehrleitung'],
        'report_returned_unit' => ['subject' => 'Einsatzbericht zurückgegeben', 'label' => 'Wehrführung hat einen Einsatzbericht zur Überarbeitung zurückgegeben', 'role' => 'einheitsleitung'],
    ];
    if (!isset($events[$event])) throw new LogicException('Unbekanntes Benachrichtigungsereignis');

    try {
        $incident = one('SELECT * FROM incidents WHERE id=? AND organization_id=?', [$incidentId, $actor['organization_id']]);
        if (!$incident) throw new RuntimeException('Einsatz nicht gefunden');
        $placeholders = implode(',', array_fill(0, count($unitIds), '?'));
        $unitNames = query(
            "SELECT name FROM units WHERE organization_id=? AND id IN ($placeholders) ORDER BY name",
            array_merge([$actor['organization_id']], $unitIds)
        )->fetchAll(PDO::FETCH_COLUMN);
        $eventDetails = $events[$event];
        if ($recipientId !== null) {
            $recipients = query(
                'SELECT id,name,email FROM users WHERE id=? AND organization_id=?',
                [$recipientId, $actor['organization_id']]
            )->fetchAll();
        } elseif ($eventDetails['role'] === 'einheitsleitung') {
            $recipients = query(
                "SELECT u.id,u.name,u.email,GROUP_CONCAT(DISTINCT un.name ORDER BY un.name SEPARATOR ', ') unit_names
                 FROM users u JOIN user_units uu ON uu.user_id=u.id JOIN units un ON un.id=uu.unit_id
                 WHERE u.organization_id=? AND u.role='einheitsleitung' AND u.id<>? AND uu.unit_id IN ($placeholders)
                 GROUP BY u.id,u.name,u.email ORDER BY u.id",
                array_merge([$actor['organization_id'], $actor['id']], $unitIds)
            )->fetchAll();
        } else {
            $recipients = query(
                "SELECT id,name,email FROM users
                 WHERE organization_id=? AND role='wehrleitung' AND id<>? ORDER BY id",
                [$actor['organization_id'], $actor['id']]
            )->fetchAll();
        }
        if (!$recipients) return null;

        $settings = mailSettings();
        $number = trim((string)($incident['foreign_id'] ?: ($incident['divera_id'] ?: $incident['id'])));
        $when = (new DateTimeImmutable($incident['started_at']))
            ->setTimezone(new DateTimeZone('Europe/Berlin'))
            ->format('d.m.Y H:i');
        $failed = 0;
        foreach ($recipients as $recipient) {
            $recipientUnits = $recipient['unit_names'] ?? implode(', ', $unitNames);
            $message = "Hallo {$recipient['name']},\n\n"
                . "{$eventDetails['label']}.\n\n"
                . "Feuerwehr: {$actor['organization_name']}\n"
                . "Einheit: $recipientUnits\n"
                . "Einsatznummer: $number\n"
                . "Stichwort: {$incident['title']}\n"
                . "Datum und Uhrzeit: $when Uhr (Europe/Berlin)\n"
                . "Ereignis: {$eventDetails['label']}\n"
                . "Ausgelöst durch: {$actor['name']}\n"
                . ($comment !== '' ? "Kommentar: $comment\n" : '')
                . "Link: {$settings['url']}/?incident=$incidentId";
            try {
                if (sendEmail($settings, $recipient['email'], $eventDetails['subject'], $message)) continue;
                $reason = 'Transport hat die Nachricht abgelehnt';
            } catch (Throwable $error) {
                $reason = $error::class;
            }
            $failed++;
            error_log("Benachrichtigung fehlgeschlagen: event=$event incident_id=$incidentId error=$reason");
        }
        if (!$failed) return null;
        return $failed === 1
            ? 'Der Vorgang wurde gespeichert, aber eine Benachrichtigungs-E-Mail konnte nicht versendet werden.'
            : "Der Vorgang wurde gespeichert, aber $failed Benachrichtigungs-E-Mails konnten nicht versendet werden.";
    } catch (Throwable $error) {
        error_log("Benachrichtigung fehlgeschlagen: event=$event incident_id=$incidentId error=" . $error::class);
        return 'Der Vorgang wurde gespeichert, aber die Benachrichtigungs-E-Mails konnten nicht versendet werden.';
    }
}

function isoDate(mixed $value): string
{
    if ($value === null || $value === '') throw new ApiError(502, 'DIVERA-Zeitpunkt fehlt');
    try {
        if (is_numeric($value)) $date = new DateTimeImmutable('@' . (int)$value);
        else $date = new DateTimeImmutable((string)$value);
        return $date->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d\TH:i:s.v\Z');
    } catch (Throwable) {
        throw new ApiError(502, 'DIVERA-Zeitpunkt ist ungültig');
    }
}

function requestDate(mixed $value, string $name): DateTimeImmutable
{
    $text = required($value, $name, 100);
    $date = DateTimeImmutable::createFromFormat('!Y-m-d\TH:i:s.v\Z', $text, new DateTimeZone('UTC'));
    $errors = DateTimeImmutable::getLastErrors();
    if (!$date || ($errors && ($errors['warning_count'] || $errors['error_count']))) throw new ApiError(400, "$name ist ungültig");
    return $date;
}

function utcString(?DateTimeImmutable $date): ?string
{
    return $date?->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d\TH:i:s.v\Z');
}

function unit(int $id, int $organizationId): ?array
{
    return one('SELECT * FROM units WHERE id=? AND organization_id=?', [$id, $organizationId]);
}

function incident(int $id, int $organizationId): ?array
{
    return one('SELECT * FROM incidents WHERE id=? AND organization_id=?', [$id, $organizationId]);
}

function report(int $id, int $organizationId): ?array
{
    return one('SELECT r.* FROM reports r JOIN incidents i ON i.id=r.incident_id WHERE r.id=? AND i.organization_id=?', [$id, $organizationId]);
}

function currentUser(): ?array
{
    $token = $_COOKIE[sessionCookieName()] ?? '';
    if (!preg_match('/^[a-f0-9]{64}$/', $token)) return null;
    $user = one(
        'SELECT u.*,o.name organization_name FROM sessions s
         JOIN users u ON u.id=s.user_id JOIN organizations o ON o.id=u.organization_id
         WHERE s.token=? AND s.expires_at>UTC_TIMESTAMP()',
        [hash('sha256', $token)]
    );
    if (!$user) return null;
    $user['unitIds'] = array_map('intval', query('SELECT unit_id FROM user_units WHERE user_id=?', [$user['id']])->fetchAll(PDO::FETCH_COLUMN));
    foreach (['id', 'organization_id', 'unit_id'] as $key) if ($user[$key] !== null) $user[$key] = (int)$user[$key];
    return $user;
}

function assertRole(array $user, string ...$roles): void
{
    if (!in_array($user['role'], $roles, true)) throw new ApiError(403, 'Keine Berechtigung');
}

function assertOwnUnit(array $user, int $unitId): void
{
    // Wehrleitung is organization-wide; unit lookups still enforce tenant ownership.
    if ($user['role'] !== 'wehrleitung' && !in_array($unitId, $user['unitIds'], true)) {
        throw new ApiError(403, 'Keine Berechtigung für diese Einheit');
    }
}

function membershipIds(array $data, int $organizationId): array
{
    $source = is_array($data['unitIds'] ?? null) ? $data['unitIds'] : (isset($data['unitId']) ? [$data['unitId']] : []);
    $ids = array_values(array_unique(array_map('intval', $source)));
    $role = $data['role'] ?? '';
    if ($role === 'wehrleitung') return [];
    if ($role === 'einheitsleitung' && count($ids) !== 1) throw new ApiError(400, 'Für die Einheitsführung ist genau eine Einheit erforderlich');
    if ($role === 'fuehrungskraft' && !$ids) throw new ApiError(400, 'Für diese Rolle ist mindestens eine Einheit erforderlich');
    foreach ($ids as $id) if ($id < 1 || !unit($id, $organizationId)) throw new ApiError(404, 'Einheit nicht gefunden');
    return $ids;
}

function replaceMemberships(int $userId, array $unitIds): void
{
    query('DELETE FROM user_units WHERE user_id=?', [$userId]);
    foreach ($unitIds as $unitId) query('INSERT INTO user_units(user_id,unit_id) VALUES(?,?)', [$userId, $unitId]);
}

function unitMembers(int $unitId, int $organizationId, bool $activeOnly = true): array
{
    $active = $activeOnly ? ' AND mu.active=1' : '';
    $rows = query(
        "SELECT m.id,m.name,m.divera_id,mu.active,
         COALESCE(GROUP_CONCAT(DISTINCT COALESCE(NULLIF(q.shortname,''),q.name) ORDER BY q.name SEPARATOR ', '),'') qualifications
         FROM members m JOIN member_units mu ON mu.member_id=m.id
         LEFT JOIN member_qualifications mq ON mq.member_id=m.id
         LEFT JOIN qualifications q ON q.id=mq.qualification_id AND q.unit_id=mu.unit_id
         WHERE mu.unit_id=? AND m.organization_id=?$active GROUP BY m.id,m.name,m.divera_id,mu.active ORDER BY m.name",
        [$unitId, $organizationId]
    )->fetchAll();
    foreach ($rows as &$row) { $row['id'] = (int)$row['id']; $row['active'] = (int)$row['active']; }
    return $rows;
}

function reportStatusForRole(string $role): string
{
    return match ($role) {
        'wehrleitung' => 'wehr_review',
        'einheitsleitung' => 'unit_review',
        default => 'author_draft',
    };
}

function canEditReport(array $report, array $user): bool
{
    if ($report['status'] === 'author_draft') {
        return $user['role'] === 'fuehrungskraft'
            && (int)$report['author_id'] === (int)$user['id']
            && in_array((int)$report['unit_id'], $user['unitIds'], true);
    }
    return $report['status'] === 'unit_review'
        && $user['role'] === 'einheitsleitung'
        && in_array((int)$report['unit_id'], $user['unitIds'], true);
}

function reportVisibilitySql(array $user, string $alias = 'r'): array
{
    if ($user['role'] === 'wehrleitung') {
        return ["EXISTS(SELECT 1 FROM report_transitions rt WHERE rt.report_id=$alias.id AND rt.to_status='wehr_review')", []];
    }
    if ($user['role'] === 'einheitsleitung') {
        return [
            "EXISTS(SELECT 1 FROM user_units uu WHERE uu.user_id=? AND uu.unit_id=$alias.unit_id)
             AND EXISTS(SELECT 1 FROM report_transitions rt WHERE rt.report_id=$alias.id AND rt.to_status='unit_review')",
            [$user['id']]
        ];
    }
    return [
        "$alias.author_id=? AND EXISTS(SELECT 1 FROM user_units uu WHERE uu.user_id=? AND uu.unit_id=$alias.unit_id)",
        [$user['id'], $user['id']]
    ];
}

function visibleIncident(int $incidentId, array $user): ?array
{
    if ($user['role'] === 'wehrleitung') {
        return one('SELECT * FROM incidents WHERE id=? AND organization_id=?', [$incidentId, $user['organization_id']]);
    }
    return one(
        'SELECT i.* FROM incidents i WHERE i.id=? AND i.organization_id=?
         AND EXISTS(SELECT 1 FROM incident_units iu JOIN user_units uu ON uu.unit_id=iu.unit_id WHERE iu.incident_id=i.id AND uu.user_id=?)',
        [$incidentId, $user['organization_id'], $user['id']]
    );
}

function visibleIncidentReports(int $incidentId, array $user): array
{
    [$visibility, $visibilityParams] = reportVisibilitySql($user);
    $where = " AND $visibility";
    $params = array_merge([$incidentId, $user['organization_id']], $visibilityParams);
    $rows = query(
        "SELECT r.*,u.name author_name,un.name unit_name FROM reports r
         JOIN incidents i ON i.id=r.incident_id
         JOIN users u ON u.id=r.author_id AND u.organization_id=i.organization_id
         JOIN units un ON un.id=r.unit_id AND un.organization_id=i.organization_id
         WHERE r.incident_id=? AND i.organization_id=?$where ORDER BY r.created_at",
        $params
    )->fetchAll();
    $crew = [];
    foreach (query(
        "SELECT rc.report_id reportId,rc.member_id memberId,m.name,rc.vehicle,rc.role
         FROM report_crew rc JOIN members m ON m.id=rc.member_id JOIN reports r ON r.id=rc.report_id
         JOIN incidents i ON i.id=r.incident_id AND m.organization_id=i.organization_id
         WHERE r.incident_id=? AND i.organization_id=?$where ORDER BY rc.report_id,rc.member_id",
        $params
    )->fetchAll() as $person) {
        $reportId = (int)$person['reportId'];
        unset($person['reportId']);
        $person['memberId'] = (int)$person['memberId'];
        $crew[$reportId][] = $person;
    }
    $history = [];
    if ($rows) {
        $ids = array_map(fn($row) => (int)$row['id'], $rows);
        $placeholders = implode(',', array_fill(0, count($ids), '?'));
        foreach (query(
            "SELECT report_id,from_status,to_status,actor_name,actor_role,comment,
             DATE_FORMAT(created_at,'%Y-%m-%dT%H:%i:%sZ') created_at
             FROM report_transitions WHERE report_id IN ($placeholders) ORDER BY created_at,id",
            $ids
        )->fetchAll() as $transition) {
            $history[(int)$transition['report_id']][] = $transition;
        }
    }
    foreach ($rows as &$row) {
        $row['crew'] = json_encode($crew[(int)$row['id']] ?? [], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
        $row['history'] = $history[(int)$row['id']] ?? [];
        $row['editable'] = canEditReport($row, $user);
        $row['duration_minutes'] = $row['ended_at'] && $row['alarmed_at']
            ? (int)round((strtotime($row['ended_at']) - strtotime($row['alarmed_at'])) / 60)
            : null;
        foreach (['id', 'incident_id', 'unit_id', 'author_id', 'report_year'] as $key) if ($row[$key] !== null) $row[$key] = (int)$row[$key];
    }
    return $rows;
}

function exportDateTime(mixed $value): string
{
    if (!$value) return '–';
    try {
        return (new DateTimeImmutable((string)$value, new DateTimeZone('UTC')))->setTimezone(new DateTimeZone('Europe/Berlin'))->format('d.m.Y H:i') . ' Uhr';
    } catch (Throwable) {
        return (string)$value;
    }
}

function exportJson(mixed $value): array
{
    if (is_array($value)) return $value;
    return json_decode((string)($value ?: '{}'), true, 512, JSON_THROW_ON_ERROR);
}

function exportLine(array &$lines, string $text = '', bool $bold = false): void
{
    $lines[] = compact('text', 'bold');
}

function incidentExportLines(array $incident, array $user): array
{
    $where = $user['role'] === 'wehrleitung'
        ? ''
        : ' AND EXISTS(SELECT 1 FROM user_units uu WHERE uu.user_id=? AND uu.unit_id=iu.unit_id)';
    $params = [$incident['organization_id'], $incident['id']];
    if ($user['role'] !== 'wehrleitung') $params[] = $user['id'];
    $assignments = query(
        "SELECT u.name,iu.vehicles FROM incident_units iu JOIN units u ON u.id=iu.unit_id AND u.organization_id=?
         WHERE iu.incident_id=?$where ORDER BY u.name",
        $params
    )->fetchAll();
    $lines = [];
    exportLine($lines, 'Einsatzdaten', true);
    exportLine($lines, 'Feuerwehr: ' . one('SELECT name FROM organizations WHERE id=?', [$incident['organization_id']])['name']);
    exportLine($lines, 'Einsatz: ' . $incident['title']);
    exportLine($lines, 'Einsatznummer: ' . ($incident['foreign_id'] ?: ($incident['divera_id'] ?: $incident['id'])));
    exportLine($lines, 'Zeitpunkt: ' . exportDateTime($incident['started_at']) . ' (Europe/Berlin)');
    exportLine($lines, 'Adresse: ' . ($incident['address'] ?: '–'));
    exportLine($lines, 'Alarmierte Einheiten: ' . (implode(', ', array_column($assignments, 'name')) ?: '–'));
    foreach (['message' => 'Meldung', 'remark' => 'Bemerkung', 'patient' => 'Patient', 'caller' => 'Meldende Person'] as $key => $label) {
        if ($incident[$key] !== '') exportLine($lines, "$label: {$incident[$key]}");
    }
    $vehicles = [];
    foreach ($assignments as $assignment) foreach (exportJson($assignment['vehicles']) as $vehicle) {
        $vehicles[] = is_string($vehicle) ? $vehicle : $vehicle['name'] . (($vehicle['own'] ?? true) ? ' (eigene Einheit)' : ' (andere Einheit)');
    }
    exportLine($lines, 'Fahrzeuge beim Import: ' . ($vehicles ? implode(', ', $vehicles) : 'Keine Fahrzeuge'));
    exportLine($lines);
    return $lines;
}

function reportExportLines(array $report): array
{
    $statusLabels = ['author_draft' => 'Entwurf der Führungskraft', 'unit_review' => 'Prüfung durch Einheitsführung', 'wehr_review' => 'Prüfung durch Wehrführung'];
    $roleLabels = ['fuehrungskraft' => 'Führungskraft', 'einheitsleitung' => 'Einheitsführung', 'wehrleitung' => 'Wehrführung'];
    $crewRoleLabels = ['einheitsfuehrer' => 'Einheitsführer', 'maschinist' => 'Maschinist', 'besatzung' => 'Besatzung', 'mannschaft' => 'Besatzung'];
    $lines = [];
    exportLine($lines, 'Einzelbericht ' . $report['unit_name'] . ' – Nr. ' . ($report['running_number'] ?: '–'), true);
    exportLine($lines, 'Autor: ' . $report['author_name']);
    exportLine($lines, 'Status: ' . ($statusLabels[$report['status']] ?? $report['status']));
    exportLine($lines, 'Einsatzart: ' . ($report['incident_type'] ?: '–'));
    exportLine($lines, 'Alarmiert: ' . exportDateTime($report['alarmed_at']));
    exportLine($lines, 'Ausgerückt: ' . exportDateTime($report['departed_at']));
    exportLine($lines, 'Eingetroffen: ' . exportDateTime($report['arrived_at']));
    exportLine($lines, 'Beendet: ' . exportDateTime($report['ended_at']));
    exportLine($lines, 'Dauer: ' . ($report['duration_minutes'] === null ? '–' : intdiv($report['duration_minutes'], 60) . ' Std. ' . ($report['duration_minutes'] % 60) . ' Min.'));
    $command = exportJson($report['incident_command']);
    foreach ([
        'Gesamteinsatzleitung' => [$command['rank'] ?? '', $command['name'] ?? ''],
        'Einsatzleitung der Einheit' => [$command['additionalRank'] ?? '', $command['additionalName'] ?? '']
    ] as $label => $person) {
        if (array_filter($person)) exportLine($lines, "$label: " . implode(' ', array_filter($person)));
    }
    foreach (['damaged_party' => 'Geschädigte Person', 'damaging_party' => 'Schädiger'] as $key => $label) {
        $contact = array_filter(exportJson($report[$key]));
        if ($contact) exportLine($lines, "$label: " . implode(' | ', $contact));
    }
    foreach (exportJson($report['classification']) as $group => $values) {
        if ($values) exportLine($lines, (CLASSIFICATION_LABELS[$group] ?? $group) . ': ' . implode(', ', $values));
    }
    exportLine($lines, 'Fahrzeuge: ' . ($report['vehicles'] ?: '–'));
    exportLine($lines, 'Personal: ' . ($report['personnel'] ?: '–'));
    exportLine($lines, 'Besatzung', true);
    $crew = exportJson($report['crew']);
    if (!$crew) exportLine($lines, 'Keine Besatzung');
    foreach ($crew as $person) {
        $vehicle = $person['vehicle'] ?: 'Ohne Fahrzeug';
        exportLine($lines, "$vehicle | " . ($crewRoleLabels[$person['role']] ?? $person['role']) . ': ' . $person['name']);
    }
    exportLine($lines, 'Einsatzverlauf', true);
    foreach (explode("\n", $report['narrative']) as $paragraph) exportLine($lines, $paragraph);
    exportLine($lines, 'Prüfverlauf', true);
    foreach ($report['history'] as $transition) {
        $entry = exportDateTime($transition['created_at']) . ': ' . $transition['actor_name'] . ' (' . ($roleLabels[$transition['actor_role']] ?? $transition['actor_role']) . ') – ' . ($statusLabels[$transition['to_status']] ?? $transition['to_status']);
        if ($transition['comment'] !== '') $entry .= ' | ' . $transition['comment'];
        exportLine($lines, $entry);
    }
    exportLine($lines);
    return $lines;
}

function reportReferenceForExport(int $reportId, array $user): ?array
{
    [$visibility, $params] = reportVisibilitySql($user);
    return one(
        "SELECT r.incident_id FROM reports r JOIN incidents i ON i.id=r.incident_id
         WHERE r.id=? AND i.organization_id=? AND $visibility",
        array_merge([$reportId, $user['organization_id']], $params)
    );
}

function transitionReport(int $reportId, string $action, array $user, string $comment): array
{
    $rules = [
        'submit-to-unit' => ['author_draft', 'unit_review', 'fuehrungskraft', 'report_submitted_unit'],
        'return-to-author' => ['unit_review', 'author_draft', 'einheitsleitung', 'report_returned_author'],
        'submit-to-command' => ['unit_review', 'wehr_review', 'einheitsleitung', 'report_submitted_command'],
        'return-to-unit' => ['wehr_review', 'unit_review', 'wehrleitung', 'report_returned_unit'],
    ];
    if (!isset($rules[$action])) throw new ApiError(404, 'Statusübergang nicht gefunden');
    [$from, $to, $role, $event] = $rules[$action];
    assertRole($user, $role);
    $comment = str_starts_with($action, 'return-') ? required($comment, 'Kommentar', 2000) : '';

    $pdo = db();
    $pdo->beginTransaction();
    try {
        $reference = one(
            'SELECT r.incident_id,i.organization_id FROM reports r JOIN incidents i ON i.id=r.incident_id WHERE r.id=?',
            [$reportId]
        );
        if (!$reference || (int)$reference['organization_id'] !== (int)$user['organization_id']) throw new ApiError(404, 'Bericht nicht gefunden');
        query('SELECT id FROM incidents WHERE id=? FOR UPDATE', [$reference['incident_id']]);
        $report = one(
            'SELECT r.*,i.organization_id,i.title incident_title FROM reports r JOIN incidents i ON i.id=r.incident_id WHERE r.id=? FOR UPDATE',
            [$reportId]
        );
        if (!$report || (int)$report['organization_id'] !== (int)$user['organization_id']) throw new ApiError(404, 'Bericht nicht gefunden');
        if ($report['status'] !== $from) throw new ApiError(409, 'Der Bericht wurde bereits geändert. Bitte Ansicht neu laden.');
        if ($action === 'submit-to-unit') {
            if ((int)$report['author_id'] !== (int)$user['id'] || !in_array((int)$report['unit_id'], $user['unitIds'], true)) {
                throw new ApiError(403, 'Keine Berechtigung');
            }
        } elseif ($user['role'] === 'einheitsleitung' && !in_array((int)$report['unit_id'], $user['unitIds'], true)) {
            throw new ApiError(403, 'Keine Berechtigung');
        }
        if ($action === 'return-to-author') {
            $assigned = query(
                "SELECT COUNT(*) FROM users u JOIN user_units uu ON uu.user_id=u.id
                 WHERE u.id=? AND u.role='fuehrungskraft' AND uu.unit_id=?",
                [$report['author_id'], $report['unit_id']]
            )->fetchColumn();
            if (!(int)$assigned) throw new ApiError(409, 'Der ursprüngliche Autor ist dieser Einheit nicht mehr zugeordnet.');
        }

        $released = $to === 'wehr_review' ? ',released_at=COALESCE(released_at,UTC_TIMESTAMP())' : '';
        $updated = query("UPDATE reports SET status=?$released WHERE id=? AND status=?", [$to, $reportId, $from]);
        if ($updated->rowCount() !== 1) throw new ApiError(409, 'Der Bericht wurde bereits geändert. Bitte Ansicht neu laden.');
        query(
            'INSERT INTO report_transitions(report_id,from_status,to_status,actor_id,actor_name,actor_role,comment,created_at) VALUES(?,?,?,?,?,?,?,UTC_TIMESTAMP())',
            [$reportId, $from, $to, $user['id'], $user['name'], $user['role'], $comment]
        );
        if ($action === 'return-to-unit') query('UPDATE incidents SET consolidated_at=NULL WHERE id=?', [$report['incident_id']]);
        $pdo->commit();
    } catch (Throwable $error) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $error;
    }

    $recipientId = $action === 'return-to-author' ? (int)$report['author_id'] : null;
    return [
        'ok' => true,
        'warning' => sendWorkflowNotification($event, (int)$report['incident_id'], [(int)$report['unit_id']], $user, $recipientId, $comment)
    ];
}

function vehicleSnapshots(mixed $value): array
{
    if (!is_array($value)) throw new ApiError(400, 'Fahrzeuge sind ungültig');
    // Preserve labels and ownership as they were when the incident was imported.
    return array_map(function ($vehicle) {
        if (is_string($vehicle)) return required($vehicle, 'Fahrzeug', 200);
        if (!is_array($vehicle)) throw new ApiError(400, 'Fahrzeug ist ungültig');
        return [
            'id' => optional($vehicle['id'] ?? '', 'Fahrzeug-ID', 200),
            'name' => required($vehicle['name'] ?? '', 'Fahrzeugname', 200),
            'shortname' => optional($vehicle['shortname'] ?? '', 'Fahrzeugtyp', 100),
            'fullname' => optional($vehicle['fullname'] ?? '', 'Fahrzeugtyp', 200),
            'own' => ($vehicle['own'] ?? true) !== false
        ];
    }, $value);
}

function reportDetails(array $data, array $incident): array
{
    if (!in_array($data['incidentType'] ?? null, INCIDENT_TYPES, true)) throw new ApiError(400, 'Einsatzart ist ungültig');
    $times = [
        'alarmedAt' => requestDate($incident['started_at'], 'Alarmiert um'),
        'departedAt' => in_array($data['departedAt'] ?? null, [null, ''], true) ? null : requestDate($data['departedAt'], 'Ausgerückt um'),
        'arrivedAt' => in_array($data['arrivedAt'] ?? null, [null, ''], true) ? null : requestDate($data['arrivedAt'], 'Eingetroffen um'),
        'endedAt' => requestDate($data['endedAt'] ?? null, 'Einsatz beendet um')
    ];
    $chronological = array_values(array_filter($times));
    for ($index = 1; $index < count($chronological); $index++) {
        if ($chronological[$index] < $chronological[$index - 1]) throw new ApiError(400, 'Vorhandene Einsatzzeiten müssen chronologisch sein');
    }
    $classification = [];
    $selected = is_array($data['classification'] ?? null) ? $data['classification'] : [];
    foreach (CLASSIFICATIONS as $group => $allowed) {
        $values = isset($selected[$group]) && is_array($selected[$group])
            ? array_values(array_unique(array_map('strval', $selected[$group]))) : [];
        foreach ($values as $value) if (!in_array($value, $allowed, true)) throw new ApiError(400, 'Aufgliederung ist ungültig');
        $classification[$group] = $values;
    }
    $structured = [];
    foreach ([
        'damagedParty' => ['name' => 'Name der geschädigten Person', 'phone' => 'Telefon der geschädigten Person', 'address' => 'Adresse der geschädigten Person'],
        'damagingParty' => ['name' => 'Name des Schädigers', 'phone' => 'Telefon des Schädigers', 'address' => 'Adresse des Schädigers'],
        'incidentCommand' => ['rank' => 'Dienstgrad der Einsatzleitung', 'name' => 'Name der Einsatzleitung', 'additionalRank' => 'Weiterer Dienstgrad', 'additionalName' => 'Weitere Führungskraft']
    ] as $group => $fields) {
        $source = is_array($data[$group] ?? null) ? $data[$group] : [];
        foreach ($fields as $field => $label) $structured[$group][$field] = optional($source[$field] ?? null, $label, $field === 'address' ? 500 : 200);
    }
    return [
        'alarmedAt' => utcString($times['alarmedAt']), 'departedAt' => utcString($times['departedAt']),
        'arrivedAt' => utcString($times['arrivedAt']), 'endedAt' => utcString($times['endedAt']),
        'reportYear' => (int)$times['alarmedAt']->setTimezone(new DateTimeZone('Europe/Berlin'))->format('Y'),
        'runningNumber' => required($data['runningNumber'] ?? null, 'Laufende Nummer', 50),
        'damagedParty' => json_encode($structured['damagedParty'], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
        'damagingParty' => json_encode($structured['damagingParty'], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
        'incidentCommand' => json_encode($structured['incidentCommand'], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
        'incidentType' => $data['incidentType'],
        'classification' => json_encode($classification, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)
    ];
}

function replaceCrew(int $reportId, int $incidentId, int $unitId, mixed $crew, int $organizationId): array
{
    if (!is_array($crew) || !array_is_list($crew)) throw new ApiError(400, 'Besatzung ist ungültig');
    $assignment = one('SELECT vehicles FROM incident_units WHERE incident_id=? AND unit_id=?', [$incidentId, $unitId]);
    $snapshots = json_decode($assignment['vehicles'] ?? '[]', true) ?: [];
    $vehicles = array_map(fn($vehicle) => is_string($vehicle) ? $vehicle : $vehicle['name'],
        array_values(array_filter($snapshots, fn($vehicle) => is_string($vehicle) || ($vehicle['own'] ?? true) !== false)));
    $members = [];
    foreach (query(
        'SELECT m.id,m.name FROM members m JOIN member_units mu ON mu.member_id=m.id
         WHERE m.organization_id=? AND mu.unit_id=?
         AND (mu.active=1 OR EXISTS(SELECT 1 FROM report_crew rc WHERE rc.report_id=? AND rc.member_id=m.id))',
        [$organizationId, $unitId, $reportId]
    )->fetchAll() as $member) $members[(int)$member['id']] = $member['name'];
    $seen = $occupied = $rows = [];
    foreach ($crew as $item) {
        if (!is_array($item)) throw new ApiError(400, 'Besatzung ist ungültig');
        $memberId = (int)($item['memberId'] ?? 0);
        $vehicle = trim((string)($item['vehicle'] ?? ''));
        $role = (string)($item['role'] ?? 'besatzung');
        // Driver and unit leader are unique per vehicle; crew members are not.
        $slot = $vehicle && $role !== 'besatzung' ? "$vehicle:$role" : '';
        if (!$memberId || isset($seen[$memberId]) || !isset($members[$memberId]) || ($vehicle && !in_array($vehicle, $vehicles, true))
            || !in_array($role, ['maschinist', 'einheitsfuehrer', 'besatzung'], true)
            || (!$vehicle && $role !== 'besatzung') || ($slot && isset($occupied[$slot]))) {
            throw new ApiError(400, 'Besatzung ist ungültig');
        }
        $seen[$memberId] = true;
        if ($slot) $occupied[$slot] = true;
        $rows[] = compact('memberId', 'vehicle', 'role') + ['name' => $members[$memberId]];
    }
    query('DELETE FROM report_crew WHERE report_id=?', [$reportId]);
    foreach ($rows as $row) query(
        'INSERT INTO report_crew(report_id,member_id,vehicle,role) VALUES(?,?,?,?)',
        [$reportId, $row['memberId'], $row['vehicle'], $row['role']]
    );
    return [
        'vehicles' => implode(', ', array_values(array_unique(array_filter(array_column($rows, 'vehicle'))))),
        'personnel' => implode(', ', array_column($rows, 'name'))
    ];
}

function diveraGet(string $url, string $error): array
{
    $context = stream_context_create(['http' => [
        'method' => 'GET', 'timeout' => 20, 'ignore_errors' => true,
        'header' => "Accept: application/json\r\nUser-Agent: Einsatzberichte-PHP\r\n"
    ]]);
    error_clear_last();
    $raw = @file_get_contents($url, false, $context);
    $warning = (string)(error_get_last()['message'] ?? '');
    $status = 0;
    foreach ($http_response_header ?? [] as $header) if (preg_match('/^HTTP\/\S+\s+(\d+)/', $header, $match)) $status = (int)$match[1];
    if ($raw === false && $status === 0) {
        $reason = match (true) {
            str_contains($warning, 'php_network_getaddresses'), str_contains($warning, 'getaddrinfo') => 'Host nicht erreichbar',
            str_contains($warning, 'Connection refused'), str_contains($warning, 'actively refused') => 'Dienst nicht erreichbar',
            str_contains($warning, 'timed out'), str_contains($warning, 'timeout') => 'Zeitüberschreitung',
            str_contains($warning, 'SSL'), str_contains($warning, 'certificate'), str_contains($warning, 'crypto') => 'TLS-Verbindung fehlgeschlagen',
            default => 'Verbindung fehlgeschlagen'
        };
        throw new ApiError(502, "$error: $reason");
    }
    if ($status < 200 || $status >= 300) throw new ApiError(502, "$error (HTTP $status)");
    try {
        $data = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
        if (!is_array($data)) throw new JsonException();
        return $data;
    } catch (JsonException) {
        throw new ApiError(502, "$error: ungültige JSON-Antwort");
    }
}

function diveraUrl(string $path, string $key): string
{
    return diveraBaseUrl() . "$path?accesskey=" . rawurlencode($key);
}

function diveraCluster(array $unit): array
{
    $raw = diveraGet(diveraUrl('/api/v2/pull/all', $unit['divera_access_key']), 'DIVERA-Stammdatenabfrage fehlgeschlagen');
    $cluster = $raw['data']['cluster'] ?? null;
    if (!is_array($cluster)
        || !is_array($cluster['vehicle'] ?? null)
        || !is_array($cluster['qualification'] ?? null)
        || !is_array($cluster['consumer'] ?? null)) {
        throw new ApiError(502, 'DIVERA-Stammdaten sind unvollständig');
    }
    return $cluster;
}

function diveraData(array $unit, bool $includeVehicles = true, ?array $cluster = null): array
{
    $alarmsRaw = diveraGet(diveraUrl('/api/v2/alarms', $unit['divera_access_key']), 'DIVERA-Abfrage fehlgeschlagen');
    $ownVehicles = [];
    if ($includeVehicles) {
        $cluster ??= diveraCluster($unit);
        foreach (($cluster['vehicle'] ?? []) as $id => $vehicle) {
            $ownVehicles[(string)($vehicle['id'] ?? $id)] = $vehicle;
        }
    }
    $vehicles = [];
    foreach ($ownVehicles as $id => $vehicle) $vehicles[] = [
        'id' => $id, 'name' => $vehicle['name'] ?? $vehicle['shortname'] ?? $id,
        'shortname' => (string)($vehicle['shortname'] ?? ''), 'fullname' => (string)($vehicle['fullname'] ?? ''), 'own' => true
    ];
    $source = $alarmsRaw['data']['items'] ?? $alarmsRaw['data'] ?? $alarmsRaw['items'] ?? $alarmsRaw;
    $alarms = [];
    foreach (is_array($source) ? array_values($source) : [] as $alarm) {
        $assigned = $alarm['vehicles'] ?? $alarm['vehicle_ids'] ?? $alarm['vehicle'] ?? [];
        $ids = is_array($assigned) ? (array_is_list($assigned) ? $assigned : array_keys($assigned)) : explode(',', (string)$assigned);
        $alarmVehicles = [];
        foreach ($ids as $id) {
            $id = trim((string)$id);
            if (!$id) continue;
            $vehicle = $ownVehicles[$id] ?? null;
            $alarmVehicles[] = [
                'id' => $id, 'name' => $vehicle['name'] ?? $vehicle['shortname'] ?? $id,
                'shortname' => (string)($vehicle['shortname'] ?? ''), 'fullname' => (string)($vehicle['fullname'] ?? ''),
                'own' => (bool)$vehicle
            ];
        }
        $alarms[] = [
            'id' => (string)($alarm['id'] ?? $alarm['cluster_id'] ?? $alarm['number'] ?? ''),
            'foreignId' => (string)($alarm['foreign_id'] ?? ''), 'date' => finiteNumber($alarm['date'] ?? null, 'Alarmierungszeit'),
            'title' => $alarm['title'] ?? $alarm['text'] ?? $alarm['type'] ?? 'Einsatz',
            'startedAt' => isoDate($alarm['date'] ?? $alarm['ts_create'] ?? $alarm['created_at'] ?? null),
            'text' => (string)($alarm['text'] ?? ''), 'address' => $alarm['address'] ?? $alarm['location'] ?? '',
            'lat' => finiteNumber($alarm['lat'] ?? null, 'Breitengrad'), 'lng' => finiteNumber($alarm['lng'] ?? $alarm['long'] ?? null, 'Längengrad'),
            'remark' => (string)($alarm['remark'] ?? ''), 'patient' => (string)($alarm['patient'] ?? ''),
            'caller' => (string)($alarm['caller'] ?? ''), 'vehicles' => $alarmVehicles
        ];
    }
    return compact('alarms', 'vehicles');
}

function diveraText(mixed $value, string $name, int $maximum, bool $required = false): string
{
    if ($value !== null && !is_scalar($value)) throw new ApiError(502, "DIVERA-$name ist ungültig");
    $text = trim((string)$value);
    if (($required && $text === '') || textLength($text) > $maximum) throw new ApiError(502, "DIVERA-$name ist ungültig");
    return $text;
}

function syncDiveraVehicles(array $cluster, int $unitId): int
{
    $vehicles = [];
    foreach ($cluster['vehicle'] as $externalId => $vehicle) {
        if (!is_array($vehicle)) throw new ApiError(502, 'DIVERA-Fahrzeugdaten sind ungültig');
        $diveraId = diveraText($vehicle['id'] ?? $externalId, 'Fahrzeug-ID', 200, true);
        $name = diveraText($vehicle['name'] ?? $vehicle['shortname'] ?? $diveraId, 'Fahrzeugname', 200, true);
        $vehicles[] = [
            $unitId, $diveraId, $name,
            diveraText($vehicle['shortname'] ?? '', 'Fahrzeugtyp', 100),
            diveraText($vehicle['fullname'] ?? '', 'Fahrzeugtyp', 200)
        ];
    }
    query('DELETE FROM vehicles WHERE unit_id=?', [$unitId]);
    foreach ($vehicles as $vehicle) {
        query(
            'INSERT INTO vehicles(unit_id,divera_id,name,shortname,fullname) VALUES(?,?,?,?,?)',
            $vehicle
        );
    }
    return count($vehicles);
}

function syncDiveraMembers(array $cluster, int $unitId, int $organizationId): array
{
    $qualificationRows = [];
    foreach ($cluster['qualification'] as $externalId => $qualification) {
        if (!is_array($qualification)) throw new ApiError(502, 'DIVERA-Qualifikationsdaten sind ungültig');
        $diveraId = diveraText($qualification['id'] ?? $externalId, 'Qualifikations-ID', 200, true);
        $qualificationRows[$diveraId] = [
            diveraText($qualification['name'] ?? null, 'Qualifikation', 200, true),
            diveraText($qualification['shortname'] ?? '', 'Qualifikationskürzel', 100)
        ];
    }
    $consumerRows = [];
    foreach ($cluster['consumer'] as $externalId => $consumer) {
        if (!is_array($consumer) || !is_array($consumer['qualifications'] ?? null)) throw new ApiError(502, 'DIVERA-Mitgliedsdaten sind ungültig');
        $diveraId = diveraText($consumer['id'] ?? $externalId, 'Mitglieds-ID', 200, true);
        $fallbackName = diveraText($consumer['firstname'] ?? '', 'Vorname', 200) . ' ' . diveraText($consumer['lastname'] ?? '', 'Nachname', 200);
        $name = diveraText($consumer['stdformat_name'] ?? trim($fallbackName), 'Mitgliedsname', 200, true);
        $qualificationIds = [];
        foreach ($consumer['qualifications'] as $qualificationId) {
            $qualificationId = diveraText($qualificationId, 'Qualifikations-ID', 200, true);
            if (!isset($qualificationRows[$qualificationId])) throw new ApiError(502, 'DIVERA-Mitgliedsdaten enthalten eine unbekannte Qualifikation');
            $qualificationIds[] = $qualificationId;
        }
        $consumerRows[] = [$diveraId, $name, array_unique($qualificationIds)];
    }

    query(
        'DELETE mq FROM member_qualifications mq JOIN qualifications q ON q.id=mq.qualification_id WHERE q.unit_id=?',
        [$unitId]
    );
    query('UPDATE member_units SET active=0 WHERE unit_id=?', [$unitId]);
    $qualifications = [];
    foreach ($qualificationRows as $diveraId => [$name, $shortname]) {
        query(
            'INSERT INTO qualifications(unit_id,divera_id,name,shortname) VALUES(?,?,?,?)
             ON DUPLICATE KEY UPDATE name=VALUES(name),shortname=VALUES(shortname),id=LAST_INSERT_ID(id)',
            [$unitId, $diveraId, $name, $shortname]
        );
        $qualifications[$diveraId] = (int)db()->lastInsertId();
    }

    $members = 0;
    foreach ($consumerRows as [$diveraId, $name, $qualificationIds]) {
        query(
            'INSERT INTO members(organization_id,divera_id,name) VALUES(?,?,?)
             ON DUPLICATE KEY UPDATE name=VALUES(name),id=LAST_INSERT_ID(id)',
            [$organizationId, $diveraId, $name]
        );
        $memberId = (int)db()->lastInsertId();
        query(
            'INSERT INTO member_units(member_id,unit_id,active) VALUES(?,?,1)
             ON DUPLICATE KEY UPDATE active=1',
            [$memberId, $unitId]
        );
        foreach ($qualificationIds as $qualificationId) {
            query(
                'INSERT IGNORE INTO member_qualifications(member_id,qualification_id) VALUES(?,?)',
                [$memberId, $qualifications[$qualificationId]]
            );
        }

        $members++;
    }

    if ($qualifications) {
        $placeholders = implode(',', array_fill(0, count($qualifications), '?'));
        query(
            "DELETE FROM qualifications WHERE unit_id=? AND divera_id NOT IN ($placeholders)",
            array_merge([$unitId], array_keys($qualifications))
        );
    } else {
        query('DELETE FROM qualifications WHERE unit_id=?', [$unitId]);
    }
    query(
        'DELETE m FROM members m WHERE m.organization_id=?
         AND NOT EXISTS(SELECT 1 FROM member_units mu WHERE mu.member_id=m.id)
         AND NOT EXISTS(SELECT 1 FROM report_crew rc WHERE rc.member_id=m.id)',
        [$organizationId]
    );
    return ['members' => $members, 'qualifications' => count($qualifications)];
}

function persistDiveraAlarm(array $alarm, int $unitId, array $user): array
{
    $diveraId = required($alarm['id'] ?? null, 'DIVERA-ID', 200);
    $saved = query(
        'INSERT INTO incidents(organization_id,divera_id,foreign_id,divera_date,title,started_at,message,address,lat,lng,remark,patient,caller,consolidated_text)
         VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
         ON DUPLICATE KEY UPDATE id=LAST_INSERT_ID(id)',
        [$user['organization_id'], $diveraId, optional($alarm['foreignId'] ?? '', 'Einsatznummer', 200),
         finiteNumber($alarm['date'] ?? null, 'Alarmierungszeit'), required($alarm['title'] ?? null, 'Stichwort', 300),
         required($alarm['startedAt'] ?? null, 'Zeitpunkt', 100), optional($alarm['text'] ?? '', 'Meldung'),
         optional($alarm['address'] ?? '', 'Adresse', 500), finiteNumber($alarm['lat'] ?? null, 'Breitengrad'),
         finiteNumber($alarm['lng'] ?? null, 'Längengrad'), optional($alarm['remark'] ?? '', 'Bemerkung'),
         optional($alarm['patient'] ?? '', 'Patient'), optional($alarm['caller'] ?? '', 'Meldende Person'), '']
    );
    $incidentId = (int)db()->lastInsertId();
    $newIncident = $saved->rowCount() === 1;
    if (!$newIncident) query(
        'UPDATE incidents SET foreign_id=?,divera_date=?,title=?,started_at=?,message=?,address=?,lat=?,lng=?,remark=?,patient=?,caller=? WHERE id=?',
        [optional($alarm['foreignId'] ?? '', 'Einsatznummer', 200), finiteNumber($alarm['date'] ?? null, 'Alarmierungszeit'),
         required($alarm['title'] ?? null, 'Stichwort', 300), required($alarm['startedAt'] ?? null, 'Zeitpunkt', 100),
         optional($alarm['text'] ?? '', 'Meldung'), optional($alarm['address'] ?? '', 'Adresse', 500),
         finiteNumber($alarm['lat'] ?? null, 'Breitengrad'), finiteNumber($alarm['lng'] ?? null, 'Längengrad'),
         optional($alarm['remark'] ?? '', 'Bemerkung'), optional($alarm['patient'] ?? '', 'Patient'),
         optional($alarm['caller'] ?? '', 'Meldende Person'), $incidentId]
    );
    $vehicles = json_encode(vehicleSnapshots($alarm['vehicles'] ?? []), JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
    $assignment = query(
        'INSERT IGNORE INTO incident_units(incident_id,unit_id,vehicles) VALUES(?,?,?)',
        [$incidentId, $unitId, $vehicles]
    );
    $newAssignment = $assignment->rowCount() === 1;
    if ($newAssignment) query('UPDATE incidents SET consolidated_at=NULL WHERE id=?', [$incidentId]);
    if (!$newAssignment) query(
        'UPDATE incident_units SET vehicles=? WHERE incident_id=? AND unit_id=?',
        [$vehicles, $incidentId, $unitId]
    );
    query(
        'INSERT INTO divera_imports(unit_id,incident_id,imported_by,imported_at) VALUES(?,?,?,UTC_TIMESTAMP())',
        [$unitId, $incidentId, $user['id']]
    );
    return ['id' => $incidentId, 'newIncident' => $newIncident, 'newAssignment' => $newAssignment];
}

try {
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
    assertRequestOrigin($method);
    $path = requestPath();
    $public = in_array($path, ['/api/bootstrap', '/api/setup', '/api/login', '/api/password-reset/context', '/api/password-reset/request', '/api/password-reset/confirm'], true);
    $user = $public ? null : currentUser();
    if (!$public && !$user) respond(401, ['error' => 'Bitte anmelden']);

    if ($method === 'GET' && $path === '/api/bootstrap') {
        $databaseError = databaseConfigurationError();
        if ($databaseError) respond(503, ['error' => $databaseError]);
        respond(200, ['needsSetup' => !one('SELECT id FROM users LIMIT 1')]);
    }

    if ($method === 'POST' && $path === '/api/setup') {
        if (one('SELECT id FROM users LIMIT 1')) throw new ApiError(409, 'Einrichtung abgeschlossen');
        $data = input();
        $setupToken = (string)(config()['setup_token'] ?? '');
        if (strlen($setupToken) < 32) throw new ApiError(503, 'SETUP_TOKEN ist nicht sicher konfiguriert');
        if (!hash_equals($setupToken, (string)($data['setupToken'] ?? ''))) throw new ApiError(403, 'Einrichtungstoken ist ungültig');
        $password = required($data['password'] ?? null, 'Passwort', 200);
        if (textLength($password) < 10) throw new ApiError(400, 'Passwort muss mindestens 10 Zeichen haben');
        $email = emailAddress($data['email'] ?? null);
        transaction(function () use ($data, $email, $password) {
            query('INSERT INTO organizations(name) VALUES(?)', [required($data['organization'] ?? null, 'Wehr', 200)]);
            $org = (int)db()->lastInsertId();
            query('INSERT INTO units(organization_id,name) VALUES(?,?)', [$org, required($data['unit'] ?? null, 'Einheit', 200)]);
            $unitId = (int)db()->lastInsertId();
            query(
                "INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) VALUES(?,?,?,?,?,'wehrleitung')",
                [$org, null, required($data['name'] ?? null, 'Name', 200), $email, password_hash($password, PASSWORD_DEFAULT)]
            );
        });
        respond(201, ['ok' => true]);
    }

    if ($method === 'POST' && $path === '/api/login') {
        $data = input();
        $email = required($data['email'] ?? null, 'E-Mail', 320);
        $password = (string)($data['password'] ?? '');
        $token = bin2hex(random_bytes(32));
        $cookieName = sessionCookieName();
        transaction(function () use ($email, $password, $token, $cookieName) {
            $login = one('SELECT * FROM users WHERE email=? FOR UPDATE', [$email]);
            if (!$login || !password_verify($password, $login['password_hash'])) {
                throw new ApiError(401, 'E-Mail oder Passwort falsch');
            }
            if (password_needs_rehash($login['password_hash'], PASSWORD_DEFAULT)) {
                query('UPDATE users SET password_hash=? WHERE id=?', [password_hash($password, PASSWORD_DEFAULT), $login['id']]);
            }
            query('DELETE FROM sessions WHERE expires_at<=UTC_TIMESTAMP()');
            if (preg_match('/^[a-f0-9]{64}$/', $_COOKIE[$cookieName] ?? '')) query('DELETE FROM sessions WHERE token=?', [hash('sha256', $_COOKIE[$cookieName])]);
            query('INSERT INTO sessions(token,user_id,expires_at) VALUES(?,?,UTC_TIMESTAMP()+INTERVAL 12 HOUR)', [hash('sha256', $token), $login['id']]);
            query('INSERT INTO login_history(user_id,logged_in_at) VALUES(?,UTC_TIMESTAMP())', [$login['id']]);
        });
        setcookie($cookieName, $token, [
            'expires' => time() + 43200, 'path' => '/', 'secure' => requestIsHttps(),
            'httponly' => true, 'samesite' => 'Strict'
        ]);
        respond(200, ['ok' => true]);
    }

    if ($method === 'POST' && $path === '/api/password-reset/request') {
        $data = input();
        $email = emailAddress($data['email'] ?? null);
        mailSettings();
        $user = one('SELECT id,name,email FROM users WHERE email=?', [$email]);
        if ($user) {
            $recent = one('SELECT id FROM password_resets WHERE user_id=? AND requested_at>UTC_TIMESTAMP()-INTERVAL 5 MINUTE', [$user['id']]);
            if (!$recent) {
                $token = bin2hex(random_bytes(32));
                transaction(function () use ($user, $token) {
                    query('DELETE FROM password_resets WHERE expires_at<=UTC_TIMESTAMP() OR user_id=?', [$user['id']]);
                    query('INSERT INTO password_resets(user_id,token_hash,expires_at) VALUES(?,?,UTC_TIMESTAMP()+INTERVAL 30 MINUTE)', [$user['id'], hash('sha256', $token)]);
                });
                if (!sendPasswordEmail($user, $token)) {
                    query('DELETE FROM password_resets WHERE user_id=?', [$user['id']]);
                    error_log('Passwort-Wiederherstellungs-E-Mail konnte nicht versendet werden');
                }
            }
        }
        // The response never reveals whether the address belongs to an account.
        respond(202, ['ok' => true]);
    }

    if ($method === 'POST' && $path === '/api/password-reset/context') {
        $data = input();
        $token = (string)($data['token'] ?? '');
        if (!preg_match('/^[a-f0-9]{64}$/', $token)) throw new ApiError(400, 'Wiederherstellungslink ist ungültig oder abgelaufen');
        $reset = one(
            'SELECT u.email FROM password_resets pr JOIN users u ON u.id=pr.user_id WHERE pr.token_hash=? AND pr.expires_at>UTC_TIMESTAMP()',
            [hash('sha256', $token)]
        );
        if (!$reset) throw new ApiError(400, 'Wiederherstellungslink ist ungültig oder abgelaufen');
        respond(200, ['email' => $reset['email']]);
    }

    if ($method === 'POST' && $path === '/api/password-reset/confirm') {
        $data = input();
        $token = (string)($data['token'] ?? '');
        if (!preg_match('/^[a-f0-9]{64}$/', $token)) throw new ApiError(400, 'Wiederherstellungslink ist ungültig oder abgelaufen');
        $password = required($data['password'] ?? null, 'Passwort', 200);
        if (textLength($password) < 10) throw new ApiError(400, 'Passwort muss mindestens 10 Zeichen haben');
        transaction(function () use ($token, $password) {
            $reset = one('SELECT user_id FROM password_resets WHERE token_hash=? AND expires_at>UTC_TIMESTAMP() FOR UPDATE', [hash('sha256', $token)]);
            if (!$reset) throw new ApiError(400, 'Wiederherstellungslink ist ungültig oder abgelaufen');
            query('UPDATE users SET password_hash=? WHERE id=?', [password_hash($password, PASSWORD_DEFAULT), $reset['user_id']]);
            query('DELETE FROM sessions WHERE user_id=?', [$reset['user_id']]);
            query('DELETE FROM password_resets WHERE user_id=?', [$reset['user_id']]);
        });
        respond(200, ['ok' => true]);
    }

    if ($method === 'POST' && $path === '/api/logout') {
        $cookieName = sessionCookieName();
        if (preg_match('/^[a-f0-9]{64}$/', $_COOKIE[$cookieName] ?? '')) query('DELETE FROM sessions WHERE token=?', [hash('sha256', $_COOKIE[$cookieName])]);
        setcookie($cookieName, '', [
            'expires' => 1, 'path' => '/', 'secure' => requestIsHttps(),
            'httponly' => true, 'samesite' => 'Strict'
        ]);
        respond(200, ['ok' => true]);
    }

    if ($method === 'GET' && $path === '/api/me') {
        respond(200, [
            'id' => $user['id'], 'organization_id' => $user['organization_id'],
            'organization_name' => $user['organization_name'], 'name' => $user['name'],
            'email' => $user['email'], 'role' => $user['role'], 'unitIds' => $user['unitIds']
        ]);
    }

    if ($method === 'GET' && $path === '/api/options') {
        respond(200, [
            'ranks' => RANKS,
            'incidentTypes' => INCIDENT_TYPES,
            'classifications' => CLASSIFICATIONS,
            'classificationLabels' => CLASSIFICATION_LABELS
        ]);
    }

    if ($method === 'GET' && $path === '/api/system') {
        assertRole($user, 'wehrleitung');
        $settings = config();
        $databaseError = databaseConfigurationError();
        $database = ['status' => $databaseError ?? 'Bereit'];
        if ($databaseError === null) {
            $database['name'] = (string)db()->query('SELECT DATABASE()')->fetchColumn();
            $database['serverVersion'] = (string)db()->getAttribute(PDO::ATTR_SERVER_VERSION);
        }
        $email = [
            'configured' => false,
            'transport' => empty($settings['smtp_host']) ? 'PHP mail()' : 'SMTP mit STARTTLS',
            'from' => (string)($settings['mail_from'] ?? '')
        ];
        try {
            $mail = mailSettings();
            $email = array_replace($email, [
                'configured' => true,
                'host' => $mail['smtpHost'],
                'port' => $mail['smtpHost'] === '' ? null : $mail['smtpPort'],
                'username' => $mail['smtpHost'] === '' ? '' : $mail['smtpUsername']
            ]);
        } catch (ApiError $error) {
            $email['error'] = $error->getMessage();
        }
        $systemUnits = query(
            'SELECT id,name,(divera_access_key IS NOT NULL) diveraConfigured FROM units WHERE organization_id=? ORDER BY name',
            [$user['organization_id']]
        )->fetchAll();
        foreach ($systemUnits as &$unit) {
            $unit['id'] = (int)$unit['id'];
            $unit['diveraConfigured'] = (bool)$unit['diveraConfigured'];
        }
        $systemUsers = query(
            "SELECT u.id,u.name,u.email,u.role,
             COALESCE((SELECT GROUP_CONCAT(un.name ORDER BY un.name SEPARATOR ', ') FROM user_units uu JOIN units un ON un.id=uu.unit_id WHERE uu.user_id=u.id),'') units
             FROM users u WHERE u.organization_id=? ORDER BY u.name",
            [$user['organization_id']]
        )->fetchAll();
        foreach ($systemUsers as &$systemUser) $systemUser['id'] = (int)$systemUser['id'];
        respond(200, [
            'application' => [
                'url' => (string)($settings['app_url'] ?? ''),
                'phpVersion' => PHP_VERSION,
                'setupConfigured' => strlen((string)($settings['setup_token'] ?? '')) >= 32
            ],
            'database' => $database,
            'email' => $email,
            'units' => $systemUnits,
            'users' => $systemUsers
        ]);
    }

    if ($method === 'GET' && $path === '/api/units') {
        $where = $user['role'] === 'wehrleitung'
            ? 'u.organization_id=?'
            : 'u.organization_id=? AND EXISTS(SELECT 1 FROM user_units uu WHERE uu.user_id=? AND uu.unit_id=u.id)';
        $params = $user['role'] === 'wehrleitung' ? [$user['organization_id']] : [$user['organization_id'], $user['id']];
        $rows = query(
            "SELECT u.id,u.name,(u.divera_access_key IS NOT NULL) divera_configured,
             DATE_FORMAT(MAX(di.imported_at),'%Y-%m-%dT%H:%i:%s.000Z') last_divera_import_at
             FROM units u LEFT JOIN divera_imports di ON di.unit_id=u.id
             WHERE $where GROUP BY u.id,u.name,u.divera_access_key ORDER BY u.name",
            $params
        )->fetchAll();
        foreach ($rows as &$row) { $row['id'] = (int)$row['id']; $row['divera_configured'] = (int)$row['divera_configured']; }
        respond(200, $rows);
    }

    if ($method === 'POST' && $path === '/api/units') {
        assertRole($user, 'wehrleitung');
        $data = input();
        query('INSERT INTO units(organization_id,name) VALUES(?,?)', [$user['organization_id'], required($data['name'] ?? null, 'Name', 200)]);
        respond(201, ['id' => (int)db()->lastInsertId()]);
    }

    if ($method === 'GET' && preg_match('#^/api/units/(\d+)/members$#', $path, $match)) {
        $unitId = (int)$match[1];
        assertOwnUnit($user, $unitId);
        if (!unit($unitId, $user['organization_id'])) throw new ApiError(404, 'Einheit nicht gefunden');
        respond(200, unitMembers($unitId, (int)$user['organization_id']));
    }

    if ($method === 'GET' && preg_match('#^/api/units/(\d+)/resources$#', $path, $match)) {
        $unitId = (int)$match[1];
        assertOwnUnit($user, $unitId);
        if (!unit($unitId, $user['organization_id'])) throw new ApiError(404, 'Einheit nicht gefunden');
        $vehicles = query(
            'SELECT id,divera_id,name,shortname,fullname FROM vehicles WHERE unit_id=? ORDER BY name',
            [$unitId]
        )->fetchAll();
        foreach ($vehicles as &$vehicle) $vehicle['id'] = (int)$vehicle['id'];
        respond(200, ['members' => unitMembers($unitId, (int)$user['organization_id'], false), 'vehicles' => $vehicles]);
    }

    if ($method === 'GET' && $path === '/api/users') {
        assertRole($user, 'wehrleitung');
        $rows = query(
            "SELECT u.id,u.name,u.email,u.role,
             COALESCE((SELECT JSON_ARRAYAGG(uu.unit_id) FROM user_units uu WHERE uu.user_id=u.id),JSON_ARRAY()) unit_ids,
             COALESCE((SELECT GROUP_CONCAT(un.name ORDER BY un.name SEPARATOR ', ') FROM user_units uu JOIN units un ON un.id=uu.unit_id WHERE uu.user_id=u.id),'') unit_names
             FROM users u WHERE u.organization_id=? ORDER BY u.name",
            [$user['organization_id']]
        )->fetchAll();
        $history = query(
            "SELECT h.user_id,DATE_FORMAT(MAX(h.logged_in_at),'%Y-%m-%dT%H:%i:%sZ') logged_in_at
             FROM login_history h JOIN users u ON u.id=h.user_id
             WHERE u.organization_id=? GROUP BY h.user_id ORDER BY h.user_id",
            [$user['organization_id']]
        )->fetchAll();
        $historyByUser = [];
        foreach ($history as $login) $historyByUser[(int)$login['user_id']][] = $login['logged_in_at'];
        foreach ($rows as &$row) {
            $row['id'] = (int)$row['id'];
            $row['loginHistory'] = $historyByUser[$row['id']] ?? [];
        }
        respond(200, $rows);
    }

    if ($method === 'POST' && $path === '/api/users') {
        assertRole($user, 'wehrleitung');
        $data = input();
        if (!in_array($data['role'] ?? null, ROLES, true)) throw new ApiError(400, 'Rolle ist ungültig');
        $unitIds = membershipIds($data, $user['organization_id']);
        $name = required($data['name'] ?? null, 'Name', 200);
        $email = emailAddress($data['email'] ?? null);
        mailSettings();
        $token = bin2hex(random_bytes(32));
        [$id, $expiresAt] = transaction(function () use ($data, $name, $email, $token, $unitIds, $user) {
            // An unknown random password keeps the account unusable until activation.
            query(
                'INSERT INTO users(organization_id,unit_id,name,email,password_hash,role) VALUES(?,?,?,?,?,?)',
                [$user['organization_id'], $unitIds[0] ?? null, $name, $email,
                 password_hash(bin2hex(random_bytes(32)), PASSWORD_DEFAULT), $data['role']]
            );
            $id = (int)db()->lastInsertId();
            replaceMemberships($id, $unitIds);
            query(
                'INSERT INTO password_resets(user_id,token_hash,expires_at) VALUES(?,?,UTC_TIMESTAMP()+INTERVAL 7 DAY)',
                [$id, hash('sha256', $token)]
            );
            return [$id, new DateTimeImmutable((string)one(
                'SELECT expires_at FROM password_resets WHERE user_id=?',
                [$id]
            )['expires_at'], new DateTimeZone('UTC'))];
        });
        if (!sendPasswordEmail(['name' => $name, 'email' => $email], $token, true, $expiresAt)) {
            query('DELETE FROM users WHERE id=?', [$id]);
            error_log('Einladungs-E-Mail konnte nicht versendet werden');
            throw new ApiError(503, 'Einladungs-E-Mail konnte nicht versendet werden');
        }
        respond(201, ['id' => $id]);
    }

    if ($method === 'PUT' && preg_match('#^/api/users/(\d+)$#', $path, $match)) {
        assertRole($user, 'wehrleitung');
        $existing = one('SELECT * FROM users WHERE id=? AND organization_id=?', [(int)$match[1], $user['organization_id']]);
        if (!$existing) throw new ApiError(404, 'Benutzer nicht gefunden');
        $data = input();
        if (!in_array($data['role'] ?? null, ROLES, true)) throw new ApiError(400, 'Rolle ist ungültig');
        $unitIds = membershipIds($data, $user['organization_id']);
        $password = (string)($data['password'] ?? '');
        if ($password && textLength($password) < 10) throw new ApiError(400, 'Passwort muss mindestens 10 Zeichen haben');
        transaction(function () use ($data, $password, $unitIds, $existing) {
            query('SELECT id FROM organizations WHERE id=? FOR UPDATE', [$existing['organization_id']]);
            $current = one('SELECT role FROM users WHERE id=? AND organization_id=?', [$existing['id'], $existing['organization_id']]);
            if ($current && $current['role'] === 'wehrleitung' && $data['role'] !== 'wehrleitung'
                && !one("SELECT id FROM users WHERE organization_id=? AND role='wehrleitung' AND id<>? LIMIT 1", [$existing['organization_id'], $existing['id']])) {
                throw new ApiError(409, 'Mindestens eine Wehrführung ist erforderlich');
            }
            $sql = 'UPDATE users SET unit_id=?,name=?,email=?,role=?';
            $params = [$unitIds[0] ?? null, required($data['name'] ?? null, 'Name', 200),
                emailAddress($data['email'] ?? null), $data['role']];
            if ($password) {
                $sql .= ',password_hash=?';
                $params[] = password_hash($password, PASSWORD_DEFAULT);
            }
            $params[] = $existing['id'];
            query("$sql WHERE id=?", $params);
            replaceMemberships((int)$existing['id'], $unitIds);
            if ($password) query('DELETE FROM sessions WHERE user_id=?', [$existing['id']]);
        });
        respond(200, ['ok' => true]);
    }

    if ($method === 'GET' && $path === '/api/incidents') {
        $where = $user['role'] === 'wehrleitung'
            ? 'i.organization_id=?'
            : 'i.organization_id=? AND EXISTS(SELECT 1 FROM incident_units x JOIN user_units uu ON uu.unit_id=x.unit_id WHERE x.incident_id=i.id AND uu.user_id=?)';
        $params = $user['role'] === 'wehrleitung' ? [$user['organization_id']] : [$user['organization_id'], $user['id']];
        $rows = query(
            "SELECT i.* FROM incidents i WHERE $where ORDER BY i.started_at DESC",
            $params
        )->fetchAll();
        $assignments = [];
        $membershipJoin = $user['role'] === 'wehrleitung'
            ? ''
            : 'JOIN user_units visible_uu ON visible_uu.unit_id=iu.unit_id AND visible_uu.user_id=?';
        $assignmentParams = $user['role'] === 'wehrleitung' ? $params : array_merge([$user['id']], $params);
        foreach (query(
            "SELECT iu.incident_id,iu.unit_id unitId,iu.vehicles,u.name unitName,
             r.id IS NOT NULL hasReport,r.status reportStatus,r.author_id reportAuthorId,author.name reportAuthorName
             FROM incident_units iu JOIN incidents i ON i.id=iu.incident_id JOIN units u ON u.id=iu.unit_id AND u.organization_id=i.organization_id
             $membershipJoin
             LEFT JOIN reports r ON r.incident_id=iu.incident_id AND r.unit_id=iu.unit_id
             LEFT JOIN users author ON author.id=r.author_id AND author.organization_id=i.organization_id
             WHERE $where ORDER BY iu.incident_id,iu.unit_id",
            $assignmentParams
        )->fetchAll() as $assignment) {
            $incidentId = (int)$assignment['incident_id'];
            unset($assignment['incident_id']);
            $assignment['unitId'] = (int)$assignment['unitId'];
            $assignment['hasReport'] = (int)$assignment['hasReport'];
            if ($assignment['reportAuthorId'] !== null) $assignment['reportAuthorId'] = (int)$assignment['reportAuthorId'];
            $assignments[$incidentId][] = $assignment;
        }
        foreach ($rows as $index => &$row) {
            $incidentAssignments = $assignments[(int)$row['id']] ?? [];
            $relevant = $incidentAssignments;
            if ($user['role'] !== 'wehrleitung' && !$relevant) {
                unset($rows[$index]);
                continue;
            }
            if ($user['role'] === 'wehrleitung') {
                $pending = array_values(array_filter($relevant, fn($assignment) => $assignment['reportStatus'] !== 'wehr_review'));
                $pendingUnits = array_column($pending, 'unitName');
                $row['reportStatus'] = $row['consolidated_at'] !== null
                    ? ['key' => 'completed', 'label' => 'Abgeschlossen', 'pendingUnits' => []]
                    : ($pending
                        ? ['key' => 'reports_pending', 'label' => (count($pending) === 1 ? 'Bericht ausstehend: ' : 'Berichte ausstehend: ') . implode(', ', $pendingUnits), 'pendingUnits' => $pendingUnits]
                        : ['key' => 'ready', 'label' => 'Bereit zur Konsolidierung', 'pendingUnits' => []]);
            } elseif ($user['role'] === 'einheitsleitung') {
                $status = $relevant[0]['reportStatus'] ?? null;
                $row['reportStatus'] = match ($status) {
                    'author_draft' => ['key' => 'awaiting_report', 'label' => 'Bericht der Führungskraft ausstehend', 'pendingUnits' => []],
                    'unit_review' => ['key' => 'review_required', 'label' => 'Prüfung erforderlich', 'pendingUnits' => []],
                    'wehr_review' => ['key' => 'submitted', 'label' => 'An Wehrführung übergeben', 'pendingUnits' => []],
                    default => ['key' => 'report_required', 'label' => 'Bericht erforderlich', 'pendingUnits' => []],
                };
            } else {
                $required = array_values(array_filter($relevant, fn($assignment) =>
                    !$assignment['hasReport']
                    || ($assignment['reportStatus'] === 'author_draft' && $assignment['reportAuthorId'] === $user['id'])
                ));
                $otherAuthors = array_values(array_filter($relevant, fn($assignment) =>
                    $assignment['hasReport'] && $assignment['reportAuthorId'] !== $user['id']
                ));
                $names = array_column($required ?: $otherAuthors, 'unitName');
                $row['reportStatus'] = $required
                    ? ['key' => 'report_required', 'label' => 'Bericht erforderlich: ' . implode(', ', $names), 'pendingUnits' => $names]
                    : ($otherAuthors
                        ? ['key' => 'report_exists', 'label' => 'Einsatzbericht vorhanden: ' . implode(', ', $names), 'pendingUnits' => []]
                        : ['key' => 'submitted', 'label' => 'Bericht abgegeben', 'pendingUnits' => []]);
            }
            $unitNames = array_column($relevant, 'unitName');
            sort($unitNames, SORT_NATURAL | SORT_FLAG_CASE);
            $row['units'] = implode(', ', $unitNames);
            foreach ($relevant as &$assignment) {
                if (!$assignment['reportAuthorName']
                    || $user['role'] !== 'fuehrungskraft'
                    || $assignment['reportAuthorId'] === $user['id']) {
                    unset($assignment['reportAuthorName']);
                }
                unset($assignment['unitName'], $assignment['reportStatus'], $assignment['reportAuthorId']);
            }
            unset($assignment);
            $row['assignments'] = json_encode($relevant, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
            foreach (['id', 'organization_id', 'divera_date'] as $key) if ($row[$key] !== null) $row[$key] = (int)$row[$key];
            foreach (['lat', 'lng'] as $key) if ($row[$key] !== null) $row[$key] = (float)$row[$key];
        }
        unset($row);
        respond(200, array_values($rows));
    }

    if ($method === 'POST' && $path === '/api/incidents') {
        $data = input();
        $source = is_array($data['unitIds'] ?? null) ? $data['unitIds'] : [];
        $unitIds = array_values(array_unique(array_map('intval', $source)));
        if (!$unitIds) throw new ApiError(400, 'Mindestens eine gültige Einheit ist erforderlich');
        foreach ($unitIds as $unitId) {
            if (!$unitId || !unit($unitId, $user['organization_id'])) throw new ApiError(400, 'Mindestens eine gültige Einheit ist erforderlich');
            assertOwnUnit($user, $unitId);
        }
        $id = transaction(function () use ($data, $unitIds, $user) {
            $startedAt = utcString(requestDate($data['startedAt'] ?? null, 'Zeitpunkt'));
            query(
                'INSERT INTO incidents(organization_id,title,started_at,address,message,remark,patient,caller,consolidated_text) VALUES(?,?,?,?,?,?,?,?,?)',
                [$user['organization_id'], required($data['title'] ?? null, 'Stichwort', 300),
                 $startedAt, optional($data['address'] ?? null, 'Adresse', 500), '', '', '', '', '']
            );
            $id = (int)db()->lastInsertId();
            foreach ($unitIds as $unitId) query('INSERT INTO incident_units(incident_id,unit_id,vehicles) VALUES(?,?,?)', [$id, $unitId, '[]']);
            return $id;
        });
        $warning = sendWorkflowNotification('incident_created', $id, $unitIds, $user);
        respond(201, ['id' => $id] + ($warning ? ['warning' => $warning] : []));
    }

    if ($method === 'GET' && preg_match('#^/api/incidents/(\d+)/pdf$#', $path, $match)) {
        $incidentId = (int)$match[1];
        $foundIncident = visibleIncident($incidentId, $user);
        if (!$foundIncident) throw new ApiError(404, 'Einsatz nicht gefunden');
        $lines = incidentExportLines($foundIncident, $user);
        foreach (visibleIncidentReports($incidentId, $user) as $report) $lines = array_merge($lines, reportExportLines($report));
        respondPdf("einsatz-$incidentId-akte.pdf", 'Rollenbezogene Einsatzakte', $lines, $user);
    }

    if ($method === 'GET' && preg_match('#^/api/reports/(\d+)/pdf$#', $path, $match)) {
        $reportId = (int)$match[1];
        $reference = reportReferenceForExport($reportId, $user);
        if (!$reference) throw new ApiError(404, 'Bericht nicht gefunden');
        $foundIncident = visibleIncident((int)$reference['incident_id'], $user);
        if (!$foundIncident) throw new ApiError(404, 'Bericht nicht gefunden');
        $reports = array_values(array_filter(visibleIncidentReports((int)$reference['incident_id'], $user), fn($report) => $report['id'] === $reportId));
        if (!$reports) throw new ApiError(404, 'Bericht nicht gefunden');
        respondPdf(
            "einsatz-{$reference['incident_id']}-bericht-$reportId.pdf",
            'Einzelbericht',
            array_merge(incidentExportLines($foundIncident, $user), reportExportLines($reports[0])),
            $user
        );
    }

    if ($method === 'GET' && preg_match('#^/api/incidents/(\d+)/consolidation/pdf$#', $path, $match)) {
        assertRole($user, 'wehrleitung');
        $incidentId = (int)$match[1];
        $foundIncident = incident($incidentId, $user['organization_id']);
        if (!$foundIncident) throw new ApiError(404, 'Einsatz nicht gefunden');
        if ($foundIncident['consolidated_at'] === null) throw new ApiError(409, 'Der Gesamtbericht ist nicht abgeschlossen');
        $lines = incidentExportLines($foundIncident, $user);
        exportLine($lines, 'Abgeschlossener Gesamtbericht', true);
        exportLine($lines, 'Abgeschlossen am: ' . exportDateTime($foundIncident['consolidated_at']) . ' (Europe/Berlin)');
        foreach (explode("\n", $foundIncident['consolidated_text']) as $paragraph) exportLine($lines, $paragraph);
        exportLine($lines);
        foreach (visibleIncidentReports($incidentId, $user) as $report) $lines = array_merge($lines, reportExportLines($report));
        respondPdf("einsatz-$incidentId-gesamtbericht.pdf", 'Abgeschlossener Gesamtbericht', $lines, $user);
    }

    if ($method === 'GET' && preg_match('#^/api/incidents/(\d+)/reports$#', $path, $match)) {
        $incident = incident((int)$match[1], $user['organization_id']);
        if (!$incident) throw new ApiError(404, 'Einsatz nicht gefunden');
        respond(200, visibleIncidentReports((int)$match[1], $user));
    }

    if ($method === 'POST' && preg_match('#^/api/incidents/(\d+)/reports$#', $path, $match)) {
        $incidentId = (int)$match[1];
        $foundIncident = incident($incidentId, $user['organization_id']);
        if (!$foundIncident) throw new ApiError(404, 'Einsatz nicht gefunden');
        $data = input();
        $unitId = (int)($data['unitId'] ?? 0);
        assertOwnUnit($user, $unitId);
        if (!one('SELECT incident_id FROM incident_units WHERE incident_id=? AND unit_id=?', [$incidentId, $unitId])) throw new ApiError(400, 'Einheit wurde nicht alarmiert');
        if (one('SELECT id FROM reports WHERE incident_id=? AND unit_id=?', [$incidentId, $unitId])) throw new ApiError(409, 'Für diese Einheit existiert bereits ein Einsatzbericht');
        $id = transaction(function () use ($data, $foundIncident, $incidentId, $unitId, $user) {
            $details = reportDetails($data, $foundIncident);
            $status = reportStatusForRole($user['role']);
            query(
                'INSERT INTO reports(incident_id,unit_id,author_id,report_year,running_number,damaged_party,damaging_party,incident_command,narrative,alarmed_at,departed_at,arrived_at,ended_at,incident_type,classification,vehicles,personnel,status,released_at)
                 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
                [$incidentId, $unitId, $user['id'], $details['reportYear'], $details['runningNumber'],
                 $details['damagedParty'], $details['damagingParty'], $details['incidentCommand'], required($data['narrative'] ?? null, 'Bericht'),
                 $details['alarmedAt'], $details['departedAt'], $details['arrivedAt'], $details['endedAt'],
                 $details['incidentType'], $details['classification'], '', '', $status,
                 $status === 'wehr_review' ? gmdate('Y-m-d H:i:s') : null]
            );
            $id = (int)db()->lastInsertId();
            $summary = replaceCrew($id, $incidentId, $unitId, $data['crew'] ?? [], $user['organization_id']);
            query('UPDATE reports SET vehicles=?,personnel=? WHERE id=?', [$summary['vehicles'], $summary['personnel'], $id]);
            query(
                'INSERT INTO report_transitions(report_id,from_status,to_status,actor_id,actor_name,actor_role,created_at) VALUES(?,NULL,?,?,?,?,UTC_TIMESTAMP())',
                [$id, $status, $user['id'], $user['name'], $user['role']]
            );
            return $id;
        });
        respond(201, ['id' => $id]);
    }

    if ($method === 'PUT' && preg_match('#^/api/reports/(\d+)$#', $path, $match)) {
        $foundReport = report((int)$match[1], $user['organization_id']);
        if (!$foundReport) throw new ApiError(404, 'Bericht nicht gefunden');
        if (!canEditReport($foundReport, $user)) throw new ApiError(403, 'Der Bericht kann nicht bearbeitet werden');
        $data = input();
        transaction(function () use ($data, $foundReport, $user) {
            $lockedReport = one('SELECT * FROM reports WHERE id=? FOR UPDATE', [$foundReport['id']]);
            if (!$lockedReport || !canEditReport($lockedReport, $user)) throw new ApiError(409, 'Der Bericht wurde bereits geändert');
            $foundIncident = incident((int)$lockedReport['incident_id'], $user['organization_id']);
            $details = reportDetails($data, $foundIncident);
            $summary = replaceCrew((int)$lockedReport['id'], (int)$lockedReport['incident_id'], (int)$lockedReport['unit_id'], $data['crew'] ?? [], $user['organization_id']);
            query(
                'UPDATE reports SET report_year=?,running_number=?,damaged_party=?,damaging_party=?,incident_command=?,narrative=?,vehicles=?,personnel=?,alarmed_at=?,departed_at=?,arrived_at=?,ended_at=?,incident_type=?,classification=? WHERE id=?',
                [$details['reportYear'], $details['runningNumber'], $details['damagedParty'], $details['damagingParty'], $details['incidentCommand'],
                 required($data['narrative'] ?? null, 'Bericht'), $summary['vehicles'], $summary['personnel'],
                 $details['alarmedAt'], $details['departedAt'], $details['arrivedAt'], $details['endedAt'],
                 $details['incidentType'], $details['classification'], $lockedReport['id']]
            );
        });
        respond(200, ['ok' => true]);
    }

    if ($method === 'POST' && preg_match('#^/api/reports/(\d+)/(submit-to-unit|return-to-author|submit-to-command|return-to-unit)$#', $path, $match)) {
        $data = input();
        $result = transitionReport((int)$match[1], $match[2], $user, (string)($data['comment'] ?? ''));
        respond(200, array_filter($result, fn($value) => $value !== null));
    }

    if ($method === 'PUT' && preg_match('#^/api/incidents/(\d+)/consolidation$#', $path, $match)) {
        assertRole($user, 'wehrleitung');
        $incidentId = (int)$match[1];
        $data = input();
        transaction(function () use ($incidentId, $data, $user) {
            $foundIncident = one('SELECT id FROM incidents WHERE id=? AND organization_id=? FOR UPDATE', [$incidentId, $user['organization_id']]);
            if (!$foundIncident) throw new ApiError(404, 'Einsatz nicht gefunden');
            $reports = query(
                'SELECT iu.unit_id,r.status FROM incident_units iu LEFT JOIN reports r ON r.incident_id=iu.incident_id AND r.unit_id=iu.unit_id WHERE iu.incident_id=? FOR UPDATE',
                [$incidentId]
            )->fetchAll();
            if (!$reports || array_filter($reports, fn($report) => $report['status'] !== 'wehr_review')) {
                throw new ApiError(409, 'Alle Einheitsberichte müssen bei der Wehrführung vorliegen.');
            }
            query(
                'UPDATE incidents SET consolidated_text=?,consolidated_at=UTC_TIMESTAMP() WHERE id=?',
                [required($data['text'] ?? null, 'Gesamtbericht'), $incidentId]
            );
        });
        respond(200, ['ok' => true]);
    }

    if ($method === 'PUT' && preg_match('#^/api/units/(\d+)/divera$#', $path, $match)) {
        assertRole($user, 'wehrleitung', 'einheitsleitung');
        $unitId = (int)$match[1];
        assertOwnUnit($user, $unitId);
        if (!unit($unitId, $user['organization_id'])) throw new ApiError(404, 'Einheit nicht gefunden');
        $data = input();
        query('UPDATE units SET divera_access_key=? WHERE id=?', [required($data['accessKey'] ?? null, 'Access-Key', 500), $unitId]);
        respond(200, ['ok' => true]);
    }

    if ($method === 'GET' && preg_match('#^/api/units/(\d+)/divera$#', $path, $match)) {
        assertRole($user, 'wehrleitung', 'einheitsleitung', 'fuehrungskraft');
        $unitId = (int)$match[1];
        assertOwnUnit($user, $unitId);
        $foundUnit = unit($unitId, $user['organization_id']);
        if (!$foundUnit || !$foundUnit['divera_access_key']) throw new ApiError(400, 'DIVERA ist nicht konfiguriert');
        respond(200, diveraData($foundUnit, ($_GET['summary'] ?? '') !== '1'));
    }

    if ($method === 'POST' && preg_match('#^/api/units/(\d+)/divera/members/sync$#', $path, $match)) {
        assertRole($user, 'wehrleitung', 'einheitsleitung');
        $unitId = (int)$match[1];
        assertOwnUnit($user, $unitId);
        $foundUnit = unit($unitId, $user['organization_id']);
        if (!$foundUnit || !$foundUnit['divera_access_key']) throw new ApiError(400, 'DIVERA ist nicht konfiguriert');
        $cluster = diveraCluster($foundUnit);
        $result = transaction(fn() => syncDiveraMembers($cluster, $unitId, (int)$user['organization_id']));
        respond(200, $result + ['count' => $result['members']]);
    }

    if ($method === 'POST' && preg_match('#^/api/units/(\d+)/divera/vehicles/sync$#', $path, $match)) {
        assertRole($user, 'wehrleitung', 'einheitsleitung');
        $unitId = (int)$match[1];
        assertOwnUnit($user, $unitId);
        $foundUnit = unit($unitId, $user['organization_id']);
        if (!$foundUnit || !$foundUnit['divera_access_key']) throw new ApiError(400, 'DIVERA ist nicht konfiguriert');
        $cluster = diveraCluster($foundUnit);
        $count = transaction(fn() => syncDiveraVehicles($cluster, $unitId));
        respond(200, ['vehicles' => $count, 'count' => $count]);
    }

    if ($method === 'POST' && preg_match('#^/api/units/(\d+)/divera/sync$#', $path, $match)) {
        assertRole($user, 'wehrleitung', 'einheitsleitung');
        $unitId = (int)$match[1];
        assertOwnUnit($user, $unitId);
        $foundUnit = unit($unitId, $user['organization_id']);
        if (!$foundUnit || !$foundUnit['divera_access_key']) throw new ApiError(400, 'DIVERA ist nicht konfiguriert');
        $cluster = diveraCluster($foundUnit);
        $data = diveraData($foundUnit, true, $cluster);
        $result = transaction(function () use ($cluster, $data, $unitId, $user) {
            $counts = syncDiveraMembers($cluster, $unitId, (int)$user['organization_id']);
            $counts['vehicles'] = syncDiveraVehicles($cluster, $unitId);
            $counts['incidentsCreated'] = 0;
            $counts['incidentsUpdated'] = 0;
            $counts['assignmentsCreated'] = 0;
            $counts['notifications'] = [];
            foreach ($data['alarms'] as $alarm) {
                $import = persistDiveraAlarm($alarm, $unitId, $user);
                $counts[$import['newIncident'] ? 'incidentsCreated' : 'incidentsUpdated']++;
                if ($import['newAssignment']) {
                    $counts['assignmentsCreated']++;
                    $counts['notifications'][] = $import['id'];
                }
            }
            return $counts;
        });
        $warnings = 0;
        foreach ($result['notifications'] as $incidentId) {
            if (sendWorkflowNotification('incident_imported', $incidentId, [$unitId], $user)) $warnings++;
        }
        unset($result['notifications']);
        if ($warnings) $result['warning'] = 'Die Synchronisation wurde gespeichert, aber nicht alle Benachrichtigungs-E-Mails konnten versendet werden.';
        respond(200, $result);
    }

    if ($method === 'POST' && preg_match('#^/api/units/(\d+)/divera/import$#', $path, $match)) {
        assertRole($user, 'wehrleitung', 'einheitsleitung', 'fuehrungskraft');
        $unitId = (int)$match[1];
        assertOwnUnit($user, $unitId);
        $foundUnit = unit($unitId, $user['organization_id']);
        if (!$foundUnit) throw new ApiError(404, 'Einheit nicht gefunden');
        if (!$foundUnit['divera_access_key']) throw new ApiError(400, 'DIVERA ist nicht konfiguriert');
        $requestedId = required(input()['id'] ?? null, 'DIVERA-ID', 200);
        // Trust only the id from the browser; reload all incident data from DIVERA.
        $verified = null;
        foreach (diveraData($foundUnit)['alarms'] as $alarm) {
            if ($alarm['id'] === $requestedId) { $verified = $alarm; break; }
        }
        if (!$verified) throw new ApiError(404, 'DIVERA-Einsatz nicht gefunden');
        $import = transaction(fn() => persistDiveraAlarm($verified, $unitId, $user));
        $warning = $import['newAssignment']
            ? sendWorkflowNotification('incident_imported', $import['id'], [$unitId], $user)
            : null;
        respond(201, ['id' => $import['id']] + ($warning ? ['warning' => $warning] : []));
    }

    respond(404, ['error' => 'Nicht gefunden']);
} catch (ApiError $error) {
    respond($error->status, ['error' => $error->getMessage()]);
} catch (PDOException $error) {
    error_log((string)$error);
    $duplicate = (int)($error->errorInfo[1] ?? 0) === 1062;
    respond($duplicate ? 409 : 500, ['error' => $duplicate ? 'Datensatz existiert bereits' : 'Interner Fehler']);
} catch (Throwable $error) {
    error_log((string)$error);
    respond(500, ['error' => 'Interner Fehler']);
}
