"""Load reviewed official fund benchmark evidence and assignments idempotently."""
import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'investment-migration'))
from org_config import allowed_org_ids
from migrate import Salesforce
from prepare import PRIVATE

ALLOWED_ORGS = allowed_org_ids()
RUN = 'benchmark-bootstrap:2026-11-14'
SCHEME_CODES = {
    '120828', '120492', '145206', '118551', '129046',
    '122639', '118778', '120841', '135781', '147704',
}
PROVIDERS = [
    ('quant', 'Quant Mutual Fund', 'https://quantmutual.com/'),
    ('jm', 'JM Financial Mutual Fund', 'https://www.jmfinancialmf.com/'),
    ('tata', 'Tata Mutual Fund', 'https://www.tatamutualfund.com/'),
    ('motilal', 'Motilal Oswal Mutual Fund', 'https://www.motilaloswalmf.com/'),
    ('ppfas', 'PPFAS Mutual Fund', 'https://amc.ppfas.com/'),
    ('nippon', 'Nippon India Mutual Fund', 'https://mf.nipponindiaim.com/'),
    ('mirae', 'Mirae Asset Mutual Fund', 'https://www.miraeassetmf.co.in/'),
    ('franklin', 'Franklin Templeton India', 'https://www.franklintempletonindia.com/'),
]
TRI_PROVIDER = ('benchmark.provider.bse', 'BSE Indices official TRI', 'https://www.bseindices.com/', 'official_benchmark')
PROVIDER_NAMES = {slug: name for slug, name, _ in PROVIDERS}
PROVIDER_NAMES['bse'] = TRI_PROVIDER[1]
EVIDENCE = [
    {'key': 'quant-2026-11', 'provider': 'quant', 'title': 'Quant Mutual Fund factsheet, November 2026',
     'url': 'https://quantmutual.com/Admin/Factsheet/quant_Factsheet_-_November_2026.pdf', 'media': 'application/pdf',
     'asOf': '2026-10-30', 'benchmark': 'Quant Small Cap Fund: Nifty Smallcap 250 TRI; Quant Mid Cap Fund: Nifty Midcap 150 TRI.'},
    {'key': 'jm-2026-06', 'provider': 'jm', 'title': 'JM Financial Mutual Fund factsheet, June 2026',
     'url': 'https://www.jmfinancialmf.com/CMS/downloads/Factsheet/Factsheet/Factsheet%20June%202026.pdf', 'media': 'application/pdf',
     'asOf': '2026-05-31', 'benchmark': 'JM Flexicap Fund: BSE 500 TRI.'},
    {'key': 'bse500-index', 'provider': 'bse', 'title': 'BSE 500 official index page and TRI API',
     'url': 'https://www.bseindices.com/indices-details/code/17/', 'media': 'text/html',
     'asOf': '2026-11-14', 'benchmark': 'Official BSE 500 index identity (code 17); historical PR/TR API exposes total-return observations in TRValue.'},
    {'key': 'tata-2026-07', 'provider': 'tata', 'title': 'Tata Small Cap Fund official product page',
     'url': 'https://info.tatamutualfund.com/combined/TATA/Small-Cap-Fund.html', 'media': 'text/html',
     'asOf': '2026-07-31', 'benchmark': 'Tata Small Cap Fund: Nifty Smallcap 250 TRI.'},
    {'key': 'motilal-flexi-2026-08', 'provider': 'motilal', 'title': 'Motilal Oswal Flexi Cap Fund official product page',
     'url': 'https://www.motilaloswalmf.com/mutual-funds/motilal-oswal-flexi-cap-fund', 'media': 'text/html',
     'asOf': '2026-08-31', 'benchmark': 'Motilal Oswal Flexi Cap Fund: Nifty 500 TRI.'},
    {'key': 'ppfas-2026-10', 'provider': 'ppfas', 'title': 'PPFAS digital factsheet, October 2026',
     'url': 'https://amc.ppfas.com/downloads/digital-factsheet/2026/october-2026/', 'media': 'text/html',
     'asOf': '2026-10-31', 'benchmark': 'Parag Parikh Flexi Cap Fund: Nifty 500 TRI.'},
    {'key': 'nippon-smallcap-2026-09', 'provider': 'nippon', 'title': 'Nippon India Small Cap Fund official product page',
     'url': 'https://mf.nipponindiaim.com/FundsAndPerformance/Pages/NipponIndia-Small-Cap-Fund.aspx', 'media': 'text/html',
     'asOf': '2026-09-30', 'benchmark': 'Nippon India Small Cap Fund: Nifty Smallcap 250 TRI.'},
    {'key': 'mirae-elss-2026-11', 'provider': 'mirae', 'title': 'Mirae Asset ELSS Tax Saver Fund official product page',
     'url': 'https://www.miraeassetmf.co.in/mutual-fund-scheme/equity-fund/mirae-asset-elss-tax-saver-fund', 'media': 'text/html',
     'asOf': '2026-11-12', 'benchmark': 'Mirae Asset ELSS Tax Saver Fund Tier 1: Nifty 500 TRI; Tier 2: Nifty 200 TRI. Tier 1 is recorded as primary.'},
    {'key': 'motilal-large-midcap-2026-08', 'provider': 'motilal', 'title': 'Motilal Oswal Large and Midcap Fund factsheet, August 2026',
     'url': 'https://www.motilaloswalmf.com/content/dam/motilal-mf/downloads/mf/factsheet/2026/sep/Factsheet_August_2026_Active.pdf', 'media': 'application/pdf',
     'asOf': '2026-08-31', 'benchmark': 'Motilal Oswal Large and Midcap Fund: Nifty Large Midcap 250 TRI.'},
    {'key': 'franklin-us-fof-2026-07', 'provider': 'franklin', 'title': 'Franklin India Feeder Franklin U.S. Opportunities Fund factsheet',
     'url': 'https://www.franklintempletonindia.com/static/factsheet/Innerpage/Franklin-India-Feeder-Franklin-us-Opportunities-Fund.html', 'media': 'text/html',
     'asOf': '2026-07-31', 'benchmark': 'Russell 3000 Growth Index (USD). No primary comparison is assigned because this application has no verified compatible currency-adjusted TRI history.'},
]
ASSIGNMENTS = [
    ('120828', 'market.instruments:27', 'quant-2026-11', '2026-10-30'),
    ('120841', 'market.instruments:26', 'quant-2026-11', '2026-10-30'),
    ('120492', 'benchmark:instrument:bse500tri', 'jm-2026-06', '2026-05-31'),
    ('145206', 'market.instruments:27', 'tata-2026-07', '2026-07-31'),
    ('129046', 'market.instruments:25', 'motilal-flexi-2026-08', '2026-08-31'),
    ('122639', 'market.instruments:25', 'ppfas-2026-10', '2026-10-31'),
    ('118778', 'market.instruments:27', 'nippon-smallcap-2026-09', '2026-09-30'),
    ('135781', 'market.instruments:25', 'mirae-elss-2026-11', '2026-11-12'),
    ('147704', 'market.instruments:28', 'motilal-large-midcap-2026-08', '2026-08-31'),
]


