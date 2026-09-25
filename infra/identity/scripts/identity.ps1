[CmdletBinding()]
param(
    [ValidateSet("start", "stop", "status", "logs", "reset", "health", "smoke")]
    [string]$Action = "status"
)

$ErrorActionPreference = "Stop"
$IdentityRoot = Split-Path -Parent $PSScriptRoot
$ComposeFile = Join-Path $IdentityRoot "docker-compose.yml"
$EnvFile = Join-Path $IdentityRoot ".env"

function Invoke-Compose {
    $ComposeArgs = $args
    & docker compose --env-file $EnvFile -f $ComposeFile @ComposeArgs
    if ($LASTEXITCODE -ne 0) { throw "docker compose failed with exit code $LASTEXITCODE" }
}

function Assert-LocalEnvironment {
    if (-not (Test-Path -LiteralPath $EnvFile)) {
        throw "Missing infra/identity/.env. Copy .env.example to .env and set a local secret first."
    }
    $match = [regex]::Match((Get-Content -LiteralPath $EnvFile -Raw), '(?m)^POSTGRES_PASSWORD=([A-Za-z0-9_-]+)$')
    if (-not $match.Success -or $match.Groups[1].Value.Length -lt 32) {
        throw "POSTGRES_PASSWORD must be at least 32 URL-safe characters (letters, digits, _ or -). Its value is never printed."
    }
}

function Get-LocalValue([string]$Name, [string]$Default) {
    $match = [regex]::Match((Get-Content -LiteralPath $EnvFile -Raw), "(?m)^$([regex]::Escape($Name))=(.*)$")
    if ($match.Success -and $match.Groups[1].Value.Trim()) { return $match.Groups[1].Value.Trim() }
    return $Default
}

function Test-Endpoints {
    $core = Get-LocalValue "LOGTO_ENDPOINT" "http://127.0.0.1:3001"
    $admin = Get-LocalValue "LOGTO_ADMIN_ENDPOINT" "http://127.0.0.1:3002"
    $discovery = Invoke-RestMethod -Uri "$($core.TrimEnd('/'))/oidc/.well-known/openid-configuration" -TimeoutSec 10
    if (-not $discovery.issuer -or -not $discovery.authorization_endpoint) { throw "OIDC discovery response is incomplete." }
    $adminRequest = [System.Net.HttpWebRequest]::Create($admin)
    $adminRequest.AllowAutoRedirect = $false
    $adminRequest.Timeout = 10000
    $adminResponse = $adminRequest.GetResponse()
    if ([int]$adminResponse.StatusCode -ge 400) { throw "Admin Console returned HTTP $([int]$adminResponse.StatusCode)." }
    $adminResponse.Close()
    Write-Output "PostgreSQL: healthy (checked by Compose)"
    Write-Output "Logto core and OIDC discovery: reachable"
    Write-Output "Admin Console: reachable"
    Write-Output "Core endpoint: $core"
    Write-Output "Admin endpoint: $admin"
}

Assert-LocalEnvironment

switch ($Action) {
    "start" { Invoke-Compose up -d --wait; Test-Endpoints }
    "stop" { Invoke-Compose stop }
    "status" { Invoke-Compose ps }
    "logs" { Invoke-Compose logs --follow --tail 100 }
    "health" { Invoke-Compose ps; Test-Endpoints }
    "reset" {
        $confirmation = Read-Host "This deletes the LOCAL Logto PostgreSQL volume. Type RESET to continue"
        if ($confirmation -cne "RESET") { throw "Reset cancelled; local identity data was not changed." }
        Invoke-Compose down --volumes --remove-orphans
        Invoke-Compose up -d --wait
        Test-Endpoints
    }
    "smoke" {
        Test-Endpoints
        $marker = [guid]::NewGuid().ToString("N")
        $dbUser = Get-LocalValue "POSTGRES_USER" "logto"
        $dbName = Get-LocalValue "POSTGRES_DB" "logto"
        Invoke-Compose exec -T postgres psql -U $dbUser -d $dbName -v ON_ERROR_STOP=1 -c "CREATE TABLE IF NOT EXISTS public.fireseed_identity_smoke (id text PRIMARY KEY); ALTER TABLE public.fireseed_identity_smoke ENABLE ROW LEVEL SECURITY; INSERT INTO public.fireseed_identity_smoke VALUES ('$marker');"
        Invoke-Compose restart postgres
        $ready = $false
        for ($attempt = 0; $attempt -lt 30; $attempt++) {
            & docker compose --env-file $EnvFile -f $ComposeFile exec -T postgres sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' *> $null
            if ($LASTEXITCODE -eq 0) { $ready = $true; break }
            Start-Sleep -Seconds 2
        }
        if (-not $ready) { throw "PostgreSQL did not recover after restart." }
        Invoke-Compose restart logto
        $found = $false
        for ($attempt = 0; $attempt -lt 45; $attempt++) {
            $queryResult = & docker compose --env-file $EnvFile -f $ComposeFile exec -T postgres psql -U $dbUser -d $dbName -tAc "SELECT 1 FROM public.fireseed_identity_smoke WHERE id='$marker'"
            if ($LASTEXITCODE -eq 0 -and (($queryResult -join "").Trim() -eq "1")) { $found = $true; break }
            Start-Sleep -Seconds 2
        }
        if (-not $found) { throw "Smoke marker did not survive the PostgreSQL restart." }
        $reachable = $false
        for ($attempt = 0; $attempt -lt 45; $attempt++) {
            try { Test-Endpoints; $reachable = $true; break } catch { Start-Sleep -Seconds 2 }
        }
        if (-not $reachable) { throw "Logto did not recover after restart; inspect the local container logs." }
        Invoke-Compose exec -T postgres psql -U $dbUser -d $dbName -v ON_ERROR_STOP=1 -c "DELETE FROM public.fireseed_identity_smoke WHERE id='$marker'; DROP TABLE IF EXISTS public.fireseed_identity_smoke;"
        Write-Output "Persistence smoke passed: a local-only marker survived PostgreSQL and Logto restart."
    }
}
