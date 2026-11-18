"""Turns a round's blind verdicts into pass/fail and merges them into refs/results.json.

Usage: python -I scripts/aggregate_results.py <round-number>

A screen passes when (1) nothing the reference has is missing from Snapreel except branding,
sample content or server-only items, and (2) the judge does not prefer the reference for any
reason other than branding, content or needs-server.
A flow passes on the same rules plus step-for-step correspondence.

Two results are recorded per screen and flow:
- "pass": the judge's own tags only.
- "passAfterTriage": also excusing items the lead triaged in refs/compare/round-<n>/triage.json
  (server-only, drawn by iOS, or the same job in another layout). Each excused item keeps its
  reason. Items triaged "fixedNext" or "real: ..." are real gaps and stay missing. Craft preferences for the
  reference are never excused.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXCUSED = {"branding", "content", "needs-server"}


def norm(item):
    """Judges wrote items as {"item"|"detail"|"name"|"reason": ..., "kind": ...} or plain strings."""
    if isinstance(item, str):
        return {"item": item, "kind": "feature"}
    text = item.get("item") or item.get("detail") or item.get("name") or item.get("reason") or json.dumps(item)
    return {"item": text, "kind": item.get("kind", "feature")}


class Triage:
    def __init__(self, data):
        self.data = data or {}
        self.globals = [(re.compile(g["pattern"], re.I), g["reason"]) for g in self.data.get("global", [])]

    def reason(self, scope, key, text):
        specific = self.data.get(scope, {}).get(key, {})
        if scope == "flows":
            specific = specific.get("items", {})
        if text in specific:
            return specific[text]
        for pattern, why in self.globals:
            if pattern.search(text):
                return why
        return None

    def step_reason(self, slug, step):
        return self.data.get("flows", {}).get(slug, {}).get("steps", {}).get(str(step))


def excuses(why):
    """A lead reason excuses an item unless it marks a real gap ("fixedNext" or "real: ...")."""
    return bool(why) and why != "fixedNext" and not why.startswith("real")


def side(key_entry, who, prefix):
    return next(k for k in (f"{prefix}-1", f"{prefix}-2") if key_entry[k] == who)


def judge(verdict, entry, prefix, triage, scope, key):
    mine = side(entry, "snapreel", prefix)
    ref = side(entry, "reference", prefix)
    n_ref = ref.split("-")[1]
    listed = [norm(i) for i in verdict.get(f"only_in_{prefix}{n_ref}", [])]
    missing = [i for i in listed if i["kind"] not in EXCUSED]
    better = verdict.get("better")
    prefers_ref = better == ref
    reasons = [norm(r) for r in verdict.get("preference_reasons", [])] if prefers_ref else []
    bad_reasons = [r for r in reasons if r["kind"] not in EXCUSED]
    correspond = verdict.get("correspond")
    ok = not missing and not bad_reasons and not (prefix == "strip" and correspond is False)

    # Lead triage.
    excused, still_missing = [], []
    for item in missing:
        why = triage.reason(scope, key, item["item"])
        if excuses(why):
            excused.append({**item, "leadReason": why})
        else:
            still_missing.append({**item, "leadReason": why} if why else item)
    still_bad = []
    for r in bad_reasons:
        why = None if r["kind"] == "craft" else triage.reason(scope, key, r["item"])
        if excuses(why):
            excused.append({**r, "leadReason": why, "preference": True})
        else:
            still_bad.append(r)
    open_mismatches = []
    if prefix == "strip" and correspond is False:
        for m in verdict.get("mismatches", []) or []:
            step = m.get("step") if isinstance(m, dict) else None
            why = triage.step_reason(key, step) if step is not None else None
            if why:
                excused.append({"item": f"step {step}: {m.get('detail')}", "kind": "mismatch", "leadReason": why})
            else:
                open_mismatches.append(m)
    triaged_ok = not still_missing and not still_bad and not (prefix == "strip" and correspond is False and open_mismatches)

    return {
        "pass": ok,
        "passAfterTriage": triaged_ok,
        "judgePrefers": "snapreel" if better == mine else ("reference" if prefers_ref else "equal"),
        "missingFromSnapreel": missing,
        "referencePreferredBecause": bad_reasons,
        "excusedByLead": excused,
        "stillMissing": still_missing + still_bad + [{"item": f"step {m.get('step')}: {m.get('detail')}", "kind": "mismatch"}
                                                     for m in open_mismatches if isinstance(m, dict)],
        "why": verdict.get("why"),
        "correspond": correspond,
        "mismatches": verdict.get("mismatches"),
    }


def main():
    round_no = sys.argv[1]
    base = os.path.join(ROOT, "refs", "compare", f"round-{round_no}")
    key = json.load(open(os.path.join(base, "key.json"), encoding="utf-8"))
    triage_path = os.path.join(base, "triage.json")
    triage = Triage(json.load(open(triage_path, encoding="utf-8")) if os.path.exists(triage_path) else None)
    out_path = os.path.join(ROOT, "refs", "results.json")
    results = json.load(open(out_path, encoding="utf-8")) if os.path.exists(out_path) else {"rounds": {}}
    rnd = {"screens": {}, "flows": {}, "missingScreenshots": key.get("missing", [])}
    for sid, entry in key["screens"].items():
        path = os.path.join(key["blind"], entry["dir"], "verdict.json")
        if not os.path.exists(path):
            rnd["screens"][sid] = {"pass": False, "passAfterTriage": False, "error": "no verdict"}
            continue
        rnd["screens"][sid] = {"reference": entry["reference"],
                               **judge(json.load(open(path, encoding="utf-8")), entry, "image", triage, "screens", sid)}
    for slug, entry in key["flows"].items():
        path = os.path.join(key["blind"], entry["dir"], "verdict.json")
        if not os.path.exists(path):
            rnd["flows"][slug] = {"pass": False, "passAfterTriage": False, "error": "no verdict"}
            continue
        rnd["flows"][slug] = {"steps": entry["steps"], "droppedReferenceSteps": entry["droppedReferenceSteps"],
                              **judge(json.load(open(path, encoding="utf-8")), entry, "strip", triage, "flows", slug)}

    def count(group, field):
        return sum(1 for r in rnd[group].values() if r.get(field))

    rnd["summary"] = {
        "screensJudged": len(rnd["screens"]), "screensPassed": count("screens", "pass"),
        "screensPassedAfterTriage": count("screens", "passAfterTriage"),
        "screensJudgePrefersSnapreel": sum(1 for r in rnd["screens"].values() if r.get("judgePrefers") == "snapreel"),
        "flowsJudged": len(rnd["flows"]), "flowsPassed": count("flows", "pass"),
        "flowsPassedAfterTriage": count("flows", "passAfterTriage"),
        "flowsJudgePrefersSnapreel": sum(1 for r in rnd["flows"].values() if r.get("judgePrefers") == "snapreel"),
        "triageFile": os.path.relpath(triage_path, ROOT).replace("\\", "/") if os.path.exists(triage_path) else None,
    }
    results["rounds"][str(round_no)] = rnd
    json.dump(results, open(out_path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print(json.dumps(rnd["summary"]))
    for group in ("screens", "flows"):
        for sid, r in rnd[group].items():
            if not r.get("passAfterTriage"):
                print("STILL FAILS", group[:-1], sid, "|", r.get("judgePrefers"), "|",
                      [m.get("item") for m in r.get("stillMissing", [])])


if __name__ == "__main__":
    main()
