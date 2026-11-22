import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const directory = resolve(process.argv[2]);
mkdirSync(directory, {recursive:true});
writeFileSync(join(directory,'config.toml'), `model = "chatstudio-test"
model_provider = "mobile-fixture"
approval_policy = "never"
sandbox_mode = "read-only"

[model_providers.mobile-fixture]
name = "Isolated local fixture"
base_url = "http://127.0.0.1:18648/v1"
wire_api = "responses"
env_key = "CHATSTUDIO_NATIVE_FIXTURE_KEY"
`, {mode:0o600, flag:'wx'});
