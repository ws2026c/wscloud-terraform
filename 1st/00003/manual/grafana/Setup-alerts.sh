#!/usr/bin/env bash
# Self-contained setup:
#   - discovers Grafana endpoint / credentials / datasource uids / log group
#   - creates all 6 alert rules (Grafana-managed)
#   - rewrites the dashboard so every panel points at the REAL datasource uids
#   - replaces the Alerts row with an Alert list panel
#
#   bash setup-alerts.sh
#
# Optional: NS APP_NS REGION GRAFANA_URL GRAFANA_USER GRAFANA_PASS LOG_GROUP
#           DASH_UID DASH_FILE FOLDER GROUP
set -uo pipefail

NS="${NS:-observability}"
APP_NS="${APP_NS:-wsc2026}"
REGION="${REGION:-ap-northeast-2}"
FOLDER="${FOLDER:-wsc2026}"
GROUP="${GROUP:-wsc2026-alerts}"
DASH_UID="${DASH_UID:-wsc2026-grafana-dashboard}"
DASH_FILE="${DASH_FILE:-./wsc2026-grafana-dashboard.json}"
PF_PORT=13000
PF_PID=""

cleanup() { [ -n "$PF_PID" ] && kill "$PF_PID" 2>/dev/null; }
trap cleanup EXIT
step() { echo; echo "== $* =="; }
die()  { echo "ERROR: $*" >&2; exit 1; }

req() {   # req METHOD PATH [file]
  local m="$1" p="$2" f="${3:-}" out
  if [ -n "$f" ]; then
    out=$(curl -s -m 60 -w $'\n%{http_code}' "${AUTH[@]}" -X "$m" "$API$p" \
          -H 'Content-Type: application/json' -H 'X-Disable-Provenance: true' \
          --data-binary "@$f")
  else
    out=$(curl -s -m 60 -w $'\n%{http_code}' "${AUTH[@]}" -X "$m" "$API$p")
  fi
  HTTP_CODE=$(printf '%s' "$out" | tail -1)
  HTTP_BODY=$(printf '%s' "$out" | sed '$d')
}

# ────────────────────────────────────────────────────────────
step "1. prerequisites"
for c in kubectl curl python3; do command -v "$c" >/dev/null || die "$c not found"; done
kubectl get ns "$NS" >/dev/null 2>&1 || die "namespace $NS not found"
echo "  ok"

# ────────────────────────────────────────────────────────────
step "2. grafana credentials"
GRAFANA_USER="${GRAFANA_USER:-admin}"
if [ -z "${GRAFANA_PASS:-}" ]; then
  kubectl -n "$NS" get deploy grafana -o json > /tmp/_gdeploy.json 2>/dev/null
  GRAFANA_PASS=$(python3 - <<'PY'
import json
try: d=json.load(open("/tmp/_gdeploy.json"))
except Exception: raise SystemExit
for c in d["spec"]["template"]["spec"]["containers"]:
    for e in c.get("env") or []:
        if e.get("name")=="GF_SECURITY_ADMIN_PASSWORD" and "value" in e:
            print(e["value"]); raise SystemExit
PY
)
fi
[ -z "$GRAFANA_PASS" ] && GRAFANA_PASS='admin'
AUTH=(-u "${GRAFANA_USER}:${GRAFANA_PASS}")
echo "  user=$GRAFANA_USER pass=${GRAFANA_PASS:0:3}***"

# ────────────────────────────────────────────────────────────
step "3. grafana endpoint"
API=""
if [ -n "${GRAFANA_URL:-}" ]; then
  API="${GRAFANA_URL%/}"
