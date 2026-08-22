<?php

// Copy to config.local.php on hosts without environment-variable support.
// Generate setup_token with: php -r "echo bin2hex(random_bytes(32));"
return [
    'dsn' => 'mysql:host=localhost;dbname=divera;charset=utf8mb4',
    'user' => 'database-user',
    'password' => 'database-password',
    'setup_token' => '',
    'app_url' => 'https://einsatzberichte.example.org',
    'mail_from' => 'einsatzberichte@example.org',
];
