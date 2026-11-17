#!/usr/bin/env python3
"""Generates Resources/Fixtures/*.json. Mirrors SSCore's Text.swift rules (checked by SSCoreTests)."""
import datetime as dt
import json
import os
import sys
import uuid

OUT = sys.argv[1]
NS = uuid.UUID("6f6e2b8e-3a51-4c43-9d0e-5e7267616e61")


def uid(kind, key):
    return str(uuid.uuid5(NS, f"{kind}:{key}")).upper()


PREFIXES = {"ASD", "US", "USD", "GS", "FC", "AC", "SSD", "POL", "POLISPORTIVA"}
STOP = {"di", "da", "de", "del", "della", "dello", "dei", "degli", "delle", "e", "ed", "il", "lo", "la", "i",
        "gli", "le", "l", "d"}


def strip(name):
    words = name.split()
    i = 0
    while i < len(words) and words[i].replace(".", "").upper() in PREFIXES:
        i += 1
    return " ".join(words if i == len(words) else words[i:])


def trunc(text, mx):
    text = text.strip()
    if len(text) <= mx:
        return text, False
    room = mx - 1
    kept = ""
    for w in text.split():
        cand = w if not kept else kept + " " + w
        if len(cand) > room:
            break
        kept = cand
    if not kept:
        kept = text[:room]
    while kept and (kept[-1] in ",-.'’:;·" or kept[-1].isspace()):
        kept = kept[:-1]
    return kept + "…", True


def display(opp, limit):
    base = opp.get("shortName") or strip(opp["name"])
    return trunc(base, limit)[0] if limit else base


def initials(name):
    import re
    words = [re.sub(r"[^\w]", "", w) for w in re.split(r"[\s\-'’]+", strip(name))]
    words = [w.replace("_", "") for w in words if w.replace("_", "")]
    sig = [w for w in words if w.lower() not in STOP] or words
    if not sig:
        return ""
    if len(sig) == 1:
        return sig[0][:2].upper()
    return "".join(w[0] for w in sig[:3]).upper()


WD = ["Lunedì", "Martedì", "Mercoledì", "Giovedì", "Venerdì", "Sabato", "Domenica"]
WDS = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]
MO = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre",
      "novembre", "dicembre"]
MOS = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]


def dlong(d):
    d = dt.date.fromisoformat(d)
    return f"{WD[d.weekday()]} {d.day} {MO[d.month - 1]}"


def dshort(d):
    d = dt.date.fromisoformat(d)
    return f"{WDS[d.weekday()]} {d.day} {MOS[d.month - 1]}"


# ---------------------------------------------------------------- data set
SETTINGS = {
    "clubName": "ASD Sergnanese", "clubShortName": "Sergnanese", "season": "2026/27",
    "accentColor": "#CF3326", "socialHandle": "@sergnanese.demo", "homeVenue": "Campo Comunale",
}
CLUB_LOGO = "assets/club-logo.png"

TEAM_NAMES = [
    ("Prima Squadra", "Prima Squadra"), ("Juniores", "Juniores"), ("Allievi U17", "Allievi U17"),
    ("Allievi U16", "Allievi U16"), ("Giovanissimi U15", "Giov. U15"), ("Giovanissimi U14", "Giov. U14"),
    ("Esordienti", "Esordienti"), ("Pulcini", "Pulcini"), ("Primi Calci", "Primi Calci"),
    ("Femminile", "Femminile"), ("Juniores Femminile", "Jun. Femminile"), ("Amatori", "Amatori"),
    ("Veterani", "Veterani"),
]
teams = []
for i, (name, label) in enumerate(TEAM_NAMES):
    teams.append({"id": uid("team", name), "name": name, "shortLabel": label, "sortOrder": i,
                  "isFirstTeam": i == 0, "isActive": name != "Veterani"})
T = {t["name"]: t for t in teams}

