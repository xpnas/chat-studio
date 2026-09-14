// Deterministic OpenAI-compatible fixture. No external API keys or model calls.
// Bind only to loopback; NEVER expose this unauthenticated test provider publicly.
import http from 'node:http';
const port = Number(process.env.MOCK_PROVIDER_PORT || 18648);
const server = http.createServer(async (req, res) => {
  if (req.url === '/health') { res.end('ok'); return; }
  if (req.url === '/v1/models') {
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({object: 'list', data: [{id:'ekko-test',object:'model',owned_by:'local'}]})); return;
  }
  if (req.method !== 'POST' || req.url !== '/v1/chat/completions') { res.writeHead(404);res.end();return; }
  let raw = '';
  for await (const chunk of req) { raw += chunk; if(raw.length > 2_000_000) {res.writeHead(413);res.end();return;} }
  let body;
  try { body=JSON.parse(raw); } catch {res.writeHead(400);res.end();return;}
  const last = JSON.stringify(body.messages?.findLast(m => m.role === 'user')?.content || '');
  const slow = last.includes('SLOW');
  const answer = '你好！这是本地协议自测回复。流式连接正常。';
  const base = {id:'chatcmpl-local-test',created:Math.floor(Date.now()/1000),model:'ekko-test'};
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
  },slow?500:40);
  res.on('close',()=>clearInterval(timer));
});
server.listen(port,'127.0.0.1',()=>console.log(`Fixture ready on 127.0.0.1:${port}`));
process.on('SIGTERM',()=>server.close());
process.on('SIGINT',()=>server.close());
