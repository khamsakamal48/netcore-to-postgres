# Netcore to Postgres

Pulls IIT Bombay email campaign engagement data from the Netcore CE API into PostgreSQL.

## Status

Step 1: API test (`spike.sh`). The backfill script, schema and Docker setup follow once the test results are in.

## Run the API test

Run on the server that will host the pipeline, so the IP-whitelisting check is meaningful:

```bash
git clone https://github.com/khamsakamal48/netcore-to-postgres.git
cd netcore-to-postgres
NETCORE_API_KEY=<key> TEST_EMAIL=<contact that received campaigns> bash spike.sh
```

- API key: Netcore panel > Profile > User Profile.
- Region defaults to `us` (panel host `pr17r`). Override with `REGION=ind|eu`.
- Optional: `NOTIFY_EMAIL=<you> LIST_ID=<id>` also tests the async audience export.

Responses are saved under `Logs/` (git-ignored). They contain contact data: keep them private.
