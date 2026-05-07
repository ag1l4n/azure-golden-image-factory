Write-Output "Running Sysprep to generalize the image..."
& $env:SystemRoot\System32\Sysprep\Sysprep.exe /oobe /generalize /quiet /quit
