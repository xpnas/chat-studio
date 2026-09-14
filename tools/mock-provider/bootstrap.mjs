// Only for a newly initialized, disposable local server. Does not log tokens.
const origin = process.env.EKKO_TEST_SERVER;
if (origin !== 'http://127.0.0.1:18647') throw Error('Fixture bootstrap requires loopback port 18647');
const password = process.env.EKKO_TEST_PASSWORD;
if (!password || password.length < 16) throw Error('Set a random EKKO_TEST_PASSWORD (16+ chars)');
let login;
for (let attempt = 0; attempt < 90; attempt++) {
  try {
    const response = await fetch(`${origin}/api/auth/app-login`, {
      method:'POST', headers:{'Content-Type':'application/json'},
      body:JSON.stringify({username:'admin',password:'123456',device_code:'fixture-bootstrap',device_name:'Isolated CI fixture'}),
    });
    if (response.ok) {login=await response.json();break;}
  } catch { /* Server still starting. */ }
  await new Promise(resolve=>setTimeout(resolve,1000));
}
if (!login?.token) throw Error('Disposable Studio did not become ready');
const changed = await fetch(`${origin}/api/auth/change-password`, {
  method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${login.token}`},
  body:JSON.stringify({currentPassword:'123456',newPassword:password}),
});
if (!changed.ok) throw Error(`Could not rotate fixture password: HTTP ${changed.status}`);
console.log('Isolated Studio ready; bootstrap password rotated.');
