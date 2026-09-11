import psycopg2

DATABASE_URL = "postgresql://neondb_owner:npg_3OxmCSbQnf2U@ep-flat-frog-a5j1ayb0.us-east-2.aws.neon.tech/neondb?sslmode=require"
conn = psycopg2.connect(DATABASE_URL)
cur = conn.cursor()
cur.execute('SELECT COUNT(*) FROM "Video" WHERE metadata IS NOT NULL;')
done = cur.fetchone()[0]
cur.execute('SELECT COUNT(*) FROM "Video";')
total = cur.fetchone()[0]
print(f"Progress: {done}/{total} videos have metadata ({100*done//total if total else 0}%)")
cur.close()
conn.close()
