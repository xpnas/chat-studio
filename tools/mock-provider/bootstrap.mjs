// Only for a newly initialized, disposable local server. Does not log tokens.
const origin = process.env.CHATSTUDIO_TEST_SERVER;
if (origin !== 'http://127.0.0.1:18647') throw Error('Fixture bootstrap requires loopback port 18647');
const password = process.env.CHATSTUDIO_TEST_PASSWORD;
if (!password || password.length < 16) throw Error('Set a random CHATSTUDIO_TEST_PASSWORD (16+ chars)');
let login;
for (let attempt = 0; attempt < 90; attempt++) {
  try {
    const response = await fetch(`${origin}/api/auth/login`, {
      method:'POST', headers:{'Content-Type':'application/json'},
      body:JSON.stringify({username:'admin',password:'123456'}),
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
const authenticated = await fetch(`${origin}/api/auth/login`, {
  method: 'POST', headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({username: 'admin', password}),
});
const authenticatedLogin = await authenticated.json();
if (!authenticated.ok || !authenticatedLogin.token) throw Error('Fixture login after rotation failed');
if (process.env.CHATSTUDIO_TEST_BASELINE === 'preview-agents') {
  const {fileURLToPath} = await import('node:url');
  const headers = {'Content-Type':'application/json', Authorization:`Bearer ${authenticatedLogin.token}`};
  async function api(path, method='GET', body) {
    const response = await fetch(`${origin}/api/studio/plugins${path}`, {method,headers,body:body && JSON.stringify(body)});
    if (!response.ok) throw Error(`Fixture plugin ${method} failed: HTTP ${response.status}: ${await response.text()}`);
    return response.json();
  }
  let snapshot = await api('');
  await api('/install','POST',{source:fileURLToPath(new URL('./plugin',import.meta.url)),trusted:true,revision:snapshot.revision});
  snapshot = await api('');
  await api('/mobile-fixture','PATCH',{enabled:true,revision:snapshot.revision});
}
const health = await fetch(`${origin}/health`);
if (!health.ok) throw Error(`Studio health check failed: HTTP ${health.status}`);
if (process.env.CHATSTUDIO_TEST_BASELINE !== 'legacy') {
  const {mkdir} = await import('node:fs/promises');
  const {join} = await import('node:path');
  const headers={'Content-Type':'application/json',Authorization:`Bearer ${authenticatedLogin.token}`};
  const shared=await (await fetch(`${origin}/api/studio/person`,{headers})).json();
  const configured=await fetch(`${origin}/api/studio/person/settings`,{method:'PUT',headers,body:JSON.stringify({expected_revision:shared.revision,agents:[{id:'mobile-fixture-worker',name:'Mobile fixture worker',description:'Controlled background execution fixture',selection:{runtime:'ekko',mode:'scoped',profile:'default',provider:'custom:mobile-test',model:'chatstudio-test',apiMode:'chat_completions'}}]})});
  if(!configured.ok)throw Error(`Fixture execution preset setup failed: HTTP ${configured.status}: ${await configured.text()}`);
  for (const name of ['Mobile Bot A','Mobile Bot B','Mobile Bot Cache','Mobile Bot Cache Peer','Mobile Flow A','Mobile Flow B','Mobile Flow C']) {
    const workspace=join(process.env.WORKSPACE_BASE,name.replaceAll(' ','-'));
    await mkdir(workspace,{recursive:true});
    const created=await fetch(`${origin}/api/studio/person/conversations`,{
      method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${authenticatedLogin.token}`},
      body:JSON.stringify({title:name,workspace,model:{profile:'default',provider:'custom:mobile-test',model:'chatstudio-test',apiMode:'chat_completions'}}),
    });
    if(!created.ok)throw Error(`Fixture BOT setup failed: HTTP ${created.status}: ${await created.text()}`);
  }
}
console.log(`Isolated Studio ready (${process.env.CHATSTUDIO_TEST_BASELINE}, ${process.env.CHATSTUDIO_TEST_SHA}); authenticated login and health checked.`);
