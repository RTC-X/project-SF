import re
with open('dashboard/consumers.py', 'r') as f:
    code = f.read()

# Replace empty if blocks left by regex
code = re.sub(r'if owner_user:\s*\n[ \t]*(?=(elif|#|async|def|except|if|else))', 'pass\n', code)
code = re.sub(r'# Broadcast fleet size / status updates to owner\s*\n[ \t]*(?=(elif|#|async))', 'pass\n', code)

with open('dashboard/consumers.py', 'w') as f:
    f.write(code)
