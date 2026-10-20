pwsh Remove-Item -Path ./grid.png
pwsh ./masks-convert.ps1 .
pwsh ./invert-alpha.ps1 .
pwsh ./downscale_png.ps1 . 2048 1024
pwsh ./downscale_png.ps1 . 1024 0512
pwsh ./png-compress.ps1 .
pwsh ./gridify.ps1 .\BepInEx\plugins\7Bpencil.WeaponCamoAndStickers\textures\camos\procedural-camos-v2 -SearchString 2048 -ExcludeString inv -TileSize 512 -Columns 1 -Output grid-camos.png
pwsh ./gridify.ps1 .\BepInEx\plugins\7Bpencil.WeaponCamoAndStickers\textures\masks\procedural-camos-v2 -SearchString 2048 -ExcludeString inv -TileSize 512 -Columns 1 -Output grid-masks.png
