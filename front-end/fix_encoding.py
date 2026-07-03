
import sys

file_path = r'c:\grad_project\front-end\lib\text_to_sign_screen.dart'
try:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    if content.startswith('\ufeff'):
        content = content[1:]
        
    restored = content.encode('cp1252').decode('utf-8')
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(restored)
    print('Fixed successfully!')
except Exception as e:
    print('Error:', e)

