"""Generate the operational overlays and one dependency-complete release manifest."""
import xml.etree.ElementTree as ET
from build import main as build
from reporting import main as reporting
from pages import main as pages
from flows import main as flows
from prepare import ROOT,NS,xml

def main():
 build();reporting();pages();flows();build()
 members={}
 for name in ['portfolio.xml','portfolio-reporting.xml','portfolio-pages.xml','portfolio-flows.xml']:
  root=ET.parse(ROOT/'manifest'/name).getroot()
  for group in root.findall('{'+NS+'}types'):
   kind=group.find('{'+NS+'}name').text
   members.setdefault(kind,set()).update(n.text for n in group.findall('{'+NS+'}members'))
 xml(ROOT/'manifest/portfolio-release.xml','Package',{'types':[{'members':sorted(v),'name':k} for k,v in sorted(members.items())],'version':'68.0'})
 print('Prepared dependency-complete operational release')

if __name__=='__main__':main()
