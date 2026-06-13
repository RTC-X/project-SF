import re

with open(r'c:\Users\Alex\Documents\GitHub\project-SF\premium_scripts\autofarm_with_c2.lua', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('getgenv()["LPH_NO_" .. "VIRTUALIZE"]', 'getgenv()[table.concat({"LPH", "_NO_", "VIRTUALIZE"})]')
content = re.sub(r'\.\.+\"', '."', content)
content = re.sub(r"\.\.+\'", ".'", content)

with open(r'c:\Users\Alex\Documents\GitHub\project-SF\premium_scripts\autofarm_with_c2.lua', 'w', encoding='utf-8', newline='') as f:
    f.write(content)
