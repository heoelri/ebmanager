<?php
declare(strict_types=1);

require __DIR__ . '/../constants.php';
require __DIR__ . '/../support.php';

assert(LOGIN_HISTORY_RETENTION_DAYS === 90);
assert(AUTH_CLEANUP_INTERVAL_SECONDS === 3600);
assert(AUTH_CLEANUP_BATCH_SIZE === 500);
$originalState = one('SELECT last_run_at FROM auth_cleanup_state WHERE id=1')['last_run_at'];
$originalTimezone = one('SELECT @@session.time_zone AS zone')['zone'];
// Ten minutes ahead keeps concurrent HTTP health checks outside the due window.
$clock = (int)one('SELECT UNIX_TIMESTAMP() AS clock')['clock'] + 600;
db()->exec("SET timestamp=$clock");
query('SET time_zone=?', ['+04:00']);
$times = one(
    'SELECT UTC_TIMESTAMP() AS now,UTC_TIMESTAMP()-INTERVAL 90 DAY AS cutoff,
     UTC_TIMESTAMP()-INTERVAL 90 DAY-INTERVAL 1 SECOND AS old_login,
     UTC_TIMESTAMP()-INTERVAL 1 HOUR AS due'
);
$organizations = [];
$users = [];
$lock = null;
$failureTrigger = false;
try {
    transaction(function () use (&$organizations, &$users, $times) {
        foreach ([1, 2] as $number) {
            query('INSERT INTO organizations(name) VALUES(?)', ["Bereinigungstest $number"]);
            $organizations[] = (int)db()->lastInsertId();
            query(
                "INSERT INTO users(organization_id,name,email,password_hash,role) VALUES(?,?,?,?,'wehrleitung')",
                [$organizations[array_key_last($organizations)], "Bereinigungstest $number", "cleanup-$number@example.test", 'unbenutzbar']
            );
            $users[] = (int)db()->lastInsertId();
        }
        for ($index = 0; $index < AUTH_CLEANUP_BATCH_SIZE; $index++) {
            query('INSERT INTO sessions(token,user_id,expires_at) VALUES(?,?,UTC_TIMESTAMP()-INTERVAL 1 DAY)',
                [hash('sha256', "cleanup-old-$index"), $users[$index % 2]]);
            query('INSERT INTO login_history(user_id,logged_in_at) VALUES(?,UTC_TIMESTAMP()-INTERVAL 91 DAY)',
                [$users[$index % 2]]);
        }
        query('INSERT INTO sessions(token,user_id,expires_at) VALUES(?,?,?), (?,?,UTC_TIMESTAMP()+INTERVAL 1 SECOND)',
            [hash('sha256', 'cleanup-boundary'), $users[0], $times['now'], hash('sha256', 'cleanup-valid'), $users[1]]);
        query('INSERT INTO login_history(user_id,logged_in_at) VALUES(?,?),(?,?),(?,UTC_TIMESTAMP()-INTERVAL 90 DAY+INTERVAL 1 SECOND)',
            [$users[0], $times['old_login'], $users[0], $times['cutoff'], $users[1]]);
        query('INSERT INTO password_resets(user_id,token_hash,expires_at) VALUES(?,?,UTC_TIMESTAMP()+INTERVAL 1 DAY),(?,?,UTC_TIMESTAMP()-INTERVAL 1 DAY)',
            [$users[0], hash('sha256', 'cleanup-valid-link'), $users[1], hash('sha256', 'cleanup-expired-link')]);
        query('UPDATE auth_cleanup_state SET last_run_at=? WHERE id=1', [$times['due']]);
    });

    // Every table loses at most 500 oldest rows, across both test organizations.
    cleanupAuthenticationData();
    assert((int)one('SELECT COUNT(*) AS n FROM sessions WHERE user_id IN (?,?)', $users)['n'] === 2);
    assert((int)one('SELECT COUNT(*) AS n FROM login_history WHERE user_id IN (?,?)', $users)['n'] === 3);
    assert(one('SELECT token FROM sessions WHERE token=?', [hash('sha256', 'cleanup-boundary')]) !== null);
    assert(one('SELECT id FROM login_history WHERE user_id=? AND logged_in_at=?', [$users[0], $times['old_login']]) !== null);
    assert(one('SELECT last_run_at FROM auth_cleanup_state WHERE id=1')['last_run_at'] === $times['now']);

    // Repeated requests and a run 3599 seconds ago cannot consume another batch.
    cleanupAuthenticationData();
    query('UPDATE auth_cleanup_state SET last_run_at=UTC_TIMESTAMP()-INTERVAL 3599 SECOND WHERE id=1');
    cleanupAuthenticationData();
    assert((int)one('SELECT COUNT(*) AS n FROM sessions WHERE user_id IN (?,?)', $users)['n'] === 2);
    assert((int)one('SELECT COUNT(*) AS n FROM login_history WHERE user_id IN (?,?)', $users)['n'] === 3);

    // A competing worker skips the locked singleton without waiting or deleting.
    query('UPDATE auth_cleanup_state SET last_run_at=? WHERE id=1', [$times['due']]);
    $config = config();
    $lock = new PDO($config['dsn'], $config['user'], $config['password'], [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
    $lock->beginTransaction();
    $lock->query('SELECT id FROM auth_cleanup_state WHERE id=1 FOR UPDATE')->fetch();
    $originalLockWaitTimeout = (int)one('SELECT @@session.innodb_lock_wait_timeout AS timeout')['timeout'];
    try {
        db()->exec('SET SESSION innodb_lock_wait_timeout=1');
        cleanupAuthenticationData();
    } finally {
        db()->exec("SET SESSION innodb_lock_wait_timeout=$originalLockWaitTimeout");
    }
    assert((int)one('SELECT @@session.innodb_lock_wait_timeout AS timeout')['timeout'] === $originalLockWaitTimeout);
    assert((int)one('SELECT COUNT(*) AS n FROM sessions WHERE user_id IN (?,?)', $users)['n'] === 2);
    assert(one('SELECT last_run_at FROM auth_cleanup_state WHERE id=1')['last_run_at'] === $times['due']);
    $lock->rollBack();

    // A failure in the second delete rolls back the first delete and the run marker.
    db()->exec("CREATE TRIGGER auth_cleanup_test_failure BEFORE DELETE ON login_history
        FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='cleanup-test'");
    $failureTrigger = true;
    try {
        cleanupAuthenticationData();
        throw new RuntimeException('Fehler der Bereinigung wurde verschluckt');
    } catch (PDOException $error) {
        assert($error->getCode() === '45000');
    }
    assert(!db()->inTransaction());
    assert(one('SELECT token FROM sessions WHERE token=?', [hash('sha256', 'cleanup-boundary')]) !== null);
    assert(one('SELECT last_run_at FROM auth_cleanup_state WHERE id=1')['last_run_at'] === $times['due']);
    db()->exec('DROP TRIGGER auth_cleanup_test_failure');
    $failureTrigger = false;

    // Exactly one hour is due; expired sessions are removed, exactly 90 days remain.
    cleanupAuthenticationData();
    assert(one('SELECT token FROM sessions WHERE token=?', [hash('sha256', 'cleanup-boundary')]) === null);
    assert(one('SELECT token FROM sessions WHERE token=?', [hash('sha256', 'cleanup-valid')]) !== null);
    assert(one('SELECT id FROM login_history WHERE user_id=? AND logged_in_at=?', [$users[0], $times['old_login']]) === null);
    assert(one('SELECT id FROM login_history WHERE user_id=? AND logged_in_at=?', [$users[0], $times['cutoff']]) !== null);
    assert((int)one('SELECT COUNT(*) AS n FROM login_history WHERE user_id IN (?,?)', $users)['n'] === 2);
    assert((int)one('SELECT COUNT(*) AS n FROM password_resets WHERE user_id IN (?,?)', $users)['n'] === 2);
    assert((int)one('SELECT COUNT(*) AS n FROM organizations WHERE id IN (?,?)', $organizations)['n'] === 2);

    // Missing state is an explicit error rather than permanently skipped maintenance.
    query('DELETE FROM auth_cleanup_state WHERE id=1');
    try {
        cleanupAuthenticationData();
        throw new RuntimeException('Fehlender Bereinigungszustand wurde nicht gemeldet');
    } catch (ApiError $error) {
        assert($error->status === 503);
    } finally {
        query('INSERT INTO auth_cleanup_state(id,last_run_at) VALUES(1,?)', [$times['now']]);
    }
} finally {
    if ($lock?->inTransaction()) $lock->rollBack();
    if ($failureTrigger) db()->exec('DROP TRIGGER auth_cleanup_test_failure');
    foreach ($users as $userId) query('DELETE FROM users WHERE id=?', [$userId]);
    foreach ($organizations as $organizationId) query('DELETE FROM organizations WHERE id=?', [$organizationId]);
    query('UPDATE auth_cleanup_state SET last_run_at=? WHERE id=1', [$originalState]);
    db()->exec('SET timestamp=0');
    query('SET time_zone=?', [$originalTimezone]);
}