else
  LB=$(kubectl -n "$NS" get svc grafana-svc -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  [ -z "$LB" ] && LB=$(kubectl -n "$NS" get svc grafana-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ -n "$LB" ] && curl -sf -m 8 "${AUTH[@]}" "http://$LB/api/health" >/dev/null 2>&1; then
    API="http://$LB"
  else
    echo "  load balancer unreachable, using port-forward"
    kubectl -n "$NS" port-forward svc/grafana-svc ${PF_PORT}:80 >/tmp/pf-grafana.log 2>&1 &
    PF_PID=$!
    for i in $(seq 1 20); do sleep 1
      curl -sf -m 3 "${AUTH[@]}" "http://localhost:${PF_PORT}/api/health" >/dev/null 2>&1 && break
    done
    API="http://localhost:${PF_PORT}"
  fi
fi
req GET /api/health
[ "$HTTP_CODE" = "200" ] || { echo "$HTTP_BODY" | head -3; die "cannot reach grafana at $API"; }
echo "  $API  health=$HTTP_CODE"

# ────────────────────────────────────────────────────────────
step "4. datasources"
req GET /api/datasources
[ "$HTTP_CODE" = "200" ] || { echo "$HTTP_BODY" | head -3; die "datasource list failed (auth?)"; }
printf '%s' "$HTTP_BODY" > /tmp/_ds.json
python3 - <<'PY'
import json
for d in json.load(open("/tmp/_ds.json")):
    print(f"   - {d['name']:<16} {d['type']:<12} {d['uid']}  default={d.get('isDefault',False)}")
PY
pick_ds() {   # pick_ds <type> [preferred-name]
  local t="$1" pref="${2:-}"
  DS_TYPE="$t" DS_PREF="$pref" python3 - <<'PY'
import json, os
t = os.environ["DS_TYPE"]; pref = os.environ["DS_PREF"]
cands = [d for d in json.load(open("/tmp/_ds.json")) if d["type"] == t]
if not cands: raise SystemExit
for f in (lambda d: pref and d["name"] == pref,
          lambda d: d.get("isDefault"),
          lambda d: True):
    hit = [d for d in cands if f(d)]
    if hit: print(hit[0]["uid"]); break
PY
}
PROM_UID=$(pick_ds prometheus  Prometheus)
CW_UID=$(pick_ds  cloudwatch   CloudWatch)
AM_UID=$(pick_ds  alertmanager Alertmanager)
[ -n "$PROM_UID" ] || die "no prometheus datasource"
echo "  prometheus=$PROM_UID  cloudwatch=${CW_UID:-none}  alertmanager=${AM_UID:-none}"

# ────────────────────────────────────────────────────────────
step "5. aws account & log group"
ACCT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [ -z "${LOG_GROUP:-}" ]; then
  kubectl -n "$NS" get cm -o json > /tmp/_cms.json 2>/dev/null
  LOG_GROUP=$(python3 - <<'PY'
import json, re
try: d=json.load(open("/tmp/_cms.json"))
except Exception: raise SystemExit
for cm in d.get("items", []):
    for v in (cm.get("data") or {}).values():
        m = re.search(r"log_group_name\s+(\S+)", v)
        if m: print(m.group(1)); raise SystemExit
PY
)
fi
if [ -z "${LOG_GROUP:-}" ]; then
  LOG_GROUP=$(aws logs describe-log-groups --region "$REGION" \
    --query 'logGroups[].logGroupName' --output text 2>/dev/null \
    | tr '\t' '\n' | grep -v '/cluster$' | head -1)
fi
echo "  account=${ACCT:-unknown}  log_group=${LOG_GROUP:-none}"
[ -z "${LOG_GROUP:-}" ] && CW_UID=""

# ────────────────────────────────────────────────────────────
step "6. folder"
req GET /api/folders
printf '%s' "$HTTP_BODY" > /tmp/_folders.json
FOLDER_UID=$(FOLDER_NAME="$FOLDER" python3 - <<'PY'
import json, os
n = os.environ["FOLDER_NAME"]
try: fs = json.load(open("/tmp/_folders.json"))
except Exception: fs = []
print(next((f["uid"] for f in fs if f.get("title") == n), ""))
PY
)
if [ -z "$FOLDER_UID" ]; then
  printf '{"title":"%s"}' "$FOLDER" > /tmp/_folder.json
  req POST /api/folders /tmp/_folder.json
  [ "$HTTP_CODE" = "200" ] || { echo "$HTTP_BODY" | head -3; die "folder create failed"; }
  printf '%s' "$HTTP_BODY" > /tmp/_folderNew.json
  FOLDER_UID=$(python3 -c 'import json;print(json.load(open("/tmp/_folderNew.json"))["uid"])')
fi
echo "  folderUID=$FOLDER_UID"

# ────────────────────────────────────────────────────────────
step "7. build rule payloads"
rm -f /tmp/_rule-*.json
PROM_UID="$PROM_UID" CW_UID="$CW_UID" FOLDER_UID="$FOLDER_UID" REGION="$REGION" \
LOG_GROUP="${LOG_GROUP:-}" APP_NS="$APP_NS" GROUP="$GROUP" ACCT="$ACCT" python3 - <<'PY'
import json, os
PROM=os.environ["PROM_UID"]; CW=os.environ["CW_UID"]; FOLDER=os.environ["FOLDER_UID"]
REGION=os.environ["REGION"]; LG=os.environ["LOG_GROUP"]; NS=os.environ["APP_NS"]
GROUP=os.environ["GROUP"]; ACCT=os.environ["ACCT"]
LG_ARN=f"arn:aws:logs:{REGION}:{ACCT}:log-group:{LG}:*"

def prom(expr):
    return {"refId":"A","queryType":"","relativeTimeRange":{"from":600,"to":0},
            "datasourceUid":PROM,
            "model":{"refId":"A","editorMode":"code","expr":expr,
                     "instant":True,"range":False,
                     "intervalMs":60000,"maxDataPoints":43200}}

def cw(expr, groups=None):
    return {"refId":"A","queryType":"","relativeTimeRange":{"from":900,"to":0},
            "datasourceUid":CW,
            "model":{"refId":"A","queryMode":"Logs","region":REGION,"id":"",
                     "queryLanguage":"CWLI",
                     "logGroups":[{"arn":LG_ARN,"name":LG,"accountId":ACCT}],
                     "logGroupNames":[LG],
                     "expression":expr,"statsGroups":groups or ["bin(1m)"],
                     "intervalMs":60000,"maxDataPoints":43200}}

def red(rng):
    return {"refId":"B","queryType":"","relativeTimeRange":{"from":rng,"to":0},
            "datasourceUid":"__expr__",
            "model":{"refId":"B","type":"reduce","reducer":"last","expression":"A",
                     "settings":{"mode":"dropNN"}}}

def thr(v,rng):
    return {"refId":"C","queryType":"","relativeTimeRange":{"from":rng,"to":0},
            "datasourceUid":"__expr__",
            "model":{"refId":"C","type":"threshold","expression":"B",
                     "conditions":[{"type":"query",
                                    "evaluator":{"type":"gt","params":[v]},
                                    "operator":{"type":"and"},
                                    "query":{"params":["C"]},
                                    "reducer":{"type":"last","params":[]}}]}}

def rule(uid,title,q,v,wait,sev,summary,rng=600,nodata="OK"):
    return {"uid":uid,"title":title,"ruleGroup":GROUP,"folderUID":FOLDER,"orgID":1,
            "condition":"C","for":wait,"noDataState":nodata,"execErrState":"Error",
            "isPaused":False,"labels":{"severity":sev,"alertsource":"grafana"},
            "annotations":{"summary":summary},"data":[q,red(rng),thr(v,rng)]}

rules=[
 rule("wsc2026-pod-high-cpu","PodHighCPU",
   prom('100 * sum by (namespace, pod) (\n'
        '  rate(container_cpu_usage_seconds_total{container!="", container!="POD"}[5m])\n'
        ')\n/ sum by (namespace, pod) (\n'
        '  kube_pod_container_resource_limits{resource="cpu"}\n)'),
   80,"3m","warning","Pod CPU usage exceeds 80% for 3 minutes"),
 rule("wsc2026-pod-high-memory","PodHighMemory",
   prom('100 * sum by (namespace, pod) (\n'
        '  container_memory_working_set_bytes{container!="", container!="POD"}\n'
        ')\n/ sum by (namespace, pod) (\n'
        '  kube_pod_container_resource_limits{resource="memory"}\n)'),
   90,"3m","warning","Pod Memory usage exceeds 90% for 3 minutes"),
 rule("wsc2026-pod-not-ready","PodNotReady",
   prom('count by (namespace, pod) (kube_pod_status_ready{condition="true"} == 0)\n'
        'or\n'
        'count by (namespace, pod) (kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1)'),
   0,"3m","critical","Pod is not ready or CrashLoopBackOff for 3 minutes"),
 rule("wsc2026-pod-crash-looping","PodCrashLooping",
   prom(f'max by (namespace, pod) (\n'
        f'  kube_pod_container_status_restarts_total{{namespace="{NS}"}}\n)'),
   3,"3m","critical",f"Pod restart count in {NS} NS exceeded 3 for 3 minutes"),
]

if CW and LG:
    rules += [
     rule("wsc2026-high-error-rate","HighErrorRate",
       cw('fields @timestamp\n'
          '| parse @message /"status":\\s*"(?<code>\\d{3})"/\n'
          '| filter ispresent(code)\n'
          '| fields code + 0 as num\n'
          '| fields num >= 400 as isError\n'
          '| stats sum(isError) * 100.0 / count(*) as ErrorRate by bin(1m)'),
       5,"1m","critical","4xx/5xx error rate exceeds 5% for 1 minute",rng=900),
     rule("wsc2026-high-latency","HighLatency",
       cw('fields @timestamp\n'
          '| parse @message /"path":\\s*"(?<path>[^"]+)"/\n'
          '| parse @message /"duration":\\s*"(?<val>[0-9.]+)(?<unit>[^"]+)"/\n'
          '| filter ispresent(val)\n'
          '| fields val + 0 as v\n'
          '| fields (unit = "ms") as isMs, (unit = "s") as isS\n'
          '| fields v * isMs + v * 1000 * isS + (v / 1000) * (1 - isMs - isS) as ms\n'
          '| stats avg(ms) as AvgLatency by bin(1m), path',
          groups=["bin(1m)","path"]),
       3000,"1m","warning","Average response time exceeds 3 seconds for 1 minute",rng=900),
    ]

for i,r in enumerate(rules):
    json.dump(r, open(f"/tmp/_rule-{i}-{r['uid']}.json","w"), ensure_ascii=False)
print("   " + ", ".join(r["title"] for r in rules))
PY

# ────────────────────────────────────────────────────────────
step "8. create / update rules"
NOK=0; NFAIL=0
for f in /tmp/_rule-*.json; do
  RULE_TITLE=$(RF="$f" python3 -c 'import json,os;print(json.load(open(os.environ["RF"]))["title"])')
  RULE_UID=$(RF="$f"  python3 -c 'import json,os;print(json.load(open(os.environ["RF"]))["uid"])')
  req GET "/api/v1/provisioning/alert-rules/$RULE_UID"
  if [ "$HTTP_CODE" = "200" ]; then
    req PUT "/api/v1/provisioning/alert-rules/$RULE_UID" "$f"
  else
    req POST "/api/v1/provisioning/alert-rules" "$f"
  fi
  if [[ "$HTTP_CODE" == 2* ]]; then echo "  OK   $RULE_TITLE"; NOK=$((NOK+1))
  else echo "  FAIL $RULE_TITLE http=$HTTP_CODE"; echo "$HTTP_BODY" | head -2 | sed 's/^/       /'; NFAIL=$((NFAIL+1)); fi
done
printf '{"title":"%s","folderUid":"%s","interval":60}' "$GROUP" "$FOLDER_UID" > /tmp/_grp.json
req PUT "/api/v1/provisioning/folder/$FOLDER_UID/rule-groups/$GROUP" /tmp/_grp.json
echo "  rule-group interval(60s) http=$HTTP_CODE"

# ────────────────────────────────────────────────────────────
step "9. fix dashboard datasource uids + alerts row"
BASE=""
if [ -f "$DASH_FILE" ]; then
  python3 - "$DASH_FILE" <<'DPY'
import json, sys
d = json.load(open(sys.argv[1]))
json.dump({"dashboard": d}, open("/tmp/_dash.json", "w"), ensure_ascii=False)
DPY
  BASE=file
  echo "  using local file $DASH_FILE"
else
  req GET "/api/dashboards/uid/$DASH_UID"
  if [ "$HTTP_CODE" = "200" ]; then
    printf '%s' "$HTTP_BODY" > /tmp/_dash.json
    BASE=existing
    echo "  $DASH_FILE not found, using dashboard in grafana"
  else
    echo "  dashboard not found and $DASH_FILE missing (skip)"
  fi
fi

if [ -n "$BASE" ]; then
  PROM_UID="$PROM_UID" CW_UID="$CW_UID" AM_UID="$AM_UID" FOLDER_UID="$FOLDER_UID" python3 - <<'PY'
import json, os
PROM=os.environ["PROM_UID"]; CW=os.environ["CW_UID"]; AM=os.environ["AM_UID"]
FOLDER=os.environ["FOLDER_UID"]
MAP={"prometheus":PROM,"cloudwatch":CW,"alertmanager":AM}

raw=json.load(open("/tmp/_dash.json"))
d=raw["dashboard"]
d.pop("__inputs",None); d.pop("__requires",None); d.pop("id",None)

fixed=0
def fix(o):
    global fixed
    if isinstance(o,dict):
        ds=o.get("datasource")
        if isinstance(ds,dict) and ds.get("type") in MAP and MAP[ds["type"]]:
            if ds.get("uid")!=MAP[ds["type"]]:
                ds["uid"]=MAP[ds["type"]]; fixed+=1
        elif isinstance(ds,str) and ds.lower() in MAP and MAP[ds.lower()]:
            o["datasource"]={"type":ds.lower(),"uid":MAP[ds.lower()]}; fixed+=1
        for v in o.values(): fix(v)
    elif isinstance(o,list):
        for v in o: fix(v)
fix(d.get("panels",[]))
fix(d.get("templating",{}))

panels=d.get("panels",[])
keep=[];removed=[];ypos=None
for p in panels:
    if p.get("type") in ("alertGroups","alertlist","table") and \
       p.get("title") in ("Active Alerts","Firing Alerts"):
        removed.append(p.get("title"))
        if ypos is None: ypos=p["gridPos"]["y"]
        continue
    keep.append(p)
if ypos is None:
    ypos=max((p["gridPos"]["y"]+p["gridPos"]["h"]) for p in keep) if keep else 0
maxid=max((p.get("id",0) for p in panels),default=0)
keep.append({"id":maxid+1,"type":"alertlist","title":"Active Alerts",
  "gridPos":{"h":16,"w":24,"x":0,"y":ypos},
  "options":{"viewMode":"list","groupMode":"default","maxItems":20,"sortOrder":1,
             "dashboardAlerts":False,"alertName":"","dashboardTitle":"",
             "folder":"","showInstances":True,"tags":[],
             "stateFilter":{"firing":True,"pending":True,"recovering":True,
                            "noData":False,"normal":False,"error":False},
             "alertInstanceLabelFilter":'{alertsource="grafana"}',"datasource":""}})
d["panels"]=keep
json.dump({"dashboard":d,"overwrite":True,"message":"fix datasources + alerts row"},
          open("/tmp/_dash-post.json","w"),ensure_ascii=False)
print(f"   datasource refs fixed: {fixed} | alerts row: {removed or 'none'} -> alertlist y={ypos}")
PY
  req POST "/api/dashboards/db" /tmp/_dash-post.json
  if [[ "$HTTP_CODE" == 2* ]]; then echo "  dashboard saved"
  else echo "  dashboard save FAILED http=$HTTP_CODE"; echo "$HTTP_BODY" | head -3 | sed 's/^/       /'; fi
fi

# ────────────────────────────────────────────────────────────
step "10. result"
req GET /api/v1/provisioning/alert-rules
printf '%s' "$HTTP_BODY" > /tmp/_rules.json
python3 - <<'PY'
import json
try: rs=json.load(open("/tmp/_rules.json"))
except Exception: rs=[]
if not rs: print("  (none)")
for r in rs:
    t=r.get("title",""); fo=r.get("for",""); g=r.get("ruleGroup","")
    print("  %-18s for=%-4s group=%s" % (t, fo, g))
PY
echo
echo "rules ok=$NOK fail=$NFAIL"
echo "Grafana: $API   (Alerting > Alert rules > $FOLDER)"