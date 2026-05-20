with open('flutter_client/lib/screens/chat_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if '_scanDocument' in line:
        print(f"Line {i+1}: {line.strip()}")
