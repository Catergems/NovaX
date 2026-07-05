$interperterpath = ".\build\nvx.exe"

$i = 1
while ($i -le 9) {
    Write-Host "--------------------$i--------------------"
    & $interperterpath ".\example\example$i.nvx"
    $i++
}
