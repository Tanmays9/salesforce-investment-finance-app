"""Convert issuer CAS output to an exact-decimal, PII-minimal staging contract."""
from collections import Counter
from decimal import Decimal
import hashlib
from datetime import datetime

VERSION='cas-staging-1'

def exact(value):
    if value is None:return None
    number=Decimal(str(value))
    if not number.is_finite():raise ValueError('Nonfinite financial value')
    value=format(number,'f')
    if '.' in value:value=value.rstrip('0').rstrip('.')
    return '0' if value=='-0' else value

def day(value):
    if value is None:return None
    value=str(value)
    try:return datetime.strptime(value,'%d-%b-%Y').date().isoformat()
    except ValueError:return datetime.strptime(value[:10],'%Y-%m-%d').date().isoformat()

def normalise(data,file_hash):
    if data.get('file_type') not in ['CAMS','KFINTECH']:
        raise ValueError('This release supports verified CAMS/KFintech layouts; other issuer mappings require rehearsal')
    start=day(data['statement_period']['from']);end=day(data['statement_period']['to'])
    scopes=[]
    for folio in data.get('folios',[]):
        for scheme in folio.get('schemes',[]):
            isin=scheme.get('isin')
            scope=hashlib.sha256((str(folio['folio']).replace(' ','')+'|'+str(isin)).encode()).hexdigest()
            transactions=[];warnings=[];last=None;occurrences=Counter()
            for sequence,row in enumerate(scheme.get('transactions',[]),1):
                kind=row.get('type');units=exact(row.get('units'));amount=exact(row.get('amount'))
                if kind in ['STAMP_DUTY_TAX','STT_TAX']:
                    if last is None or last['tradeDate']!=day(row['date']):
                        warnings.append('Unattached charge at source sequence '+str(sequence));continue
                    charge={'kind':'stamp_duty' if kind=='STAMP_DUTY_TAX' else 'stt','amount':exact(abs(Decimal(amount))),'sequence':sequence}
                    last['charges'].append(charge)
                    if last['kind']=='purchase' and kind=='STAMP_DUTY_TAX':
                        last['cost']=exact(Decimal(last['cost'])+abs(Decimal(amount)))
                    continue
                if kind in ['PURCHASE','PURCHASE_SIP','REDEMPTION']:
                    if units is None or amount is None:raise ValueError('Unit transaction has missing financial fields')
                    if (kind=='REDEMPTION')!=(Decimal(units)<0):raise ValueError('Transaction type and unit sign disagree')
                    last={'sequence':sequence,'tradeDate':day(row['date']),'kind':'redemption' if kind=='REDEMPTION' else 'purchase',
                        'units':units,'amount':exact(abs(Decimal(amount))),'cost':exact(abs(Decimal(amount))) if Decimal(units)>0 else None,
                        'nav':exact(row.get('nav')),'balance':exact(row.get('balance')),'charges':[]}
                    key=(last['tradeDate'],last['kind'],last['units'],last['amount'])
                    occurrences[key]+=1;last['occurrence']=occurrences[key];transactions.append(last)
                elif units is not None and Decimal(units)!=0:
                    warnings.append('Unsupported unit movement '+str(kind)+' at source sequence '+str(sequence));last=None
                else:
                    # Non-unit notifications remain in the linked original statement; no economic event is invented.
                    last=None
            opening=exact(scheme.get('open'));closing=exact(scheme.get('close'))
            calculated=None if opening is None else Decimal(opening)+sum((Decimal(t['units']) for t in transactions),Decimal(0))
            if calculated is None or closing is None or calculated!=Decimal(closing):warnings.append('Opening units plus parsed movements do not equal closing units')
            if scheme.get('close_calculated') is not None and closing is not None and Decimal(str(scheme['close_calculated']))!=Decimal(closing):warnings.append('Issuer parser reports a closing-balance discrepancy')
            scopes.append({'scopeKey':scope,'isin':isin,'schemeName':scheme.get('scheme'),'periodStart':start,'periodEnd':end,
                'opening':opening,'closing':closing,'transactions':transactions,'warnings':warnings})
    if not scopes:raise ValueError('Statement contains no supported account scopes')
    return {'contractVersion':VERSION,'fileHash':file_hash,'parserVersion':'casparser-1.4.1','issuer':data['file_type'],
        'statementType':data.get('cas_type'),'warnings':data.get('parse_warnings',[]),'scopes':scopes}
