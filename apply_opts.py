import shutil
import re

shutil.copy('premium_scripts/autofarm_with_c2.lua', 'premium_scripts/autofarm_with_c2_no_lua_armor.lua')

with open('premium_scripts/autofarm_with_c2_no_lua_armor.lua', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Strip the strict check for LUARMOR_LICENSE (fallback to 'standalone')
content = content.replace(
    'local LUARMOR_LICENSE = (args[2] and type(args[2]) == "string" and args[2] ~= "") or (typeof(script_key) == "string" and script_key ~= "your_license_here" and script_key) or ""',
    'local LUARMOR_LICENSE = (args[2] and type(args[2]) == "string" and args[2] ~= "") or (typeof(script_key) == "string" and script_key ~= "your_license_here" and script_key) or "standalone"'
)

content = content.replace(
'''if not LUARMOR_LICENSE or LUARMOR_LICENSE == "" then
    warn("[!] Missing script_key! Please set script_key='.' before running the script.")
    return
end''', '')

# 2. Optimization 1: Remove firetouchinterest pcall blocks safely
content = re.sub(r'pcall\(function\(\)\s*if\s+firetouchinterest\s+then[\s\S]*?end\s*end\)', '-- firetouch pcall removed', content)

# 3. Optimization 2: C2 Sync loop reduced
content = content.replace('while task.wait(1) do\n                if not _G.LastC2SyncTime or tick() - _G.LastC2SyncTime >= 2 then', 'while task.wait(5) do\n                if not _G.LastC2SyncTime or tick() - _G.LastC2SyncTime >= 5 then')

# 4. Optimization 3: Turn off 3D Rendering by default
content = content.replace('RunService:Set3dRenderingEnabled(true)', '-- RunService:Set3dRenderingEnabled(true) -- disabled for max performance')

with open('premium_scripts/autofarm_with_c2_no_lua_armor.lua', 'w', encoding='utf-8', newline='') as f:
    f.write(content)
print("done")
