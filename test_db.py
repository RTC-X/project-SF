import sqlite3, json
conn = sqlite3.connect('db.sqlite3')
cur = conn.cursor()
cur.execute('SELECT data FROM dashboard_globalmetadata WHERE key=''game_data''')
data = json.loads(cur.fetchone()[0])
print(list(data.keys()))
if 'Enchant1' in data: print(list(data['Enchant1'].items())[:2])
if 'Enchant' in data: print(list(data['Enchant'].items())[:2])
