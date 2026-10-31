"""Administrative index/evaluation runner. Credentials come only from environment.
SUPABASE_URL=https://<project>.supabase.co SUPABASE_SERVICE_ROLE_KEY=<secret>
python3 scripts/smart_service_apache.py index
python3 scripts/smart_service_apache.py evaluate 'Install 300 SF of LVP flooring'
Never ship the service key in the iOS app or commit it to the repository.
"""
import json, os, sys, urllib.request, urllib.error

def call(body):
    key = os.environ['SUPABASE_SERVICE_ROLE_KEY']
    request = urllib.request.Request(
        os.environ['SUPABASE_URL'].rstrip('/') + '/functions/v1/smart-service-apache',
        data=json.dumps(body).encode(),
        headers={'Authorization': 'Bearer ' + key, 'apikey': key, 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(request, timeout=380) as response:
            result = json.loads(response.read())
    except urllib.error.HTTPError as error:
        raise RuntimeError('Apache HTTP error ' + str(error.code)) from None
    if 'error' in result:
        raise RuntimeError(result['error'])
    return result

if __name__ == '__main__':
    operation = sys.argv[1] if len(sys.argv) > 1 else ''
    if operation == 'index':
        while True:
            result = call({'operation': 'index'})
            print(json.dumps(result), flush=True)
            if result['done']:
                break
    elif operation == 'evaluate' and len(sys.argv) == 3:
        print(json.dumps(call({'operation': 'evaluate', 'scope': sys.argv[2], 'markup_percent': 0}), indent=2))
    else:
        raise SystemExit('Use index or evaluate "scope text"')
