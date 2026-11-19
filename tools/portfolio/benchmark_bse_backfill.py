"""Import official BSE 500 TRI observations with source verification and resumable idempotent batches."""
import argparse
import datetime as dt
import decimal
import hashlib
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'investment-migration'))
from org_config import allowed_org_ids
from migrate import Salesforce
from prepare import PRIVATE

ALLOWED_ORGS = allowed_org_ids()
INSTRUMENT_KEY = 'benchmark:instrument:bse500tri'
PROVIDER_KEY = 'benchmark.provider.bse'
INDEX_PAGE = 'https://www.bseindices.com/indices-details/code/17/'
API_PATH = '/AsiaIndexAPI/api/GetHistoricalPRTRData_Asia/w'


def exact_decimal(value):
    number = decimal.Decimal(str(value))
    if not number.is_finite() or number <= 0:
        raise ValueError('BSE TRI values must be finite and positive')
    digits = len(number.as_tuple().digits)
    if digits > 28:
        raise ValueError('BSE TRI value exceeds supported source precision')
    return number


def value_key(value):
    number = exact_decimal(value).normalize()
    return f'{number.as_tuple().sign and "-" or ""}{"".join(str(d) for d in number.as_tuple().digits)}e{number.as_tuple().exponent}'


def source_rows(end_date):
    params = urllib.parse.urlencode({'code': '17', 'Fromdate': '20130101', 'Todate': end_date.strftime('%Y%m%d'), 'flag': '1', 'type': '1'})
    url = 'https://www.bseindices.com' + API_PATH + '?' + params
    request = urllib.request.Request(url, headers={'Accept': 'application/json', 'User-Agent': 'InvestmentPortfolioBenchmarkRefresh/1.0'})
    with urllib.request.urlopen(request, timeout=60) as response:
        if response.status != 200:
            raise RuntimeError(f'BSE API HTTP {response.status}')
        payload = response.read()
    decoded = json.loads(payload)
    if not isinstance(decoded, list) or len(decoded) < 500:
        raise RuntimeError('BSE API returned an incomplete or unexpected history payload')
    result = {}
    for row in decoded:
        if row.get('IndexName', '').strip().casefold() != 'bse 500':
            raise RuntimeError('BSE API returned a different index identity')
        day = dt.datetime.strptime(row['TransDate'].split(' ')[0], '%m/%d/%Y').date()
        value = exact_decimal(row['TRValue'])
        if day > end_date:
            raise RuntimeError('BSE API returned a future observation')
        if day in result and exact_decimal(result[day]['TRValue']) != value:
            raise RuntimeError('BSE API returned conflicting values for the same date')
        result[day] = row
    if len(result) < 500:
        raise RuntimeError('BSE API history is unexpectedly sparse')
    return url, result, hashlib.sha256(payload).hexdigest()


