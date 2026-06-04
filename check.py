import re

with open('premium_scripts/autofarm_with_c2.lua', 'r', encoding='utf-8') as f:
    lines_orig = f.readlines()

text = ''.join(lines_orig)
# remove multi-line comments
text = re.sub(r'--\[\[.*?\]\]', lambda m: '\n'*m.group(0).count('\n'), text, flags=re.DOTALL)
# remove single-line comments
text = re.sub(r'--.*', '', text)
# remove strings
text = re.sub(r'"(?:\\.|[^\\"])*"', '""', text)
text = re.sub(r"'(?:\\.|[^\\'])*'", "''", text)

lines = text.split('\n')
nesting = 0
for i, line in enumerate(lines):
    words = re.findall(r'\b[a-zA-Z_]\w*\b', line)
    for w in words:
        if w in ['if', 'function']:
            nesting += 1
        elif w == 'do':
            nesting += 1
        elif w == 'end':
            nesting -= 1
    if i > len(lines) - 20:
        print(f'{i+1}: nesting={nesting} | {lines_orig[i].strip()}')
