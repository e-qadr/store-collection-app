<?php
declare(strict_types=1);

// ضع قيمة قوية وطويلة هنا، ثم استخدم نفس القيمة في INVOICE_UPLOAD_TOKEN داخل التطبيق.
const UPLOAD_TOKEN = 'uP9xK7mQ2vR6sT4nY8bL3wZ5aH1cD0eF9gJ2kM7pX4qN8rS6';
const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10 MB

$allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png'];
$allowedMimeTypes = [
    'application/pdf',
    'image/jpeg',
    'image/png',
];

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, X-Upload-Token, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

function respond(int $status, array $payload): never
{
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function header_value(string $name): string
{
    $serverKey = 'HTTP_' . strtoupper(str_replace('-', '_', $name));
    return $_SERVER[$serverKey] ?? '';
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(405, ['ok' => false, 'error' => 'Method not allowed']);
}

$token = $_POST['token'] ?? header_value('X-Upload-Token');
$authorization = header_value('Authorization');
if ($token === '' && str_starts_with($authorization, 'Bearer ')) {
    $token = substr($authorization, 7);
}

if (!hash_equals(UPLOAD_TOKEN, (string) $token)) {
    respond(401, ['ok' => false, 'error' => 'Unauthorized upload request']);
}

if (!isset($_FILES['file']) || !is_uploaded_file($_FILES['file']['tmp_name'])) {
    respond(400, ['ok' => false, 'error' => 'No uploaded file']);
}

$file = $_FILES['file'];
if (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
    respond(400, ['ok' => false, 'error' => 'Upload failed']);
}

if (($file['size'] ?? 0) <= 0 || $file['size'] > MAX_FILE_SIZE) {
    respond(400, ['ok' => false, 'error' => 'File size is not allowed']);
}

$originalName = basename((string) $file['name']);
$extension = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));
if (!in_array($extension, $allowedExtensions, true)) {
    respond(400, ['ok' => false, 'error' => 'File extension is not allowed']);
}

$mimeType = mime_content_type($file['tmp_name']) ?: 'application/octet-stream';
if (!in_array($mimeType, $allowedMimeTypes, true)) {
    respond(400, ['ok' => false, 'error' => 'File type is not allowed']);
}

$requestId = preg_replace('/[^A-Za-z0-9_-]/', '', (string) ($_POST['request_id'] ?? 'general'));
if ($requestId === '') {
    $requestId = 'general';
}

$uploadRoot = __DIR__ . '/uploads/cash_expense_invoices';
$targetDir = $uploadRoot . '/' . $requestId;
if (!is_dir($targetDir) && !mkdir($targetDir, 0755, true) && !is_dir($targetDir)) {
    respond(500, ['ok' => false, 'error' => 'Cannot create upload directory']);
}

$safeBaseName = preg_replace('/[^A-Za-z0-9_.-]/', '_', pathinfo($originalName, PATHINFO_FILENAME));
$safeBaseName = trim((string) $safeBaseName, '._-');
if ($safeBaseName === '') {
    $safeBaseName = 'invoice';
}

$storedName = time() . '_' . bin2hex(random_bytes(6)) . '_' . $safeBaseName . '.' . $extension;
$targetPath = $targetDir . '/' . $storedName;

if (!move_uploaded_file($file['tmp_name'], $targetPath)) {
    respond(500, ['ok' => false, 'error' => 'Cannot save uploaded file']);
}

$scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
$host = $_SERVER['HTTP_HOST'] ?? '';
$scriptDir = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '')), '/');
$relativePath = $scriptDir . '/uploads/cash_expense_invoices/' . rawurlencode($requestId) . '/' . rawurlencode($storedName);
$url = $scheme . '://' . $host . $relativePath;

respond(200, [
    'ok' => true,
    'name' => $originalName,
    'path' => 'uploads/cash_expense_invoices/' . $requestId . '/' . $storedName,
    'url' => $url,
    'content_type' => $mimeType,
    'size' => (int) $file['size'],
]);
