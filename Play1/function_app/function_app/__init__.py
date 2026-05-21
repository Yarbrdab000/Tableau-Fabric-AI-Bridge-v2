import azure.functions as func
import requests
import json
import logging
from azure.identity import ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient
import os

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

KV_URL = os.environ["KV_URL"]
KV_SECRET_NAME = os.environ["KV_SECRET_NAME"]
TABLEAU_POD = os.environ["TABLEAU_POD"]
TABLEAU_SITE = os.environ["TABLEAU_SITE"]
TABLEAU_PAT_NAME = os.environ["TABLEAU_PAT_NAME"]
DATASOURCE_LUID = os.environ["DATASOURCE_LUID"]

def get_pat_from_keyvault():
    credential = ManagedIdentityCredential()
    client = SecretClient(vault_url=KV_URL, credential=credential)
    return client.get_secret(KV_SECRET_NAME).value

def get_tableau_token(pat_name, pat_value, pod, site):
    url = f"https://{pod}/api/3.24/auth/signin"
    payload = {
        "credentials": {
            "personalAccessTokenName": pat_name,
            "personalAccessTokenSecret": pat_value,
            "site": {"contentUrl": site}
        }
    }
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    resp = requests.post(url, json=payload, headers=headers)
    resp.raise_for_status()
    data = resp.json()
    return data["credentials"]["token"], data["credentials"]["site"]["id"]

def get_logical_table_id(token, pod, datasource_luid):
    url = f"https://{pod}/api/v1/vizql-data-service/read-metadata"
    headers = {"x-tableau-auth": token, "Content-Type": "application/json"}
    payload = {"datasource": {"datasourceLuid": datasource_luid}}
    resp = requests.post(url, json=payload, headers=headers)
    logging.info(f"read-metadata status: {resp.status_code}")
    logging.info(f"read-metadata body: {resp.text[:500]}")
    resp.raise_for_status()
    tables = resp.json().get("logicalTables", [])
    if not tables:
        raise ValueError("No logical tables found in datasource")
    return tables[0]["id"]

def query_vds(token, pod, datasource_luid, logical_table_id, query_fields):
    url = f"https://{pod}/api/v1/vizql-data-service/query-datasource"
    headers = {"x-tableau-auth": token, "Content-Type": "application/json"}
    payload = {
        "datasource": {"datasourceLuid": datasource_luid},
        "query": {
            "fields": query_fields,
            "logicalTableId": logical_table_id
        }
    }
    resp = requests.post(url, json=payload, headers=headers)
    resp.raise_for_status()
    return resp.json()

@app.route(route="query", methods=["POST"])
def query(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("VDS query request received")
    try:
        body = req.get_json()
        query_fields = body.get("query_fields")
        if not query_fields:
            return func.HttpResponse(
                json.dumps({"error": "query_fields is required"}),
                status_code=400,
                mimetype="application/json"
            )

        pat_value = get_pat_from_keyvault()
        token, site_id = get_tableau_token(TABLEAU_PAT_NAME, pat_value, TABLEAU_POD, TABLEAU_SITE)
        logical_table_id = get_logical_table_id(token, TABLEAU_POD, DATASOURCE_LUID)
        result = query_vds(token, TABLEAU_POD, DATASOURCE_LUID, logical_table_id, query_fields)

        return func.HttpResponse(
            json.dumps(result),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.error(f"Error: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )
