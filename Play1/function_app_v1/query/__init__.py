import azure.functions as func
import requests
import json
import logging
from azure.identity import ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient
import os

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
    payload = {"credentials": {"personalAccessTokenName": pat_name, "personalAccessTokenSecret": pat_value, "site": {"contentUrl": site}}}
    resp = requests.post(url, json=payload, headers={"Content-Type": "application/json", "Accept": "application/json"})
    resp.raise_for_status()
    data = resp.json()
    return data["credentials"]["token"], data["credentials"]["site"]["id"]

def query_vds(token, pod, datasource_luid, query_fields):
    url = f"https://{pod}/api/v1/vizql-data-service/query-datasource"
    payload = {
        "datasource": {"datasourceLuid": datasource_luid},
        "query": {
            "fields": query_fields
        },
        "options": {"returnFormat": "OBJECTS"}
    }
    resp = requests.post(url, json=payload, headers={"x-tableau-auth": token, "Content-Type": "application/json"})
    logging.info(f"query-datasource status: {resp.status_code}")
    logging.info(f"query-datasource body: {resp.text[:500]}")
    resp.raise_for_status()
    return resp.json()

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("VDS query request received")
    try:
        body = req.get_json()
        query_fields = body.get("query_fields")
        if not query_fields:
            return func.HttpResponse(json.dumps({"error": "query_fields is required"}), status_code=400, mimetype="application/json")
        pat_value = get_pat_from_keyvault()
        token, site_id = get_tableau_token(TABLEAU_PAT_NAME, pat_value, TABLEAU_POD, TABLEAU_SITE)
        result = query_vds(token, TABLEAU_POD, DATASOURCE_LUID, query_fields)
        return func.HttpResponse(json.dumps(result), status_code=200, mimetype="application/json")
    except Exception as e:
        logging.error(f"Error: {str(e)}")
        return func.HttpResponse(json.dumps({"error": str(e)}), status_code=500, mimetype="application/json")