# (key, name, shortName, logo?, aliases)
OPP = [
    ("gerolamo", "A.S.D. Oratorio San Gerolamo", "San Gerolamo", True, ["Oratorio S. Gerolamo"]),
    ("eufrasio", "A.C. Oratorio Sant'Eufrasio di Valfonda Bassa", None, True, []),
    ("castelverde", "U.S. Castelverde Calcio", None, True, []),
    ("valdorso", "F.C. Valdorso", None, True, []),
    ("borgolucente", "Pol. Borgo Lucente", None, False, []),
    ("pratofiorito", "A.C. Prato Fiorito", None, True, []),
    ("novaria", "S.S.D. Novaria Bassa", None, True, []),
    ("cascina", "Real Cascina Alta", None, True, []),
    ("ripalta", "Sporting Ripalta Nuova", None, True, []),
    ("montesello", "Atletico Montesello", None, False, []),
    ("ilario", "G.S. Sant'Ilario Città", None, True, ["Sant'Ilario"]),
    ("campofelice", "Virtus Campofelice", None, True, []),
    ("brolo", "Unione Calcio Brolo Verde", None, True, []),
    ("lucia", "Oratorio Santa Lucia", None, True, []),
]
opponents = []
for key, name, short, logo, aliases in OPP:
    o = {"id": uid("opponent", key), "name": name, "aliases": aliases}
    if short:
        o["shortName"] = short
    if logo:
        o["logoFile"] = f"fixture-{key}.png"
    opponents.append(o)
O = {k: o for (k, *_), o in zip(OPP, opponents)}
assert len(O["eufrasio"]["name"]) == 45, len(O["eufrasio"]["name"])

AWAY_VENUE = {
    "gerolamo": "Campo Oratorio San Gerolamo", "eufrasio": "Centro Sportivo Valfonda", "castelverde": "Comunale Castelverde",
    "valdorso": "Campo Valdorso", "borgolucente": "Comunale Borgo Lucente", "pratofiorito": "Prato Fiorito",
    "novaria": "Stadio Novaria", "cascina": "Campo Cascina Alta", "ripalta": "Ripalta Nuova",
    "montesello": "Comunale Montesello", "ilario": "Campo Sant'Ilario", "campofelice": "Campofelice",
    "brolo": "Brolo Verde", "lucia": "Oratorio Santa Lucia",
}

CREATED = "2026-11-10T09:00:00Z"
matches = []


def match(key, team, opp, date, time, home, *, status="scheduled", score=None, half=None, notes=None,
          competition=None, rnd=None, source="seed", locked=False):
    m = {"id": uid("match", key), "teamID": T[team]["id"], "opponentID": O[opp]["id"], "date": date,
         "isHome": home, "venue": SETTINGS["homeVenue"] if home else AWAY_VENUE[opp], "status": status,
         "source": source, "isLocked": locked, "createdAt": CREATED, "updatedAt": CREATED}
    if time:
        m["time"] = time
    if competition:
        m["competition"] = competition
    if rnd:
        m["round"] = rnd
    if score:
        m["score"] = {"us": score[0], "them": score[1]}
    if half:
        m["halfTime"] = {"us": half[0], "them": half[1]}
    if notes:
        m["notes"] = notes
    matches.append(m)
    return m


PC = "Prima Categoria · Girone C"
# Previous weekend: played, with scores.
match("p1", "Prima Squadra", "ripalta", "2026-11-15", "14:30", False, status="played", score=(2, 1), half=(1, 0),
      notes="Rossi 23', Bianchi 78'", competition=PC, rnd=11)
match("p2", "Juniores", "brolo", "2026-11-14", "15:00", True, status="played", score=(0, 0), half=(0, 0),
      competition="Juniores Regionali", rnd=9)
match("p3", "Allievi U17", "lucia", "2026-11-15", "10:30", False, status="played", score=(3, 3), half=(1, 2),
      notes="Verdi (2), Neri")
match("p4", "Femminile", "campofelice", "2026-11-14", "18:00", True, status="played", score=(4, 0), half=(2, 0))

