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
  if (req.method === 'POST' && req.url === '/v1/responses') {
    let raw = '';
    for await (const chunk of req) { raw += chunk; if(raw.length > 2_000_000) {res.writeHead(413);res.end();return;} }
    let body;
    try { body = JSON.parse(raw); } catch {res.writeHead(400);res.end();return;}
    const id = `resp-local-${Date.now()}`;
    const text = 'NATIVE_CODEX_FIXTURE_OK';
    const item = {id:`msg-${id}`,type:'message',role:'assistant',status:'completed',content:[{type:'output_text',text,annotations:[]}]};
    const response = {id,object:'response',created_at:Math.floor(Date.now()/1000),status:'completed',model:body.model || 'chatstudio-test',output:[item],usage:{input_tokens:10,output_tokens:5,total_tokens:15,input_tokens_details:{cached_tokens:0},output_tokens_details:{reasoning_tokens:0}}};
    if(!body.stream) {res.setHeader('Content-Type','application/json');res.end(JSON.stringify(response));return;}
    res.writeHead(200,{'Content-Type':'text/event-stream','Cache-Control':'no-cache'});
    let sequence=0;
    const send = event => res.write(`event: ${event.type}\ndata: ${JSON.stringify({...event,sequence_number:sequence++})}\n\n`);
    send({type:'response.created',response:{...response,status:'in_progress',output:[]}});
    send({type:'response.output_item.added',output_index:0,item:{...item,status:'in_progress',content:[]}});
    send({type:'response.content_part.added',item_id:item.id,output_index:0,content_index:0,part:{type:'output_text',text:'',annotations:[]}});
    send({type:'response.output_text.delta',item_id:item.id,output_index:0,content_index:0,delta:text});
    send({type:'response.output_text.done',item_id:item.id,output_index:0,content_index:0,text});
    send({type:'response.content_part.done',item_id:item.id,output_index:0,content_index:0,part:item.content[0]});
    send({type:'response.output_item.done',output_index:0,item});
    send({type:'response.completed',response});res.end();return;
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
  let answer = longResume ? Array.from({length: 100}, (_, i) => `[${String(i).padStart(3, '0')}]`).join('') : '你好！这是本地协议自测回复。流式连接正常。';
  const base = {id:'chatcmpl-local-test',created:Math.floor(Date.now()/1000),model:'chatstudio-test'};
  // The pinned Studio executes every tool, persists its result, and verifies the
  // live stage/run ownership. This provider supplies deterministic decisions;
  // it never edits the DB or fabricates server completion events.
  const input = body.messages?.findLast(m => m.role === 'user')?.content;
  const closedLoop = JSON.stringify(body.messages).includes('BOT_FLOW_CLOSED_LOOP');
  if (closedLoop && body.messages.some(m => m.role === 'system' && String(m.content).includes('Confirm ONLY the status of your already saved reply'))) {
    answer = JSON.stringify({status:'complete',reason:'The fixture stage requested exactly the saved fixture result.'});
  } else if (closedLoop && typeof input === 'string' && input.startsWith('Handle the assigned stage supplied in context.') && body.tools?.some(t => t.function?.name === 'bot_flows_query')) {
    const start = body.messages.findLastIndex(m => m.role === 'user');
    const results = body.messages.slice(start + 1).filter(m => m.role === 'tool');
    const flowId = /"flow_id"\s*:\s*"([^"]+)"/.exec(input)?.[1];
    let call;
    if (results.length === 0) call = {name:'bot_flows_query',arguments:JSON.stringify({flow_id:flowId})};
    else if (results.length === 1) {
      const result = JSON.parse(results[0].content);
      const flow = result.flows?.[0];
      if (!flow?.allowed_actions?.includes('complete')) throw Error('Fixture stage has no authorized complete action');
      call = {name:'bot_flow_control',arguments:JSON.stringify({action:'complete',flow_ref:flow.flow_ref})};
    }
    if (call) {
      const toolCall = {id:`flow-fixture-${results.length}`,type:'function',function:call};
      if (body.stream) {
        res.writeHead(200,{'Content-Type':'text/event-stream'});
        for(const [delta,finish_reason] of [[{role:'assistant',tool_calls:[{index:0,...toolCall}]},null],[{},'tool_calls']]) res.write(`data: ${JSON.stringify({...base,object:'chat.completion.chunk',choices:[{index:0,delta,finish_reason}]})}\n\n`);
        res.end('data: [DONE]\n\n');
      } else {res.setHeader('Content-Type','application/json');res.end(JSON.stringify({...base,object:'chat.completion',choices:[{index:0,message:{role:'assistant',content:null,tool_calls:[toolCall]},finish_reason:'tool_calls'}],usage:{prompt_tokens:10,completion_tokens:20,total_tokens:30}}));}
      return;
    }
    answer = 'BOT_FLOW_CLOSED_LOOP fixture result delivered.';
  }
  if (last.includes('BOT_DURABLE_QUESTION') && body.tools?.some(tool => tool.function?.name === 'clarify')) {
    const start=body.messages.findLastIndex(message=>message.role==='user');
    if(!body.messages.slice(start+1).some(message=>message.role==='tool')) {
      const call={id:'bot-durable-fixture',type:'function',function:{name:'clarify',arguments:JSON.stringify({question:'Choose the fixture delivery format',choices:['A','B']})}};
      if(body.stream){res.writeHead(200,{'Content-Type':'text/event-stream'});for(const [delta,finish_reason] of [[{role:'assistant',tool_calls:[{index:0,...call}]},null],[{},'tool_calls']])res.write(`data: ${JSON.stringify({...base,object:'chat.completion.chunk',choices:[{index:0,delta,finish_reason}]})}\n\n`);res.end('data: [DONE]\n\n');}
      else{res.setHeader('Content-Type','application/json');res.end(JSON.stringify({...base,object:'chat.completion',choices:[{index:0,message:{role:'assistant',content:null,tool_calls:[call]},finish_reason:'tool_calls'}],usage:{prompt_tokens:10,completion_tokens:20,total_tokens:30}}));}
      return;
    }
  }
  if (last.includes('BOT_RESULT_ATTACHMENT') && body.tools?.some(tool => tool.function?.name === 'write_file')) {
    const start = body.messages.findLastIndex(message => message.role === 'user');
    const written = body.messages.slice(start + 1).some(message => message.role === 'assistant' && message.tool_calls?.some(call => call.function?.name === 'write_file'));
    if (!written) {
      const toolCall = {id:'bot-result-file',type:'function',function:{name:'write_file',arguments:JSON.stringify({path:'mobile-result.txt',content:'BOT_RESULT_ATTACHMENT verified fixture artifact.'})}};
      if(body.stream){res.writeHead(200,{'Content-Type':'text/event-stream'});for(const [delta,finish_reason] of [[{role:'assistant',tool_calls:[{index:0,...toolCall}]},null],[{},'tool_calls']])res.write(`data: ${JSON.stringify({...base,object:'chat.completion.chunk',choices:[{index:0,delta,finish_reason}]})}\n\n`);res.end('data: [DONE]\n\n');}
      else{res.setHeader('Content-Type','application/json');res.end(JSON.stringify({...base,object:'chat.completion',choices:[{index:0,message:{role:'assistant',content:null,tool_calls:[toolCall]},finish_reason:'tool_calls'}],usage:{prompt_tokens:10,completion_tokens:20,total_tokens:30}}));}
      return;
    }
    const result = body.messages.findLast(message => message.role === 'tool').content;
    const path = /^Wrote \d+ bytes to ([\s\S]+)$/.exec(result)?.[1];
    if (!path) throw Error('The real write_file result did not contain the artifact path');
    answer = `BOT_RESULT_ATTACHMENT [mobile-result.txt](/api/studio/files/download?path=${encodeURIComponent(path)})`;
  }
  if (last.includes('SESSION_GOAL_CONTRACT') && body.tools?.some(t => t.function?.name === 'list_session_tasks')) {
    const start = body.messages.findLastIndex(m => m.role === 'user');
    const toolResults = body.messages.slice(start + 1).filter(m => m.role === 'tool');
    const toolNames = (body.tools || []).map(t => t.function?.name);
    if (!toolNames.includes('update_session_tasks')) {res.writeHead(400);res.end('Goal fixture requires goal tools');return;}
    let call;
    if (toolResults.length === 0) call=Array.from({length:65},(_,index)=>({id:`goal-list-fixture-${index}`,type:'function',function:{name:'list_session_tasks',arguments:'{}'}}));
    if (toolResults.length === 65) {
      const result=JSON.parse(toolResults[0].content);
      const snapshot=result.snapshot || result;
      call={id:'goal-update-fixture',type:'function',function:{name:'update_session_tasks',arguments:JSON.stringify({revision:snapshot.revision,changes:[{title:'Verify mobile goals',summary:'Verify state and evidence deletion on two clients',status:'completed',completion_evidence:'Verified fixture ledger'}]})}};
    }
    if (call) {
      const calls = Array.isArray(call) ? call : [call];
      res.setHeader('Content-Type','application/json');
      if (body.stream) {
        res.setHeader('Content-Type','text/event-stream');
        for (const [delta,finish_reason] of [[{role:'assistant',tool_calls:calls.map((call,index)=>({index,...call}))},null],[{},'tool_calls']]) res.write(`data: ${JSON.stringify({...base,object:'chat.completion.chunk',choices:[{index:0,delta,finish_reason}]})}\n\n`);
        res.end('data: [DONE]\n\n');
      } else res.end(JSON.stringify({...base,object:'chat.completion',choices:[{index:0,message:{role:'assistant',content:null,tool_calls:calls},finish_reason:'tool_calls'}],usage:{prompt_tokens:10,completion_tokens:20,total_tokens:30}}));
      return;
    }
  }
  // Exercise Studio's real update_plan tool and persistence, not fabricated
  // socket events. Only this sentinel activates tool calls in the fixture.
  if (last.includes('TASK_PLAN_CONTRACT')) {
    const start = body.messages.findLastIndex(m => m.role === 'user');
    const updates = body.messages.slice(start + 1).filter(m => m.role === 'tool').length;
    if (updates < 2) {
      const call = {id:`plan-fixture-${updates}`,type:'function',function:{name:'update_plan',arguments:JSON.stringify({
        explanation:'Local task-plan contract verification',
        plan:[
          {id:'inspect',step:'Inspect the contract',status:'completed'},
          {id:'verify',step:'Verify reconnect and persistence',status:updates === 0 ? 'in_progress' : 'completed'},
        ],
      })}};
      // Give the mobile test time to disconnect after the first committed plan.
      if (updates === 1) await new Promise(resolve => setTimeout(resolve, 2500));
      if (!body.stream) {
        res.setHeader('Content-Type','application/json');
        res.end(JSON.stringify({...base,object:'chat.completion',choices:[{index:0,message:{role:'assistant',content:null,tool_calls:[call]},finish_reason:'tool_calls'}],usage:{prompt_tokens:10,completion_tokens:20,total_tokens:30}}));
      } else {
        res.writeHead(200,{'Content-Type':'text/event-stream','Cache-Control':'no-cache'});
        for (const [delta,finish_reason] of [[{role:'assistant',tool_calls:[{index:0,...call}]},null],[{},'tool_calls']]) {
          res.write(`data: ${JSON.stringify({...base,object:'chat.completion.chunk',choices:[{index:0,delta,finish_reason}]})}\n\n`);
        }
        res.end('data: [DONE]\n\n');
      }
      return;
    }
  }
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
