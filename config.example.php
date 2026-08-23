<?php

// Copy to config.local.php on hosts without environment-variable support.
// Generate setup_token with: php -r "echo bin2hex(random_bytes(32));"
return [
    'dsn' => 'mysql:host=localhost;dbname=einsatzberichte;charset=utf8mb4',
    'user' => 'database-user',
    'password' => 'database-password',
    'setup_token' => '',
    'app_url' => 'https://einsatzberichte.example.org',
    'mail_from' => 'einsatzberichte@example.org',
    // Optional SMTP fallback for hosts where PHP mail() is unavailable or unreliable.
    // 'smtp_host' => 'smtp.strato.de',
    // 'smtp_port' => 587,
    // 'smtp_username' => 'einsatzberichte@example.org',
    // 'smtp_password' => 'email-password',
];
