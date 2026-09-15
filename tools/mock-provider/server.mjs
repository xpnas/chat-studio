// Deterministic OpenAI-compatible fixture. No external API keys or model calls.
// Bind only to loopback; NEVER expose this unauthenticated test provider publicly.
import http from 'node:http';
const port = Number(process.env.MOCK_PROVIDER_PORT || 18648);
const server = http.createServer(async (req, res) => {
  if (req.url === '/health') { res.end('ok'); return; }
  if (req.url === '/v1/models') {
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({object: 'list', data: [{id:'chatstudio-test',object:'model',owned_by:'local'}]})); return;
  }
  if (req.method === 'POST' && req.url === '/v1/audio/speech') {
    for await (const _ of req) { /* consume isolated fixture request */ }
    const audio = Buffer.alloc(32044);
    audio.write('RIFF', 0); audio.writeUInt32LE(32036, 4); audio.write('WAVEfmt ', 8);
    audio.writeUInt32LE(16, 16); audio.writeUInt16LE(1, 20); audio.writeUInt16LE(1, 22);
    audio.writeUInt32LE(16000, 24); audio.writeUInt32LE(32000, 28);
    audio.writeUInt16LE(2, 32); audio.writeUInt16LE(16, 34);
    audio.write('data', 36); audio.writeUInt32LE(32000, 40);
    res.writeHead(200, {'Content-Type': 'audio/wav'}); res.end(audio); return;
  }
  if (req.method === 'POST' && req.url === '/v1/audio/transcriptions') {
    let size = 0;
    for await (const chunk of req) { size += chunk.length; if (size > 4_000_000) { res.writeHead(413); res.end(); return; } }
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({text:'这是本地语音识别协议自测。'})); return;
  }
  if (req.method !== 'POST' || req.url !== '/v1/chat/completions') { res.writeHead(404);res.end();return; }
  let raw = '';
  for await (const chunk of req) { raw += chunk; if(raw.length > 2_000_000) {res.writeHead(413);res.end();return;} }
  let body;
  try { body=JSON.parse(raw); } catch {res.writeHead(400);res.end();return;}
  const last = JSON.stringify(body.messages?.findLast(m => m.role === 'user')?.content || '');
  const slow = last.includes('SLOW');
  const longResume = last.includes('LONG_FOREGROUND');
  const answer = longResume ? Array.from({length: 100}, (_, i) => `[${String(i).padStart(3, '0')}]`).join('') : '你好！这是本地协议自测回复。流式连接正常。';
  const base = {id:'chatcmpl-local-test',created:Math.floor(Date.now()/1000),model:'chatstudio-test'};
  if (!body.stream) {
    res.setHeader('Content-Type','application/json');
    res.end(JSON.stringify({...base,object:'chat.completion',choices:[{index:0,message:{role:'assistant',content:answer},finish_reason:'stop'}],usage:{prompt_tokens:10,completion_tokens:20,total_tokens:30}}));return;
  }
  res.writeHead(200,{'Content-Type':'text/event-stream','Cache-Control':'no-cache'});
  const send = (delta,finish_reason=null) => res.write(`data: ${JSON.stringify({...base,object:'chat.completion.chunk',choices:[{index:0,delta,finish_reason}]})}\n\n`);
  send({role:'assistant',content:''});
  let index=0;
  const timer=setInterval(() => {
    if(index<answer.length) {send({content:answer[index++]});return;}
    send({},'stop');res.end('data: [DONE]\n\n');clearInterval(timer);
  },longResume?20:slow?500:40);
  res.on('close',()=>clearInterval(timer));
});
server.listen(port,'127.0.0.1',()=>console.log(`Fixture ready on 127.0.0.1:${port}`));
process.on('SIGTERM',()=>server.close());
process.on('SIGINT',()=>server.close());
