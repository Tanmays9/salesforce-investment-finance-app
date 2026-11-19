"""Grant the authenticated organization owner the portfolio viewer and manager roles."""
import json,sys
sys.path.insert(0,str(__import__('pathlib').Path(__file__).resolve().parents[1]/'investment-migration'))
from org_config import org_alias_for_stage, org_id_for_stage
from migrate import Salesforce

def main():
    s=Salesforce(org_alias_for_stage('production'));org=s.query('SELECT Id,IsSandbox FROM Organization')[0]
    if org['Id']!=org_id_for_stage('production') or org['IsSandbox']:raise RuntimeError('Expected the verified investment production org')
    user=s.request('GET','/services/oauth2/userinfo')['user_id'];assigned=[]
    for name in ['Inv_Viewer','Inv_PortfolioManager']:
        permission=s.query("SELECT Id FROM PermissionSet WHERE Name='"+name+"'")[0]['Id']
        if not s.query("SELECT Id FROM PermissionSetAssignment WHERE AssigneeId='"+user+"' AND PermissionSetId='"+permission+"'"):
            s.request('POST','/services/data/v68.0/sobjects/PermissionSetAssignment',{'AssigneeId':user,'PermissionSetId':permission})
        assigned.append(name)
    group=s.query("SELECT Id FROM Group WHERE DeveloperName='Investment_Viewers'")[0]['Id']
    if not s.query("SELECT Id FROM GroupMember WHERE GroupId='"+group+"' AND UserOrGroupId='"+user+"'"):
        s.request('POST','/services/data/v68.0/sobjects/GroupMember',{'GroupId':group,'UserOrGroupId':user})
    print(json.dumps({'roles':assigned,'reportFolderAccess':'Investment_Viewers','membershipVerified':bool(s.query("SELECT Id FROM GroupMember WHERE GroupId='"+group+"' AND UserOrGroupId='"+user+"'"))}))

if __name__=='__main__':main()
