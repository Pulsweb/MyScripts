spark.conf.set("spark.sql.parquet.vorder.enabled", "true")
import json, requests, pandas as pd
from azure.identity import UsernamePasswordCredential
from datetime import date

tenant = '###'
api = 'https://analysis.windows.net/powerbi/api/.default'
client_id = '###'
username = '###'
password = '###'  
path = '/lakehouse/default/Files/TenantSettings/'
activityDate = date.today().strftime("%Y-%m-%d")

username_password_credential_class = UsernamePasswordCredential(client_id=client_id, username=username, password=password, tenant_id=tenant)
access_token_class = username_password_credential_class.get_token(api)
access_token = access_token_class.token

TenantSettingsURL = 'https://api.fabric.microsoft.com/v1/admin/tenantsettings'
header = {'Authorization': f'Bearer {access_token}'}
TenantSettingsJSON = requests.get(TenantSettingsURL , headers=header)

TenantSettingsJSONContent = json.loads(TenantSettingsJSON.content)
TenantSettingsJSONContentExplode = TenantSettingsJSONContent['tenantSettings']

df = pd.DataFrame(TenantSettingsJSONContentExplode)
df['ExportedDate'] = activityDate
df.to_csv(path + activityDate + '_TenantSettings.csv', index=False) 

df = spark.read.format("csv").option("header","true").load("Files/TenantSettings/*.csv")
df.write.mode("overwrite").format("delta").saveAsTable("TenantSettings")