def chunks(values, size=200):
    for offset in range(0, len(values), size):
        yield values[offset:offset + size]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target-org', required=True)
    args = parser.parse_args()
    sf = Salesforce(args.target_org)
    organization = sf.query('SELECT Id,IsSandbox FROM Organization')[0]
    if organization['Id'] not in ALLOWED_ORGS:
        raise RuntimeError('Unexpected Salesforce org; no records were changed')

    end_date = dt.date.today()
    api_url, observations, payload_hash = source_rows(end_date)
    instrument_rows = sf.query("SELECT Id,MigrationKey__c FROM Inv_MarketInstruments__c WHERE MigrationKey__c='" + INSTRUMENT_KEY + "'")
    provider_rows = sf.query("SELECT Id,MigrationKey__c FROM Inv_OpsProviders__c WHERE MigrationKey__c='" + PROVIDER_KEY + "'")
    if len(instrument_rows) != 1 or len(provider_rows) != 1:
        raise RuntimeError('Verified BSE instrument or provider is missing; run benchmark bootstrap first')
    instrument_id, provider_id = instrument_rows[0]['Id'], provider_rows[0]['Id']

    existing_rows = sf.query("SELECT Id,MigrationKey__c,ObservedOn__c,Value__c,RevisionNo__c,QualityStatus__c FROM Inv_MarketPriceObservations__c WHERE InstrumentRef__c='" + instrument_id + "'")
    existing_by_date = {}
    for row in existing_rows:
        existing_by_date.setdefault(row['ObservedOn__c'], []).append(row)

    retrieved = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')
    records, unchanged, revisions, expected_by_key = [], 0, 0, {}
    for day, source in sorted(observations.items()):
        date_text = day.isoformat()
        value_text = str(source['TRValue'])
        exact_decimal(value_text)
        identity = f'{provider_id}|{instrument_id}|{date_text}|TRI|{value_key(value_text)}'
        key = 'bse-tri:' + hashlib.sha256(identity.encode('utf-8')).hexdigest()
        raw = json.dumps(source, ensure_ascii=False, separators=(',', ':'), sort_keys=True)
        source_hash = hashlib.sha256(raw.encode('utf-8')).hexdigest()
        expected_by_key[key] = {'date': date_text, 'value': value_text, 'sourceHash': source_hash}
        prior = existing_by_date.get(date_text, [])
        matching = [row for row in prior if exact_decimal(row['Value__c']) == exact_decimal(value_text)
                    and row.get('QualityStatus__c') == 'accepted']
        if matching:
            unchanged += 1
            continue
        prior.sort(key=lambda row: (decimal.Decimal(row.get('RevisionNo__c') or '0'), row['Id']), reverse=True)
        revision_number = int(decimal.Decimal(prior[0].get('RevisionNo__c') or '0')) + 1 if prior else 1
        envelope = {'endpoint': api_url, 'indexPage': INDEX_PAGE, 'indexCode': '17', 'indexName': 'BSE 500 TRI',
                    'selectedField': 'TRValue', 'excludedPriceReturnField': 'PRValue', 'responseRow': source}
        number = exact_decimal(value_text)
        fits = number == number.quantize(decimal.Decimal('0.0000000001')) and abs(number) < decimal.Decimal('100000000')
        record = {'attributes': {'type': 'Inv_MarketPriceObservations__c'}, 'MigrationKey__c': key,
            'ObservationKey__c': key, 'InstrumentRef__c': instrument_id, 'ObservedOn__c': date_text,
            'Value__c': value_text, 'PriceKind__c': 'TRI', 'KindFilter__c': 'TRI',
            'QualityStatus__c': 'accepted', 'QualityFilter__c': 'accepted', 'ProviderRef__c': provider_id,
            'ReceivedAt__c': retrieved, 'RetrievedAt__c': retrieved, 'RevisionNo__c': str(revision_number),
            'RevisionNoNumber__c': revision_number, 'SourceHash__c': source_hash,
            'SourceJson__c': json.dumps(envelope, ensure_ascii=False, separators=(',', ':')),
            'MigrationRun__c': f'bse500-tri-backfill:{end_date.isoformat()}'}
        # Preserve exact decimal text; numeric columns are only populated when they fit without rounding.
        if fits:
            record['ValueNumber__c'] = str(number)
        if prior:
            record['SupersedesRef__c'] = prior[0]['Id']
            revisions += 1
        records.append(record)

    artifact = PRIVATE / f'bse500-tri-{args.target_org}-{dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")}'
    artifact.mkdir(parents=True, exist_ok=True)
    (artifact / 'manifest.json').write_text(json.dumps({'orgId': organization['Id'], 'isSandbox': organization['IsSandbox'],
        'apiUrl': api_url, 'sourcePayloadSha256': payload_hash, 'sourceRows': len(observations),
        'startDate': min(observations).isoformat(), 'endDate': max(observations).isoformat(),
        'pendingInsertOrRevisionRows': len(records), 'unchangedAcceptedRows': unchanged,
        'correctionsWithSupersedesLinks': revisions}, indent=2), encoding='utf-8')
    successes = 0
    for batch_number, batch in enumerate(chunks(records), 1):
        result = sf.request('PATCH', '/services/data/v68.0/composite/sobjects/Inv_MarketPriceObservations__c/MigrationKey__c',
                            {'allOrNone': True, 'records': batch})
        failures = [row for row in result if not row.get('success')]
        if failures:
            (artifact / f'errors-batch-{batch_number}.json').write_text(json.dumps(failures, indent=2), encoding='utf-8')
            raise RuntimeError(f'BSE backfill batch {batch_number} failed; protected diagnostics: {artifact}')
        successes += len(result)
    readback = sf.query("SELECT Id,MigrationKey__c,ObservedOn__c,Value__c,ValueNumber__c,ProviderRef__c,PriceKind__c,QualityStatus__c,SourceHash__c FROM Inv_MarketPriceObservations__c WHERE InstrumentRef__c='" + instrument_id + "'")
    accepted = [row for row in readback if row.get('ProviderRef__c') == provider_id and row.get('PriceKind__c') == 'TRI' and row.get('QualityStatus__c') == 'accepted']
    readback_by_key = {row['MigrationKey__c']: row for row in accepted}
    for key, expected in expected_by_key.items():
        saved = readback_by_key.get(key)
        if not saved or saved.get('ObservedOn__c') != expected['date'] or saved.get('Value__c') != expected['value'] or saved.get('SourceHash__c') != expected['sourceHash']:
            raise RuntimeError('A BSE TRI identity, exact source value or provenance hash did not reconcile')
        numeric = saved.get('ValueNumber__c')
        if numeric is not None and decimal.Decimal(str(numeric)) != exact_decimal(expected['value']):
            raise RuntimeError('BSE TRI numeric projection does not match the preserved source decimal')
    duplicates = len(accepted) - len({row['ObservedOn__c'] for row in accepted})
    report = {'orgId': organization['Id'], 'isSandbox': organization['IsSandbox'], 'sourceRows': len(observations),
        'acceptedBseRows': len(accepted), 'insertedOrRevisionRows': successes, 'unchangedRows': unchanged,
        'correctionsWithSupersedesLinks': revisions, 'latestSourceDate': max(observations).isoformat(),
        'duplicateAcceptedRowsByDate': duplicates, 'allIdentityValuesAndHashesVerified': True,
        'payloadSha256': payload_hash, 'verifiedReadBack': True}
    (artifact / 'verification.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
