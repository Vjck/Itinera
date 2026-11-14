#!/usr/bin/env python3
"""Builds the visual test report in ./report from the test attachments.

- copies the screenshots with readable names
- lists the problems found by Apple's accessibility audit
- if ANTHROPIC_API_KEY is set, asks Claude to review the screenshots
Only the Python standard library is used. The script never fails the job.
"""
import base64
import json
import os
import re
import shutil
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

ATTACHMENTS = Path("attachments")
REPORT = Path("report")
SHOTS = REPORT / "screenshots"
MODEL = os.environ.get("UI_REVIEW_MODEL") or "claude-sonnet-5-5"
SUFFIX = re.compile(r"^(.*?)_\d+_[0-9A-Fa-f-]{36}(\.\w+)$")

PROMPT = """Sei un revisore di interfacce iOS. Queste sono le schermate di un'app SwiftUI \
(iPhone, lingua italiana), ciascuna preceduta dal suo nome.
Cerca solo problemi reali e visibili: elementi disallineati, testi tagliati o troncati male, \
spaziature incoerenti, contenuti sotto la Dynamic Island o la barra Home (safe area), \
contrasto o colori poco leggibili, font incoerenti, layout sbilanciati, elementi sovrapposti.
Non segnalare gusti personali e non inventare problemi: se una schermata è a posto non citarla.
Rispondi SOLO con un array JSON, senza testo attorno. Ogni elemento:
{"schermata": "<nome>", "gravita": "alta|media|bassa", "problema": "<cosa si vede e dove>", \
"correzione": "<modifica SwiftUI suggerita>"}
Se non c'è nessun problema rispondi []."""


def collect():
    """Copies attachments into the report and returns (screenshots, audit text)."""
    SHOTS.mkdir(parents=True, exist_ok=True)
    names = {}
    manifest = ATTACHMENTS / "manifest.json"
    if manifest.exists():
        try:
            for test in json.loads(manifest.read_text()):
                for item in test.get("attachments", []):
                    names[item.get("exportedFileName")] = item.get("suggestedHumanReadableName") or ""
        except (ValueError, AttributeError, TypeError):
            pass
    shots, audit = [], ""
    files = sorted(p for p in ATTACHMENTS.glob("*") if p.is_file() and p.name != "manifest.json") \
        if ATTACHMENTS.exists() else []
    for path in files:
        human = names.get(path.name) or path.name
        match = SUFFIX.match(human)
        clean = (match.group(1) + match.group(2)) if match else human
        if path.suffix.lower() in (".png", ".jpg", ".jpeg", ".heic"):
            target = SHOTS / clean
            shutil.copyfile(path, target)
            shots.append(target)
        elif clean.startswith("audit"):
            audit = path.read_text(errors="replace")
    return sorted(shots), audit


def small_copy(path):
    """Returns PNG bytes scaled down for the API (keeps cost and size low)."""
    tmp = Path("/tmp") / ("small-" + path.stem + ".png")
    try:
        subprocess.run(["sips", "-s", "format", "png", "-Z", "1568", str(path), "--out", str(tmp)],
                       check=True, capture_output=True)
        return tmp.read_bytes()
    except (OSError, subprocess.CalledProcessError):
        return path.read_bytes()


