"""Turns a round's blind verdicts into pass/fail and merges them into refs/results.json.

Usage: python -I scripts/aggregate_results.py <round-number>

A screen passes when (1) nothing the reference has is missing from Snapreel except branding,
sample content or server-only items, and (2) the judge does not prefer the reference for any
reason other than branding, content or needs-server.
A flow passes on the same rules plus step-for-step correspondence.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXCUSED = {"branding", "content", "needs-server"}


def side(key_entry, who, prefix):
    return next(k for k in (f"{prefix}-1", f"{prefix}-2") if key_entry[k] == who)


def judge(verdict, entry, prefix):
    mine = side(entry, "snapreel", prefix)
    ref = side(entry, "reference", prefix)
    n_ref = ref.split("-")[1]
    missing = [i for i in verdict.get(f"only_in_{prefix if prefix == 'strip' else 'image'}{n_ref}", [])
               if isinstance(i, dict) and i.get("kind") not in EXCUSED]
    better = verdict.get("better")
    prefers_ref = better == ref
    reasons = verdict.get("preference_reasons", []) if prefers_ref else []
    bad_reasons = [r for r in reasons if not (isinstance(r, dict) and r.get("kind") in EXCUSED)]
    ok = not missing and not bad_reasons
    if prefix == "strip" and verdict.get("correspond") is False:
        ok = False
    return {
        "pass": ok,
        "judgePrefers": "snapreel" if better == mine else ("reference" if prefers_ref else "equal"),
        "missingFromSnapreel": missing,
        "referencePreferredBecause": bad_reasons,
        "why": verdict.get("why"),
        "correspond": verdict.get("correspond"),
        "mismatches": verdict.get("mismatches"),
    }


def main():
    round_no = sys.argv[1]
    base = os.path.join(ROOT, "refs", "compare", f"round-{round_no}")
    key = json.load(open(os.path.join(base, "key.json"), encoding="utf-8"))
    out_path = os.path.join(ROOT, "refs", "results.json")
    results = json.load(open(out_path, encoding="utf-8")) if os.path.exists(out_path) else {"rounds": {}}
    rnd = {"screens": {}, "flows": {}, "missingScreenshots": key.get("missing", [])}
    for sid, entry in key["screens"].items():
        path = os.path.join(key["blind"], entry["dir"], "verdict.json")
        if not os.path.exists(path):
            rnd["screens"][sid] = {"pass": False, "error": "no verdict"}
            continue
        rnd["screens"][sid] = {"reference": entry["reference"], **judge(json.load(open(path, encoding="utf-8")), entry, "image")}
    for slug, entry in key["flows"].items():
        path = os.path.join(key["blind"], entry["dir"], "verdict.json")
        if not os.path.exists(path):
            rnd["flows"][slug] = {"pass": False, "error": "no verdict"}
            continue
        rnd["flows"][slug] = {"steps": entry["steps"], "droppedReferenceSteps": entry["droppedReferenceSteps"],
                              **judge(json.load(open(path, encoding="utf-8")), entry, "strip")}
    s_pass = sum(1 for r in rnd["screens"].values() if r.get("pass"))
    f_pass = sum(1 for r in rnd["flows"].values() if r.get("pass"))
    rnd["summary"] = {"screensPassed": s_pass, "screensJudged": len(rnd["screens"]),
                      "flowsPassed": f_pass, "flowsJudged": len(rnd["flows"])}
    results["rounds"][str(round_no)] = rnd
    json.dump(results, open(out_path, "w", encoding="utf-8"), indent=1)
    print(json.dumps(rnd["summary"]))
    for sid, r in rnd["screens"].items():
        if not r.get("pass"):
            print("FAIL screen", sid, "|", r.get("judgePrefers"), "|", [m.get("item") for m in r.get("missingFromSnapreel", [])],
                  [b.get("item") if isinstance(b, dict) else b for b in r.get("referencePreferredBecause", [])])
    for slug, r in rnd["flows"].items():
        if not r.get("pass"):
            print("FAIL flow", slug, "|", r.get("judgePrefers"), "| correspond:", r.get("correspond"), r.get("mismatches"))


if __name__ == "__main__":
    main()