# Reference weekend ("Questo weekend"): 21-22 Nov 2026, 10 matches.
match("r1", "Allievi U17", "castelverde", "2026-11-21", "15:00", True, rnd=10)
match("r2", "Giovanissimi U15", "valdorso", "2026-11-21", "16:30", False)
match("r3", "Esordienti", "borgolucente", "2026-11-21", "15:00", True)
match("r4", "Pulcini", "pratofiorito", "2026-11-21", None, False)
match("r5", "Prima Squadra", "gerolamo", "2026-11-22", "14:30", True, competition=PC, rnd=12)
match("r6", "Juniores", "eufrasio", "2026-11-22", "10:30", False, competition="Juniores Regionali", rnd=10)
match("r7", "Allievi U16", "novaria", "2026-11-22", "10:00", True)
match("r8", "Giovanissimi U14", "cascina", "2026-11-22", "09:30", False)
match("r9", "Femminile", "ilario", "2026-11-22", "18:00", True, status="postponed")
match("r10", "Primi Calci", "montesello", "2026-11-22", "11:00", True, source="manual", locked=True)

# Next weekend: 28-29 Nov 2026, 12 matches, 11 on Sunday (two programme pages).
match("n1", "Amatori", "campofelice", "2026-11-28", "20:30", True)
NEXT_SUNDAY = [
    ("Prima Squadra", "castelverde", "14:30", False), ("Juniores", "lucia", "10:30", True),
    ("Allievi U17", "ripalta", "10:00", False), ("Allievi U16", "brolo", "11:00", False),
    ("Giovanissimi U15", "novaria", "09:30", True), ("Giovanissimi U14", "gerolamo", "09:30", False),
    ("Esordienti", "cascina", "11:00", True), ("Pulcini", "valdorso", None, True),
    ("Primi Calci", "pratofiorito", "10:00", False), ("Femminile", "eufrasio", "18:00", False),
    ("Juniores Femminile", "montesello", "16:00", True),
]
for i, (team, opp, time, home) in enumerate(NEXT_SUNDAY, 2):
    extra = {"competition": PC, "rnd": 13} if team == "Prima Squadra" else {}
    match(f"n{i}", team, opp, "2026-11-29", time, home, **extra)

renders = [
    {"id": uid("render", "1"), "templateID": "story-fulltime", "templateVersion": "1.0.0",
     "matchIDs": [uid("match", "p1")], "date": "2026-11-15",
     "file": "2026-11-15/2026-11-15_story-fulltime_prima-squadra_vs_sporting-ripalta-nuova.png",
     "width": 1080, "height": 1920, "warnings": [], "createdAt": "2026-11-15T17:10:00Z"},
    {"id": uid("render", "2"), "templateID": "story-halftime", "templateVersion": "1.0.0",
     "matchIDs": [uid("match", "p1")], "date": "2026-11-15",
     "file": "2026-11-15/2026-11-15_story-halftime_prima-squadra_vs_sporting-ripalta-nuova.png",
     "width": 1080, "height": 1920, "warnings": [], "createdAt": "2026-11-15T15:20:00Z"},
    {"id": uid("render", "3"), "templateID": "post-prematch", "templateVersion": "1.0.0",
     "matchIDs": [uid("match", "p1")], "date": "2026-11-15",
     "file": "2026-11-15/2026-11-15_post-prematch_prima-squadra_vs_sporting-ripalta-nuova.png",
     "width": 1080, "height": 1350, "warnings": [], "createdAt": "2026-11-12T20:00:00Z"},
    {"id": uid("render", "4"), "templateID": "story-programme", "templateVersion": "1.0.0",
     "matchIDs": [uid("match", "p2"), uid("match", "p4")], "date": "2026-11-14", "page": {"index": 1, "total": 1},
     "file": "2026-11-14/2026-11-14_story-programme_1of1.png",
     "width": 1080, "height": 1920, "warnings": ["Manca il campo."], "createdAt": "2026-11-13T19:00:00Z"},
]

dataset = {
    "referenceSaturday": "2026-11-21",
    "settings": SETTINGS,
    "teams": teams,
    "opponents": opponents,
    "matches": matches,
    "renders": renders,
    "missingRenderFileIDs": [uid("render", "4")],
}

# ---------------------------------------------------------------- contexts
CLUB = {"name": SETTINGS["clubName"], "shortName": SETTINGS["clubShortName"], "logo": CLUB_LOGO,
        "accent": SETTINGS["accentColor"], "season": SETTINGS["season"], "handle": SETTINGS["socialHandle"]}
