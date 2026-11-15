"""Create the sandbox rehearsal manifest for the current investment implementation."""
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NS = 'http://soap.sforce.com/2006/04/metadata'
ET.register_namespace('', NS)
SOURCES = ('portfolio.xml', 'portfolio-pages.xml', 'portfolio-reporting.xml')
APEX_CLASSES = {
    'InvExposureEngine', 'InvFundMetrics', 'InvPlanService', 'InvPlanServiceTest',
    'InvPortfolioEngine', 'InvPortfolioEngineTest', 'InvRecalculate', 'InvMovementService',
    'InvNAVPolicy', 'InvPlanScenarioService', 'InvRedemptionService',
    'InvResearchPipeline', 'InvResearchService', 'InvResearchServicesTest', 'InvRefreshTest',
}


def main():
    members = {}
    for filename in SOURCES:
        package = ET.parse(ROOT / 'manifest' / filename).getroot()
        for component in package.findall('{'+NS+'}types'):
            kind = component.find('{'+NS+'}name').text
            members.setdefault(kind, set()).update(x.text for x in component.findall('{'+NS+'}members'))

    # Scheduled continuation classes must not be replaced while their cron jobs are active.
    members['ApexClass'] = set(APEX_CLASSES)
    members.pop('ApexTrigger', None)
    package = ET.Element('{'+NS+'}Package')
    for kind in sorted(members):
        component = ET.SubElement(package, '{'+NS+'}types')
        for member in sorted(members[kind]):
            ET.SubElement(component, '{'+NS+'}members').text = member
        ET.SubElement(component, '{'+NS+'}name').text = kind
    ET.SubElement(package, '{'+NS+'}version').text = '68.0'
    ET.indent(package, space='  ')
    ET.ElementTree(package).write(ROOT / 'manifest' / 'portfolio-implementation.xml', encoding='UTF-8', xml_declaration=True)
    print(f"Generated sandbox implementation manifest: {sum(map(len, members.values()))} components, {len(members['ApexClass'])} changed Apex classes")


if __name__ == '__main__':
    main()
