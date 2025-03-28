@echo off

bcdedit /export BCD_modded

bcdedit /store BCD_modded /create /d "softreboot" /application startup>GUID.txt
For /F "tokens=2 delims={}" %%i in (GUID.txt) do (set REBOOT_GUID=%%i)
del GUID.txt

bcdedit /store BCD_modded /set {%REBOOT_GUID%} path "\shimx64.efi"
bcdedit /store BCD_modded /set {%REBOOT_GUID%} device boot
bcdedit /store BCD_modded /set {%REBOOT_GUID%} pxesoftreboot yes

bcdedit /store BCD_modded /set {default} recoveryenabled yes
bcdedit /store BCD_modded /set {default} recoverysequence {%REBOOT_GUID%}
bcdedit /store BCD_modded /set {default} path "\\"
bcdedit /store BCD_modded /set {default} winpe yes

bcdedit /store BCD_modded /displayorder {%REBOOT_GUID%} /addlast


move BCD_modded S:\BCD
echo "BCD file was moved to S:\BCD"
echo "You can now exit and restart into PXE / Network Boot"

pause
