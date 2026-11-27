"""Validate a bank-supplied private configuration without logging credentials."""
import json, os, pathlib, re, sys, urllib.parse

def prepare(raw, directory, allow_pending_registration=False):
    if not raw:
        return None
    c = json.loads(raw)
    if c.get('enabled') is False:
        raise ValueError('Use an explicit reviewed disable operation')
    if c.get('environment') not in ('sandbox', 'production'):
        raise ValueError('Invalid BCC environment')
    if not re.fullmatch(r'\d{8}', str(c.get('terminal', ''))) or not re.fullmatch(r'[A-Za-z0-9]{1,15}', str(c.get('merchant', ''))):
        raise ValueError('Invalid BCC terminal')
    if not isinstance(c.get('mac_key'), str) or not re.fullmatch(r'(?:[a-fA-F0-9]{2}){16,32}', c['mac_key']):
        raise ValueError('Invalid BCC signing key')
    if c['environment']=='production' and (c['terminal'] in ('88888881','88888888') or c['mac_key'].upper()=='6BB0AC02E47BDF73D98FEB777F3B5294'):
        raise ValueError('Sandbox credentials forbidden in production')
    bank_managed=c.get('notification_mode')=='bank-managed' and c.get('notifications_registered') is True and not c.get('notify_user') and not c.get('notify_password')
    if c.get('notification_mode') not in (None,'http-basic','bank-managed'):
        raise ValueError('Invalid bank notification mode')
    if c['environment']=='production' and not bank_managed and (not c.get('notify_user') or not c.get('notify_password') or c.get('callback_registered') is not True) and not (allow_pending_registration and c.get('notify_user') and c.get('notify_password') and c.get('callback_registered') is False):
        raise ValueError('Registered bank notifications required')
    if c.get('notify_user') or c.get('notify_password'):
        if not re.fullmatch(r'[A-Za-z0-9_.-]{3,80}',c.get('notify_user','')) or not isinstance(c.get('notify_password'),str) or len(c['notify_password'])<16 or any(v in c['notify_password'] for v in ('\r','\n')):
            raise ValueError('Invalid callback credentials')
    origin = urllib.parse.urlparse(c.get('public_origin', ''))
    if origin.scheme != 'https' or origin.hostname != 'joba.com.kz' or origin.port not in (None,443) or origin.username or origin.password or origin.path not in ('','/') or origin.query or origin.fragment:
        raise ValueError('Invalid public return origin')
    for field, default, allowed in [('countries',['KZ'],{'KZ','KG'}),('currencies',['KZT'],{'KZT','KGS'})]:
        values=c.get(field,default)
        if not isinstance(values,list) or not values or any(not isinstance(x,str) or x not in allowed for x in values):
            raise ValueError('Invalid BCC country or currency agreement')
        c[field]=values
    # The public host/endpoint comes from the selected environment in code.
    # Do not accept caller-provided destinations or local journal paths.
    c={key:c[key] for key in ['environment','terminal','merchant','mac_key','public_origin','countries','currencies','notify_user','notify_password','callback_registered','notification_mode','notifications_registered'] if key in c}
    target=pathlib.Path(directory);target.mkdir(parents=True,exist_ok=True,mode=0o700)
    path=target/'bcc.json'
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
    with os.fdopen(fd,'w') as f:json.dump(c,f)
    os.chmod(path,0o600)
    return path

if __name__=='__main__':
    path=prepare(os.environ.get('JOBA_BCC_CONFIG_JSON',''),sys.argv[1])
    print('Private BCC configuration prepared' if path else 'Existing bank configuration preserved')
