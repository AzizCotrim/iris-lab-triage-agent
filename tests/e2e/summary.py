"""Prints one line per final output in data/out: message number, decision,
agent provider/attempts and the reasonCode of every exam."""
import glob
import json

for f in sorted(glob.glob("data/out/*/*.final.json")):
    d = json.load(open(f))
    items = [e["code"] + ":" + e["reasonCode"] for k in ("critical", "review", "released") for e in d[k]]
    a = d["agent"]
    agent = a["provider"] + "/" + str(a["attempts"]) if a["called"] else "no-agent"
    print(d["messageControlId"][-4:], d["decision"], agent, " ".join(items))