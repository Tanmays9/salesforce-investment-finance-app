"""Remove only the ten exact duplicate BSE rows created by the 2026-11-14 sandbox rehearsal."""
import datetime as dt
import json
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'investment-migration'))
from org_config import org_alias_for_stage, org_id_for_stage
from migrate import Salesforce
from prepare import PRIVATE

EXPECTED_ORG=org_id_for_stage('sandbox')
EXPECTED_DATES = {'2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06',
                  '2026-11-08', '2026-11-09', '2026-11-11', '2026-11-12', '2026-11-13'}
EARLIER_CREATED = dt.datetime(2026, 11, 14, 8, 52, 48, tzinfo=dt.timezone.utc)
LATER_CREATED = dt.datetime(2026, 11, 14, 8, 53, 50, tzinfo=dt.timezone.utc)


def main():
    sf = Salesforce(org_alias_for_stage('sandbox'))
    organization = sf.query('SELECT Id,IsSandbox FROM Organization')[0]
    if organization['Id'] != EXPECTED_ORG or not organization['IsSandbox']:
        raise RuntimeError('Sandbox guard failed; no rows were changed')
    instruments = sf.query("SELECT Id FROM Inv_MarketInstruments__c WHERE MigrationKey__c='benchmark:instrument:bse500tri'")
    if len(instruments) != 1:
        raise RuntimeError('Expected exactly one sandbox BSE 500 TRI instrument')
    instrument = instruments[0]['Id']
    rows = sf.query("SELECT Id,ObservedOn__c,Value__c,CreatedDate,ReceivedAt__c,ProviderRef__c,PriceKind__c,QualityStatus__c "
                    "FROM Inv_MarketPriceObservations__c WHERE InstrumentRef__c='" + instrument + "'")
    grouped = defaultdict(list)
    for row in rows:
        grouped[row['ObservedOn__c']].append(row)
    duplicates = {day: group for day, group in grouped.items() if len(group) > 1}
    if not duplicates:
        print(json.dumps({'orgId': organization['Id'], 'deleted': 0, 'duplicateDates': 0, 'idempotent': True}))
        return
    if set(duplicates) != EXPECTED_DATES or any(len(group) != 2 for group in duplicates.values()):
        raise RuntimeError('Sandbox duplicate set differs from the exact rehearsal rows; no records were deleted')
    targets = []
    for day, group in duplicates.items():
        if len({row['Value__c'] for row in group}) != 1 or len({row['ProviderRef__c'] for row in group}) != 1:
            raise RuntimeError('Same-date duplicate values or providers differ; no records were deleted')
        if any(row['PriceKind__c'] != 'TRI' or row['QualityStatus__c'] != 'accepted' for row in group):
            raise RuntimeError('Same-date duplicate quality does not match the rehearsed accepted BSE series')
        by_created = sorted(group, key=lambda row: row['CreatedDate'])
        timestamps = [dt.datetime.fromisoformat(row['CreatedDate'].replace('Z', '+00:00')).astimezone(dt.timezone.utc)
                      for row in by_created]
        if timestamps != [EARLIER_CREATED, LATER_CREATED]:
            raise RuntimeError('Created timestamps do not match the rehearsal run; no records were deleted')
        targets.append({'id': by_created[1]['Id'], 'day': day, 'value': by_created[1]['Value__c']})

    for target in targets:
        sf.request('DELETE', '/services/data/v68.0/sobjects/Inv_MarketPriceObservations__c/' + target['id'])

    verified = sf.query("SELECT Id,ObservedOn__c FROM Inv_MarketPriceObservations__c WHERE InstrumentRef__c='" + instrument + "'")
    final_groups = defaultdict(int)
    for row in verified:
        final_groups[row['ObservedOn__c']] += 1
    if len(verified) != 3435 or any(count > 1 for count in final_groups.values()):
        raise RuntimeError('Sandbox cleanup read-back failed; inspect the protected verification report')
    artifact = PRIVATE / ('sandbox-bse-cleanup-' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
    artifact.mkdir(parents=True, exist_ok=True)
    report = {'orgId': organization['Id'], 'deletedExactDuplicateRows': len(targets),
              'remainingBseObservations': len(verified), 'duplicateDatesAfterCleanup': 0,
              'targetRows': targets, 'verified': True}
    (artifact / 'verification.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({'orgId': organization['Id'], 'deletedExactDuplicateRows': len(targets),
                      'remainingBseObservations': len(verified), 'duplicateDatesAfterCleanup': 0,
                      'verificationArtifact': str(artifact / 'verification.json')}))


if __name__ == '__main__':
    main()
