// Deterministic engine for the pinned preview's real plugin host and run pipeline.
export function apply(ctx) {
  ctx.extensions.agents.register({
    id: 'echo', name: 'Mobile fixture', vendor: 'Contract tests', agentApiVersion: 1,
    getStatus: async () => ({installed:true, version:'1.0.0'}), management:{},
    modes:{global:{listModels:async () => ({status:'ready', source:'fixture', scope:'builtin', models:[{id:'fixture-alias', name:'Fixture alias', resolvedModel:'Fixture concrete', reasoningEfforts:[]}]})}},
    features:{surfaces:['chat'], streaming:true, resume:true},
    runtime:{createSession:() => ({
      async run(input, run) {
        if (run.mode !== 'global' || run.model.model !== 'fixture-alias') throw Error('Wrong execution configuration');
        const text = `PLUGIN_FIXTURE_OK history=${input.history.length}`;
        await run.output.emit({type:'text.delta',text});
        return {content:[{type:'text',text}],finishReason:'stop'};
      }, checkpoint: async () => ({schemaVersion:1,data:{fixture:true}}), dispose() {},
    })},
  });
}
