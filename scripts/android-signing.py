"""Write CI signing files without printing secrets or embedding them in source."""
import base64
import os
from pathlib import Path

required = ('KEYSTORE_BASE64', 'STORE_PASSWORD', 'KEY_PASSWORD', 'KEY_ALIAS', 'RUNNER_TEMP')
for key in required:
    if not os.environ.get(key):
        raise SystemExit(f'Missing required secret/environment variable: {key}')
keystore = Path(os.environ['RUNNER_TEMP']) / 'chatstudio-upload.jks'
keystore.write_bytes(base64.b64decode(os.environ['KEYSTORE_BASE64'], validate=True))
keystore.chmod(0o600)

def escape(value):
    # java.util.Properties escaping; do not permit injected properties/newlines.
    return ''.join('\\u%04x' % ord(c) if ord(c) > 126 else '\\' + c
                   if c in '\\:= #!' else '\\n' if c == '\n' else '\\r'
                   if c == '\r' else c for c in value)

values = {'storeFile': keystore.as_posix(), 'storePassword': os.environ['STORE_PASSWORD'],
          'keyPassword': os.environ['KEY_PASSWORD'], 'keyAlias': os.environ['KEY_ALIAS']}
path = Path('android/key.properties')
path.write_text(''.join(f'{key}={escape(value)}\n' for key, value in values.items()), encoding='ascii')
path.chmod(0o600)
