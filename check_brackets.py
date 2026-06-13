import re

def check_brackets(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Remove strings and comments carefully
    # We will just iterate char by char
    
    in_string = False
    string_char = ''
    in_comment = False
    in_multi_comment = False
    in_multi_string = False
    
    clean = ""
    i = 0
    while i < len(content):
        c = content[i]
        
        if not in_string and not in_comment and not in_multi_comment and not in_multi_string:
            if c == '"' or c == "'":
                in_string = True
                string_char = c
            elif c == '-' and i+1 < len(content) and content[i+1] == '-':
                if i+3 < len(content) and content[i+2] == '[' and content[i+3] == '[':
                    in_multi_comment = True
                    i += 3
                else:
                    in_comment = True
                    i += 1
            elif c == '[' and i+1 < len(content) and content[i+1] == '[':
                in_multi_string = True
                i += 1
            else:
                clean += c
        elif in_string:
            if c == '\\':
                i += 1
            elif c == string_char:
                in_string = False
        elif in_comment:
            if c == '\n':
                in_comment = False
                clean += '\n'
        elif in_multi_comment:
            if c == ']' and i+1 < len(content) and content[i+1] == ']':
                in_multi_comment = False
                i += 1
        elif in_multi_string:
            if c == ']' and i+1 < len(content) and content[i+1] == ']':
                in_multi_string = False
                i += 1
                
        i += 1

    stack = []
    brackets = {'}': '{', ']': '[', ')': '('}
    lines = clean.split('\n')
    
    for i, line in enumerate(lines):
        for char in line:
            if char in '{[(':
                stack.append((char, i + 1))
            elif char in '}])':
                if not stack:
                    print(f"Error: Unmatched closing bracket '{char}' at line {i + 1}")
                    return
                top, line_num = stack.pop()
                if top != brackets[char]:
                    print(f"Error: Mismatched brackets. Expected '{brackets[char]}' to match '{top}' from line {line_num}, but found '{char}' at line {i + 1}")
                    return
    
    if stack:
        print("Error: Unmatched opening brackets:")
        for char, line_num in stack:
            print(f"  '{char}' opened at line {line_num}")
    else:
        print("All brackets match perfectly!")

check_brackets(r'c:\Users\Alex\Documents\GitHub\project-SF\premium_scripts\autofarm_with_c2.lua')