M = {m["id"]: m for m in matches}
TID = {t["id"]: t for t in teams}
OID = {o["id"]: o for o in opponents}


def side_us(m):
    s = {"name": SETTINGS["clubName"], "displayName": SETTINGS["clubShortName"], "logo": CLUB_LOGO,
         "initials": initials(SETTINGS["clubShortName"]), "isUs": True}
    if "score" in m:
        s["score"] = m["score"]["us"]
    if "halfTime" in m:
        s["halfTimeScore"] = m["halfTime"]["us"]
    return s


def side_them(m, limit):
    o = OID[m["opponentID"]]
    s = {"name": o["name"], "displayName": display(o, limit), "initials": initials(o["name"]), "isUs": False}
    if "logoFile" in o:
        s["logo"] = "_logos/" + o["logoFile"]
    if "score" in m:
        s["score"] = m["score"]["them"]
    if "halfTime" in m:
        s["halfTimeScore"] = m["halfTime"]["them"]
    return s


def mctx(m, *, list_row=False, team_limit=16, venue_limit=14, cat_limit=22):
    team = TID[m["teamID"]]
    us, them = side_us(m), side_them(m, team_limit)
    c = {"category": trunc(team["shortLabel"] if list_row else team["name"], cat_limit)[0],
         "dateLong": dlong(m["date"]), "dateShort": dshort(m["date"]),
         "venue": trunc(m["venue"], venue_limit)[0], "isHome": m["isHome"], "isAway": not m["isHome"],
         "home": us if m["isHome"] else them, "away": them if m["isHome"] else us, "us": us, "opponent": them,
         "isPostponed": m["status"] == "postponed", "isCancelled": m["status"] == "cancelled"}
    for k in ("round", "competition", "time", "halfTime", "notes"):
        if k in m:
            c[k] = m[k]
    return c


def single(m, **kw):
    return {"club": CLUB, "match": mctx(m, **kw)}


def order(m):
    return (m["date"], m.get("time") is None, m.get("time") or "", TID[m["teamID"]]["sortOrder"], m["id"])


def lst(ms, title, label, index=1, total=1):
    rows = [mctx(m, list_row=True, team_limit=22, venue_limit=14, cat_limit=16) for m in sorted(ms, key=order)]
    return {"club": CLUB, "title": title, "dateLabel": label, "rows": rows,
            "page": {"index": index, "total": total}, "hasPages": total > 1, "pageLabel": f"{index}/{total}"}


# The standard fixture: first team, home, logo, short name, with scores so result stories show numbers.
standard = dict(M[uid("match", "r5")])
standard.update({"score": {"us": 2, "them": 1}, "halfTime": {"us": 1, "them": 0}, "notes": "Rossi 23', Bianchi 78'"})
files = {
    "single.context.json": single(standard),
    "single-long-name.context.json": single(M[uid("match", "r6")]),
    "single-no-logo.context.json": single(M[uid("match", "r3")]),
    "single-away.context.json": single(M[uid("match", "r2")]),
    "single-no-time.context.json": single(M[uid("match", "r4")]),
}
sunday29 = [m for m in matches if m["date"] == "2026-11-29"]
ten = sorted(sunday29, key=order)[:10]
files["list.context.json"] = lst(ten, "Oggi in campo", dlong("2026-11-29"))
twenty3 = [m for m in matches if m["date"] >= "2026-11-21"] + [M[uid("match", "p2")]]
assert len(twenty3) == 23, len(twenty3)
files["list-23.context.json"] = lst(twenty3, "Weekend in campo", "Dal 14 al 29 novembre")
assert len(files["list.context.json"]["rows"]) == 10
files["matches.json"] = dataset

for name, content in files.items():
    with open(os.path.join(OUT, name), "w", encoding="utf-8") as fh:
        json.dump(content, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
print("wrote", len(files), "files;", len(matches), "matches,", len(opponents), "opponents")
print("logos:", " ".join(o["logoFile"] for o in opponents if "logoFile" in o))
