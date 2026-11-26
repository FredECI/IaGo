# Publica o MVP 0.2 de uma vez. Rodar no PowerShell, em C:\IaGo:
#   powershell -ExecutionPolicy Bypass -File tool\publicar-mvp.ps1
# Faz: merge de feat/mvp na main e push; deploy das regras do Firestore e do
# site (build/web já gerado); espera o CI da main, baixa o APK e cria a release
# v0.2.0. Para no primeiro erro. Não lê nem imprime segredos.
$ErrorActionPreference = 'Stop'
$env:Path = "$env:USERPROFILE\dev\flutter\bin;$env:USERPROFILE\dev\gh\bin;$env:Path"
Set-Location C:\IaGo

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Check($what) { if ($LASTEXITCODE -ne 0) { throw "Falhou: $what" } }

if (-not (Test-Path build\web\index.html)) { throw 'Falta build\web. Peça ao Claude para gerar o build.' }
if ((git status --porcelain) -ne $null) { throw 'Há mudanças sem commit em C:\IaGo. Avise o Claude.' }

Step '1/4 Merge feat/mvp na main e push'
git fetch -q origin; Check 'fetch'
git checkout -q main; Check 'checkout main'
git pull -q --ff-only origin main; Check 'pull main'
git merge --no-ff -q origin/feat/mvp -m 'Merge feat/mvp: MVP 0.2 (Agrega, Direciona e Conecta)'; Check 'merge'
git push -q origin main; Check 'push main'
$sha = (git rev-parse HEAD).Trim()
git checkout -q feat/mvp

Step '2/4 Regras e índices do Firestore (iago-beta)'
firebase.cmd deploy --only firestore --project iago-beta; Check 'deploy firestore'

Step '3/4 Site (Hosting)'
firebase.cmd deploy --only hosting --project iago-beta; Check 'deploy hosting'

Step '4/4 APK: esperando o CI da main (cerca de 10 min)'
$runId = $null
for ($i = 0; $i -lt 30 -and -not $runId; $i++) {
  Start-Sleep 10
  $runs = gh run list --branch main --workflow CI --limit 5 --json databaseId,headSha | ConvertFrom-Json
  $runId = ($runs | Where-Object { $_.headSha -eq $sha } | Select-Object -First 1).databaseId
}
if (-not $runId) { throw 'O CI da main não apareceu. O site já está no ar; avise o Claude para fazer a release.' }
gh run watch $runId --exit-status; Check 'CI da main'
$dir = Join-Path $env:TEMP "iago-apk-$sha"
gh run download $runId -n iago-apk -D $dir; Check 'baixar APK'
Copy-Item "$dir\app-release.apk" "$dir\IaGo-MVP-0.2.apk" -Force
gh release create v0.2.0 "$dir\IaGo-MVP-0.2.apk" --target $sha --title 'IaGo MVP 0.2' --notes 'MVP de 27/11: Agrega, Direciona e Conecta (este último desligado em contas reais até haver moderação). IA na web para membros do piloto.'; Check 'release'

Write-Host "`nPronto. Site: https://iago-beta.web.app  APK: https://github.com/FredECI/IaGo/releases/tag/v0.2.0" -ForegroundColor Green
