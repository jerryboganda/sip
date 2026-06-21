# =============================================================================
# 00-ssh-discovery.ps1 — RUN ON YOUR LOCAL WINDOWS PC, read-only.
# Helps locate the SSH key for the VPS. Never paste private keys anywhere.
# =============================================================================
$HostIp   = '185.252.233.186'
$HostFqdn = 'sip.polytronx.com'

Write-Host '== SSH keys in %USERPROFILE%\.ssh ==' -ForegroundColor Cyan
Get-ChildItem "$env:USERPROFILE\.ssh" -Force -ErrorAction SilentlyContinue |
    Format-Table Mode, Length, LastWriteTime, Name -AutoSize

Write-Host '== Loaded ssh-agent identities ==' -ForegroundColor Cyan
ssh-add -l 2>$null

Write-Host '== References to the host in ssh config/keys ==' -ForegroundColor Cyan
Select-String -Path "$env:USERPROFILE\.ssh\config", "$env:USERPROFILE\.ssh\*" `
    -Pattern "$HostIp|$HostFqdn" -ErrorAction SilentlyContinue

Write-Host ''
Write-Host 'Test the connection with:'
Write-Host "  ssh -o IdentitiesOnly=yes root@$HostIp"
Write-Host "  ssh -i `"$env:USERPROFILE\.ssh\YOUR_KEY_FILE`" -o IdentitiesOnly=yes root@$HostIp"