def compact_hash(value):
    body = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    return body, hashlib.sha256(body.encode('utf-8')).hexdigest()


def upsert(sf, object_name, records):
    if not records:
        return []
    result = sf.request('PATCH', f'/services/data/v68.0/composite/sobjects/{object_name}/MigrationKey__c',
                        {'allOrNone': True, 'records': records})
    errors = [row for row in result if not row.get('success')]
    if errors:
        # Store precise record-level diagnostics privately, then expose only a count.
        diagnostic = PRIVATE / 'errors' / f'benchmark-{object_name}-{time_key()}.json'
        diagnostic.parent.mkdir(parents=True, exist_ok=True)
        diagnostic.write_text(json.dumps(errors, indent=2), encoding='utf-8')
        raise RuntimeError(f'Benchmark bootstrap failed for {object_name}; see protected diagnostic {diagnostic}')
    return result


def time_key():
    return dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target-org', required=True)
    args = parser.parse_args()
    sf = Salesforce(args.target_org)
    organization = sf.query('SELECT Id,IsSandbox FROM Organization')[0]
    if organization['Id'] not in ALLOWED_ORGS:
        raise RuntimeError('Unexpected Salesforce org; no records were changed')

    # Make benchmark source providers durable without replacing the NSE observation provider.
    provider_records = []
    for slug, name, base_url in PROVIDERS:
        provider_records.append({'attributes': {'type': 'Inv_OpsProviders__c'},
            'MigrationKey__c': f'benchmark.provider.amc.{slug}', 'Name__c': name,
            'BaseUrl__c': base_url, 'Kind__c': 'official_amc', 'Priority__c': '1',
            'SourceJson__c': json.dumps({'source': 'official AMC evidence source', 'baseUrl': base_url}, separators=(',', ':'))})
    provider_records.append({'attributes': {'type': 'Inv_OpsProviders__c'}, 'MigrationKey__c': TRI_PROVIDER[0],
        'Name__c': TRI_PROVIDER[1], 'BaseUrl__c': TRI_PROVIDER[2], 'Kind__c': TRI_PROVIDER[3], 'Priority__c': '1',
        'SourceJson__c': json.dumps({'source': 'official BSE Indices BSE 500 PR/TR historical series',
            'baseUrl': TRI_PROVIDER[2], 'indexCode': '17', 'variantField': 'TRValue'}, separators=(',', ':'))})
    upsert(sf, 'Inv_OpsProviders__c', provider_records)
    provider_keys = [f'benchmark.provider.amc.{slug}' for slug, _, _ in PROVIDERS] + [TRI_PROVIDER[0]]
    provider_rows = sf.query("SELECT Id,MigrationKey__c,Name__c,BaseUrl__c,Kind__c,Priority__c FROM Inv_OpsProviders__c WHERE MigrationKey__c IN ('" + "','".join(provider_keys) + "')")
    providers = {row['MigrationKey__c']: row['Id'] for row in provider_rows}
    if len(providers) != len(provider_keys):
        raise RuntimeError('Provider verification failed; no benchmark assignments were written')
    expected_providers = {f'benchmark.provider.amc.{slug}': (name, base_url, 'official_amc', '1') for slug, name, base_url in PROVIDERS}
    expected_providers[TRI_PROVIDER[0]] = (TRI_PROVIDER[1], TRI_PROVIDER[2], TRI_PROVIDER[3], '1')
    for row in provider_rows:
        if (row.get('Name__c'), row.get('BaseUrl__c'), row.get('Kind__c'), row.get('Priority__c')) != expected_providers[row['MigrationKey__c']]:
            raise RuntimeError('Provider record did not reconcile to its reviewed official source')

    retrieved = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')
    evidence_records = []
    for item in EVIDENCE:
        content = {'sourceUrl': item['url'], 'publisher': PROVIDER_NAMES[item['provider']],
                   'title': item['title'], 'observedAsOf': item['asOf'], 'reportedBenchmark': item['benchmark'],
                   'reviewedAgainst': 'official fund-family factsheet or product page',
                   'sourceBytesCopied': False,
                   'sourceBytesSha256': None}
        source_json, source_hash = compact_hash(content)
        evidence_records.append({'attributes': {'type': 'Inv_OpsSourceDocuments__c'},
            'MigrationKey__c': f'benchmark.evidence.{item["key"]}',
            'ProviderRef__c': providers[TRI_PROVIDER[0] if item['provider'] == 'bse' else f'benchmark.provider.amc.{item["provider"]}'],
            'MediaType__c': item['media'], 'ParserVersion__c': 'manual-official-evidence-review/1',
            'SourceUrl__c': item['url'], 'SourceHash__c': source_hash, 'SourceJson__c': source_json,
            'RetrievedAt__c': retrieved, 'MigrationRun__c': RUN})
    # Preserve the first evidence capture time when the same reviewed metadata is already present.
    evidence_keys = [row['MigrationKey__c'] for row in evidence_records]
    old_docs = sf.query("SELECT MigrationKey__c,SourceHash__c,RetrievedAt__c FROM Inv_OpsSourceDocuments__c WHERE MigrationKey__c IN ('" + "','".join(evidence_keys) + "')")
    old_by_key = {row['MigrationKey__c']: row for row in old_docs}
    for row in evidence_records:
        old = old_by_key.get(row['MigrationKey__c'])
        if old and old['SourceHash__c'] == row['SourceHash__c']:
            row['RetrievedAt__c'] = old['RetrievedAt__c']
    upsert(sf, 'Inv_OpsSourceDocuments__c', evidence_records)
    doc_rows = sf.query("SELECT Id,MigrationKey__c,SourceHash__c,SourceJson__c,SourceUrl__c,MediaType__c,ProviderRef__c FROM Inv_OpsSourceDocuments__c WHERE MigrationKey__c IN ('" + "','".join(evidence_keys) + "')")
    docs = {row['MigrationKey__c']: row for row in doc_rows}
    if len(docs) != len(EVIDENCE):
        raise RuntimeError('Source document verification failed; no benchmark assignments were written')
    expected_evidence = {f'benchmark.evidence.{item["key"]}': item for item in EVIDENCE}
    for row in doc_rows:
        item = expected_evidence[row['MigrationKey__c']]
        evidence = {'sourceUrl': item['url'], 'publisher': PROVIDER_NAMES[item['provider']],
                    'title': item['title'], 'observedAsOf': item['asOf'], 'reportedBenchmark': item['benchmark'],
                    'reviewedAgainst': 'official fund-family factsheet or product page',
                    'sourceBytesCopied': False, 'sourceBytesSha256': None}
        expected_json, expected_hash = compact_hash(evidence)
        expected_provider = providers[TRI_PROVIDER[0] if item['provider'] == 'bse' else f'benchmark.provider.amc.{item["provider"]}']
        if (row.get('SourceHash__c') != expected_hash or row.get('SourceJson__c') != expected_json or
                row.get('SourceUrl__c') != item['url'] or row.get('MediaType__c') != item['media'] or
                row.get('ProviderRef__c') != expected_provider):
            raise RuntimeError('Source document did not reconcile to the reviewed benchmark evidence')

    # JM's BSE 500 TRI mapping and the corresponding official BSE history source are explicit.
    jm_doc = docs['benchmark.evidence.jm-2026-06']
    bse_doc = docs['benchmark.evidence.bse500-index']
    instrument_json, instrument_hash = compact_hash({'officialBenchmarkEvidence': jm_doc['SourceHash__c'],
        'officialSeriesSource': bse_doc['SourceHash__c'], 'name': 'BSE 500 TRI', 'indexCode': '17',
        'currency': 'INR', 'variant': 'TRI', 'apiField': 'TRValue', 'priceReturnFieldExcluded': 'PRValue'})
    upsert(sf, 'Inv_MarketInstruments__c', [{'attributes': {'type': 'Inv_MarketInstruments__c'},
        'MigrationKey__c': 'benchmark:instrument:bse500tri', 'Name__c': 'BSE 500 TRI', 'DisplayName__c': 'BSE 500 TRI',
        'Kind__c': 'benchmark', 'Currency__c': 'INR', 'BenchmarkVariant__c': 'TRI', 'ProviderCode__c': '17',
        'MappingVerified__c': True, 'SourceHash__c': instrument_hash, 'SourceJson__c': instrument_json,
        'MigrationRun__c': RUN}])
    instruments = sf.query("SELECT Id,MigrationKey__c,Name__c,DisplayName__c,Kind__c,Currency__c,BenchmarkVariant__c,ProviderCode__c,MappingVerified__c,SourceHash__c,SourceJson__c FROM Inv_MarketInstruments__c WHERE MigrationKey__c IN (" +
        "'market.instruments:25','market.instruments:26','market.instruments:27','market.instruments:28','benchmark:instrument:bse500tri')")
    benchmark_ids = {row['MigrationKey__c']: row['Id'] for row in instruments}
    expected_instruments = {'market.instruments:25', 'market.instruments:26', 'market.instruments:27', 'market.instruments:28', 'benchmark:instrument:bse500tri'}
    if set(benchmark_ids) != expected_instruments:
        raise RuntimeError('Benchmark instrument verification failed; no assignments were written')
    bse = next(row for row in instruments if row['MigrationKey__c'] == 'benchmark:instrument:bse500tri')
    if (bse.get('Name__c'), bse.get('DisplayName__c'), bse.get('Kind__c'), bse.get('Currency__c'),
            bse.get('BenchmarkVariant__c'), bse.get('ProviderCode__c'), bse.get('MappingVerified__c'),bse.get('SourceHash__c'),bse.get('SourceJson__c')) != (
            'BSE 500 TRI', 'BSE 500 TRI', 'benchmark', 'INR', 'TRI', '17', True,instrument_hash,instrument_json):
        raise RuntimeError('The BSE 500 TRI instrument did not reconcile')

    classes = sf.query('SELECT AmfiCode__c,SchemeRef__c FROM Inv_MarketFundShareClasses__c')
    scheme_by_code = {}
    for row in classes:
        if row.get('AmfiCode__c') in SCHEME_CODES:
            if row['AmfiCode__c'] in scheme_by_code:
                raise RuntimeError('A supported AMFI code maps to multiple share classes; no assignments were written')
            scheme_by_code[row['AmfiCode__c']] = row['SchemeRef__c']
    if set(scheme_by_code) != SCHEME_CODES or any(not value for value in scheme_by_code.values()):
        raise RuntimeError('Verified share-class mappings are incomplete; no assignments were written')

    assignments = []
    for code, benchmark_key, evidence_key, effective in ASSIGNMENTS:
        assignment_key = f'benchmark.assignment.amfi.{code}.primary'
        assignments.append({'attributes': {'type': 'Inv_MarketBenchmarkAssignments__c'},
            'MigrationKey__c': assignment_key, 'SchemeRef__c': scheme_by_code[code],
            'BenchmarkRef__c': benchmark_ids[benchmark_key], 'DocumentRef__c': docs[f'benchmark.evidence.{evidence_key}']['Id'],
            'Role__c': 'primary', 'EffectiveFrom__c': effective, 'MigrationRun__c': RUN,
            'SourceHash__c': docs[f'benchmark.evidence.{evidence_key}']['SourceHash__c'],
            'SourceJson__c': json.dumps({'amfiSchemeCode': code, 'evidenceKey': evidence_key,
                'benchmarkMigrationKey': benchmark_key, 'effectiveFrom': effective,
                'note': 'Effective date is the cited source observation date; older benchmark comparisons remain unavailable until supported by evidence.'},
                ensure_ascii=False, separators=(',', ':')),
            'SnapshotNotice__c': 'Official benchmark assignment preserved from dated AMC evidence; calculations respect this effective date and available history.'})

    target_schemes = {scheme_by_code[code] for code, _, _, _ in ASSIGNMENTS}
    current = sf.query('SELECT MigrationKey__c,SchemeRef__c,Role__c,EffectiveFrom__c,EffectiveTo__c FROM Inv_MarketBenchmarkAssignments__c')
    owned_keys = {row['MigrationKey__c'] for row in assignments}
    for row in current:
        if row.get('SchemeRef__c') not in target_schemes or row.get('Role__c') != 'primary' or row['MigrationKey__c'] in owned_keys:
            continue
        # Do not create a second primary assignment over a record managed elsewhere.
        if not row.get('EffectiveTo__c'):
            raise RuntimeError('A different active primary assignment exists for a target scheme; no assignments were written')
    upsert(sf, 'Inv_MarketBenchmarkAssignments__c', assignments)

    assignment_keys = [row['MigrationKey__c'] for row in assignments]
    saved_assignments = sf.query("SELECT MigrationKey__c,SchemeRef__c,BenchmarkRef__c,DocumentRef__c,Role__c,EffectiveFrom__c FROM Inv_MarketBenchmarkAssignments__c WHERE MigrationKey__c IN ('" + "','".join(assignment_keys) + "')")
    if len(saved_assignments) != len(assignments):
        raise RuntimeError('Benchmark assignment read-back failed')
    for row in assignments:
        saved = next(value for value in saved_assignments if value['MigrationKey__c'] == row['MigrationKey__c'])
        for field in ('SchemeRef__c', 'BenchmarkRef__c', 'DocumentRef__c', 'Role__c', 'EffectiveFrom__c'):
            if saved[field] != row[field]:
                raise RuntimeError('Benchmark assignment relationship or effective date did not reconcile')

    artifact = PRIVATE / f'benchmark-bootstrap-{args.target_org}-{time_key()}'
    artifact.mkdir(parents=True, exist_ok=True)
    (artifact / 'verification.json').write_text(json.dumps({'orgId': organization['Id'], 'isSandbox': organization['IsSandbox'],
        'providers': len(provider_rows), 'evidenceDocuments': len(doc_rows), 'assignments': len(saved_assignments),
        'triBenchmarks': len(benchmark_ids), 'franklinBenchmarkAssignment': 'withheld: USD Russell 3000 Growth lacks verified compatible history',
        'jmBenchmarkHistory': 'BSE 500 TRI instrument and assignment recorded; official history import is handled separately'}, indent=2), encoding='utf-8')
    print(json.dumps({'orgId': organization['Id'], 'isSandbox': organization['IsSandbox'],
        'providerRecords': len(provider_rows), 'sourceEvidenceRecords': len(doc_rows),
        'benchmarkAssignments': len(saved_assignments), 'supportedNiftyTriInstruments': 4,
        'bse500InstrumentAdded': True, 'bseOfficialProviderAdded': True, 'franklinAssignmentWithheld': True,
        'protectedVerification': str(artifact / 'verification.json')}))


if __name__ == '__main__':
    main()