def review(shots):
    """Returns (issues or None, note)."""
    key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not key:
        return None, ("Analisi automatica non eseguita: il secret `ANTHROPIC_API_KEY` non è configurato. "
                      "Le schermate sono comunque pronte per essere analizzate da Claude in chat.")
    if not shots:
        return None, "Analisi automatica non eseguita: nessuno screenshot disponibile."
    content = []
    for shot in shots:
        content.append({"type": "text", "text": f"Schermata: {shot.stem}"})
        content.append({"type": "image", "source": {
            "type": "base64", "media_type": "image/png",
            "data": base64.b64encode(small_copy(shot)).decode()}})
    content.append({"type": "text", "text": PROMPT})
    body = json.dumps({"model": MODEL, "max_tokens": 4000,
                       "messages": [{"role": "user", "content": content}]}).encode()
    request = urllib.request.Request(
        "https://api.anthropic.com/v1/messages", data=body,
        headers={"x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            data = json.loads(response.read())
    except urllib.error.HTTPError as error:
        return None, f"Analisi automatica fallita: HTTP {error.code} {error.read().decode(errors='replace')[:400]}"
    except (urllib.error.URLError, TimeoutError, ValueError) as error:
        return None, f"Analisi automatica fallita: {error}"
    text = "".join(block.get("text", "") for block in data.get("content", []) if block.get("type") == "text")
    start, end = text.find("["), text.rfind("]")
    try:
        issues = json.loads(text[start:end + 1])
        if not isinstance(issues, list):
            raise ValueError
    except ValueError:
        return None, "Analisi automatica: risposta non interpretabile.\n\n" + text[:2000]
    return issues, f"Analisi eseguita con il modello `{MODEL}`."


def cell(value):
    return str(value).replace("|", "/").replace("\n", " ").strip()


def main():
    REPORT.mkdir(exist_ok=True)
    shots, audit = collect()
    issues, note = review(shots)
    outcome = os.environ.get("TEST_OUTCOME", "sconosciuto")
    sha = os.environ.get("GITHUB_SHA", "")[:7]
    lines = [
        "# Report grafico Itinera", "",
        f"- Commit: `{sha}`",
        f"- Simulatore: {os.environ.get('SIM_NAME', '?')} (iOS {os.environ.get('SIM_OS', '?')})",
        f"- Esito dei test delle schermate: **{'superati' if outcome == 'success' else outcome}**",
        f"- Screenshot acquisiti: {len(shots)}", "",
        "## Analisi visiva (Claude)", "", note, "",
    ]
    if issues:
        lines += ["| Schermata | Gravità | Problema | Correzione suggerita |", "|---|---|---|---|"]
        for issue in issues:
            if isinstance(issue, dict):
                lines.append("| " + " | ".join(cell(issue.get(k, "")) for k in
                                               ("schermata", "gravita", "problema", "correzione")) + " |")
        lines.append("")
    elif issues == []:
        lines += ["Nessun problema individuato.", ""]
    if issues is not None:
        (REPORT / "issues.json").write_text(json.dumps(issues, ensure_ascii=False, indent=2))

    lines += ["## Controllo automatico di accessibilità (Xcode)", ""]
    rows = [row.split(" | ", 3) for row in audit.splitlines() if row.strip()]
    if rows:
        lines += ["| Schermata | Tipo | Problema | Dettaglio |", "|---|---|---|---|"]
        lines += ["| " + " | ".join(cell(c) for c in (row + [""] * 4)[:4]) + " |" for row in rows]
    else:
        lines.append("Nessun problema segnalato." if shots else "Controllo non eseguito.")
    (REPORT / "audit.txt").write_text(audit)

    lines += ["", "## Schermate", ""]
    for shot in shots:
        lines += [f"### {shot.stem}", "", f'<img src="screenshots/{shot.name}" width="300">', ""]
    if not shots:
        lines += ["Nessuno screenshot: i test non sono arrivati ad acquisirne. Vedi `xcodebuild-fine.txt`.", ""]

    log = Path("xcodebuild.log")
    if log.exists():
        tail = log.read_text(errors="replace").splitlines()
        errors = [l for l in tail if "error:" in l or "Test Case" in l or "** TEST" in l]
        (REPORT / "xcodebuild-fine.txt").write_text("\n".join(errors[-200:] + ["", "--- ultime righe ---"] + tail[-150:]))

    text = "\n".join(lines) + "\n"
    (REPORT / "report.md").write_text(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as handle:
            handle.write(text.split("## Schermate")[0])
            handle.write("\nScreenshot e report completo: artifact `ui-report` e branch `ui-report`.\n")
    print(text.split("## Schermate")[0])


if __name__ == "__main__":
    main()
