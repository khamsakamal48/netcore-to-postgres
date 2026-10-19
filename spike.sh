#!/usr/bin/env bash
# One-off Netcore CE API test. Answers: is IP whitelisting enforced, how far back
# does summary data go, max date range per call, latency, any 429s.
# Usage: NETCORE_API_KEY=xxx TEST_EMAIL=someone@example.com [REGION=ind|us|eu] [NOTIFY_EMAIL=you@x LIST_ID=123] bash spike.sh
set -u
: "${NETCORE_API_KEY:?set NETCORE_API_KEY}"
: "${TEST_EMAIL:?set TEST_EMAIL (a contact known to have received campaigns)}"
REGION="${REGION:-us}"  # pr17r panel = US data centre
case "$REGION" in
  ind) V4=https://apiind.netcoresmartech.com; V2=https://apiin.netcoresmartech.com ;;
  us)  V4=https://api.netcoresmartech.com;    V2=https://api.netcoresmartech.com ;;
  eu)  V4=https://apieu.netcoresmartech.com;  V2=https://euceeapi.netcorecloud.net ;;
  *) echo "REGION must be ind, us or eu"; exit 1 ;;
esac
OUT="Logs/spike_$(date +%Y%m%d_%H%M%S)"; mkdir -p "$OUT"
echo "Public IP of this machine: $(curl -s https://api.ipify.org)"

call() {  # name, curl args...
  local name=$1; shift
  local meta
  meta=$(curl -sS -o "$OUT/$name.json" -w '%{http_code} %{time_total}s' "$@")
  echo "$name -> HTTP $meta  ($OUT/$name.json)"
  head -c 400 "$OUT/$name.json"; echo; echo
}

# V5 gateway (latest docs). Read-only contact search: tells us if the key works on v5 even when v4/apiv2 reject it.
# Body follows the docs sample: pagination.limit has a minimum of 10.
case "$REGION" in ind) V5=https://netcoreapi-main-prod-ind.netcorein.com/v5 ;; eu) V5=https://netcoreapi-main-prod-eu.netcorein.com/v5 ;; *) V5=https://netcoreapi-main-prod-us.netcorein.com/v5 ;; esac
call v5_contact_search -X POST "$V5/contact/search" -H "api-key: $NETCORE_API_KEY" -H 'Content-Type: application/json' \
  -d '{"filtering_criteria_operator":"or","filtering_criteria":[{"condition_operator":"and","condition_details":[{"field":"contact_type","field_category":"config","operation":"equals","value":["identified"]}]}],"output":{"get_count":false,"pagination":{"page":1,"limit":10},"fields":["EMAIL"]}}'

call campaign_list -X POST "$V4/v4/campaign/list" -H "api-key: $NETCORE_API_KEY" -H 'Content-Type: application/json' \
  -d '{"channel":["email"],"page_no":1,"page_size":50,"campaign_states":["sent"]}'

call audience_lists -X POST "$V4/v4/audience/list" -H "api-key: $NETCORE_API_KEY" -H 'Content-Type: application/json' \
  -d '{"page_details":{"page_no":1,"page_size":50},"audience_type":"list"}'

# Summary API: same contact over growing ranges, to find retention and range limit.
today=$(date +%d%m%Y)
for from in $(date -d '-1 year' +%d%m%Y) $(date -d '-2 year' +%d%m%Y) $(date -d '-3 year' +%d%m%Y) 01012020; do
  data=$(printf '{"primary_key":"%s","from_date":"%s","to_date":"%s"}' "$TEST_EMAIL" "$from" "$today")
  call "summary_from_$from" -X POST -G "$V2/apiv2" \
    --data-urlencode type=export_data --data-urlencode activity=get_user_summary_data \
    --data-urlencode "apikey=$NETCORE_API_KEY" --data-urlencode "data=$data"
done

# Burst of 20 summary calls back to back: look for 429 / slowdown.
echo "Burst test (20 calls, no delay):"
data=$(printf '{"primary_key":"%s","from_date":"%s","to_date":"%s"}' "$TEST_EMAIL" "$(date -d '-30 day' +%d%m%Y)" "$today")
for i in $(seq 1 20); do
  curl -s -o /dev/null -w '%{http_code}/%{time_total}s ' -X POST -G "$V2/apiv2" \
    --data-urlencode type=export_data --data-urlencode activity=get_user_summary_data \
    --data-urlencode "apikey=$NETCORE_API_KEY" --data-urlencode "data=$data"
done; echo

# Audience export is async: Netcore emails a download link. Only runs if NOTIFY_EMAIL and LIST_ID set.
if [ -n "${NOTIFY_EMAIL:-}" ] && [ -n "${LIST_ID:-}" ]; then
  call audience_export -X POST "$V4/v4/audience/export" -H "api-key: $NETCORE_API_KEY" -H 'Content-Type: application/json' \
    -d "{\"audience_details\":{\"audience_type\":\"list\",\"audience_id\":$LIST_ID},\"file_type\":\"csv\",\"notify_email\":\"$NOTIFY_EMAIL\"}"
fi
echo "Done. Send me the output above (it contains no API key)."
