
import re

with open("templates/dashboard.html", "r", encoding="utf-8") as f:
    text = f.read()

for attr in ["x-show", "x-if", "x-text", "x-model", ":class"]:
    pattern = attr + r"=\"([^\"]*selectedBot\.[a-zA-Z][^\"]*)\""
    matches = re.finditer(pattern, text)
    for m in matches:
        print(attr, ":", m.group(1))

