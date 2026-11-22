// Stored-history fixtures only. These rows are not claimed as model executions.
import {DatabaseSync} from 'node:sqlite';
import {resolve,join,dirname,basename} from 'node:path';
import {randomUUID} from 'node:crypto';

const directory=resolve(process.env.HERMES_WEB_UI_TEST_DB_DIR||'.');
const state=dirname(directory);
if(process.env.NODE_ENV!=='test'||process.env.CHATSTUDIO_TEST_SERVER!=='http://127.0.0.1:18647'||basename(directory)!=='database'||! /^(contract-[a-f0-9]{32}|chatstudio-contract\.[A-Za-z0-9]+)$/.test(basename(state))||resolve(process.env.WORKSPACE_BASE||'.')!==join(state,'workspace'))throw Error('History seeding requires the runner-owned disposable state');
const [sessionId,peerId]=process.argv.slice(2);
const db=new DatabaseSync(join(directory,'hermes-web-ui.db'));
db.exec('PRAGMA busy_timeout=5000');
const session=db.prepare('SELECT * FROM sessions WHERE id=?').get(sessionId);
const peer=db.prepare('SELECT * FROM sessions WHERE id=?').get(peerId);
if(!sessionId?.startsWith('person-main-')||session?.title!=='Mobile Bot Cache'||!peer||String(peer.studio_user_id)!==String(session.studio_user_id)||session.message_count>0)throw Error('Expected a fresh, owned cache-fixture BOT');
const message=db.prepare("INSERT INTO messages(session_id,role,content,timestamp,finish_reason) VALUES(?,'assistant',?,?,'stop')");
const flow=db.prepare("INSERT INTO person_flows(id,owner_user_id,creator_session_id,title,goal,state,created_at,updated_at,timeline_at,workspace) VALUES(?,?,?,?,?,'completed',?,?,?,?)");
const stage=db.prepare("INSERT INTO person_stages(id,flow_id,position,group_position,session_id,goal,return_expectation,state) VALUES(?,?,0,0,?,?,?,'completed')");
db.exec('BEGIN');
try {
  const base=Date.now()-1_000_000;
  for(let index=0;index<225;index++){
    const timestamp=base+index*2000;
    message.run(sessionId,`Stored projected fixture ${index}`,timestamp/1000);
    const id=randomUUID();
    flow.run(id,Number(session.studio_user_id),sessionId,`Stored card ${index}`,'Stored timeline fixture',timestamp+1000,timestamp+1000,timestamp+1000,session.workspace);
    stage.run(randomUUID(),id,peerId,'Stored stage fixture','Visible record');
  }
  db.prepare('UPDATE sessions SET message_count=(SELECT COUNT(*) FROM messages WHERE session_id=?) WHERE id=?').run(sessionId,sessionId);
  db.exec('COMMIT');
}catch(error){db.exec('ROLLBACK');throw error;}
db.close();console.log('Seeded 450 mixed projected references in disposable storage.');
