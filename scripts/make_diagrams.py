"""Generates docs/assets/*.svg with one shared style.

Usage: python3 scripts/make_diagrams.py docs/assets
"""
import os, sys
from xml.sax.saxutils import escape as esc

OUT = sys.argv[1]
STYLE = """<style>
  .bg{fill:none}
  .t{font-family:system-ui,-apple-system,"Segoe UI",Helvetica,Arial,sans-serif;fill:#1f2328}
  .h{font-size:20px;font-weight:700}
  .b{font-size:15px;font-weight:650}
  .s{font-size:12.5px;fill:#59636e}
  .m{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12px;fill:#59636e}
  .box{fill:#f6f8fa;stroke:#d0d7de;stroke-width:1.5}
  .acc{fill:#ddf4ff;stroke:#0969da;stroke-width:1.8}
  .gate{fill:#ffebe9;stroke:#cf222e;stroke-width:1.8}
  .ok{fill:#dafbe1;stroke:#1a7f37;stroke-width:1.5}
  .ln{stroke:#59636e;stroke-width:1.6;fill:none}
  .lg{stroke:#cf222e;stroke-width:1.6;fill:none;stroke-dasharray:5 4}
  .ah{fill:#59636e}.ahg{fill:#cf222e}
  @media (prefers-color-scheme: dark){
    .t{fill:#e6edf3}.s,.m{fill:#9198a1}
    .box{fill:#161b22;stroke:#3d444d}
    .acc{fill:#0c2d6b;stroke:#4493f8}
    .gate{fill:#3c1618;stroke:#f85149}
    .ok{fill:#0f2d1a;stroke:#3fb950}
    .ln{stroke:#9198a1}.ah{fill:#9198a1}
    .lg{stroke:#f85149}.ahg{fill:#f85149}
  }
</style>"""
DEFS = """<defs>
  <marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path class="ah" d="M0,0 L10,5 L0,10 z"/></marker>
  <marker id="g" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path class="ahg" d="M0,0 L10,5 L0,10 z"/></marker>
</defs>"""

def svg(name, w, h, title, desc, body):
    s = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-labelledby="title desc">\n'
         f'<title id="title">{esc(title)}</title>\n<desc id="desc">{esc(desc)}</desc>\n{STYLE}\n{DEFS}\n'
         + "\n".join(body) + "\n</svg>\n")
    open(os.path.join(OUT, name), "w", encoding="utf-8").write(s)

def text(x, y, s, cls="s", anchor="middle"):
    # SVG collapses leading spaces; turn indentation into an x offset instead.
    n = len(s) - len(s.lstrip(" "))
    if n and anchor == "start":
        x += n * 7.2
        s = s.lstrip(" ")
    return f'<text class="t {cls}" x="{x}" y="{y}" text-anchor="{anchor}">{esc(s)}</text>'

def box(x, y, w, h, cls="box", r=10):
    return f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}"/>'

def card(x, y, w, h, title, lines, cls="box", mono=()):
    out = [box(x, y, w, h, cls), text(x + w / 2, y + 26, title, "b")]
    for i, l in enumerate(lines):
        out.append(text(x + w / 2, y + 48 + i * 18, l, "m" if i in mono else "s"))
    return out

def arrow(x1, y1, x2, y2, cls="ln", m="a"):
    return f'<path class="{cls}" d="M{x1},{y1} L{x2},{y2}" marker-end="url(#{m})"/>'

def path(d, cls="ln", m="a"):
    return f'<path class="{cls}" d="{d}" marker-end="url(#{m})"/>'

# 1. five phases ---------------------------------------------------------
b = [text(480, 34, "Five phases, one approval gate", "h")]
xs = [20, 210, 400, 590, 780]; y = 110; w = 160; h = 126
phases = [
    ("1  Read", ["AGENTS.md, MAP.md,", "HARNESS.md, then code", "MAP.md missing: draft it", "from the real code"], "box"),
    ("2  Write brief", ["TASK.md, 7 sections", "plain language", "(ASD-STE100)", "then STOP"], "acc"),
    ("3  Confirm", ["nothing moves until", "you say go", "approve", "or keep refining"], "gate"),
    ("4  Build", ["only files listed", "in TASK.md section 2", "no tests, no harness", "while building"], "box"),
    ("5  Close out", ["one run: section 7", "+ every registered", "harness, real data", "no fake mocks"], "acc"),
]
for x, (t, lines, cls) in zip(xs, phases):
    b += card(x, y, w, h, t, lines, cls)
for i in range(4):
    b.append(arrow(xs[i] + w, y + h / 2, xs[i + 1] - 4, y + h / 2, "lg" if i == 2 else "ln", "g" if i == 2 else "a"))
b.append(path(f"M{xs[2]+w/2},{y} C{xs[2]+w/2},{y-44} {xs[1]+w/2},{y-44} {xs[1]+w/2},{y-4}", "lg", "g"))
b.append(text((xs[1] + xs[2]) / 2 + w / 2, y - 40, "keep refining: feedback goes back to the brief"))
oy = 305
outs = [("HARNESS.md", "add loops worth keeping", "ok"), ("MAP.md", "decisions that will recur", "ok"), ("TASK.md", "deleted, never archived", "box")]
ox = [470, 640, 810]
for x, (t, s, cls) in zip(ox, outs):
    b += [box(x, oy, 150, 64, cls), text(x + 75, oy + 25, t, "b"), text(x + 75, oy + 46, s)]
    b.append(path(f"M{xs[4]+w/2},{y+h} C{xs[4]+w/2},{oy-30} {x+75},{oy-40} {x+75},{oy-4}"))
b.append(text(460, oy + 25, "Write-backs are proposed with the before", "s", "end"))
b.append(text(460, oy + 43, "and after sentence. Written only if you agree;", "s", "end"))
b.append(text(460, oy + 61, "a \u201cno\u201d is final and never asked twice.", "s", "end"))
svg("workflow-phases.svg", 960, 395, "code-project-flow: five phases",
    "Read, write the task brief, confirm, build, close out. The confirm step is the only gate; close-out proposes write-backs to HARNESS.md and MAP.md and deletes TASK.md.", b)

# 2. components and install targets -----------------------------------------
b = [text(480, 34, "One repository, two components, one installer", "h")]
b += [box(20, 70, 260, 250), text(150, 98, "Repository", "b")]
for i, l in enumerate(["SKILL.md", "references/  (4 templates)", "dsh/preset/quick-dev.patch.yml", "dsh/plugin/quick-dev-plan-arm.mjs", "install.sh  install.ps1", "VERSION  LICENSE"]):
    b.append(text(38, 130 + i * 28, l, "m", "start"))
b += card(318, 140, 200, 110, "Installer", ["install.sh  /  install.ps1", "--components skill,dsh", "--dry-run  --uninstall", "--migrate-legacy"], "acc", mono=(0, 1, 2, 3))
b.append(arrow(280, 195, 314, 195))
# skill target
b += [box(550, 60, 390, 130, "box"), text(745, 86, "skill  \u2192  any SKILL.md client (default: Qoder)", "b")]
for i, l in enumerate(["~/.qoder-cn/skills/code-project-flow/", "  or ~/.qoder/skills/\u2026, or --skills-dir DIR", "SKILL.md  references/  LICENSE  .cpf-manifest", "documents in the project: docs/MAP.md \u2026"]):
    b.append(text(568, 110 + i * 20, l, "m", "start"))
b += [box(550, 210, 390, 150, "box"), text(745, 236, "dsh  \u2192  DSH quick dev mode", "b")]
for i, l in enumerate(["$DSH_HOME (default ~/.dsh)/", "  skills/code-project-flow/   root layout", "  plugins/quick-dev-plan-arm.mjs", "  profiles/*/cordis.patch.yml", "      + one preset-quick-dev block", "documents in the project root: MAP.md \u2026"]):
    b.append(text(568, 260 + i * 18, l, "m", "start"))
b.append(path("M518,180 C535,180 530,125 546,125"))
b.append(path("M518,215 C535,215 530,285 546,285"))
b += [box(20, 385, 920, 60, "gate"),
      text(480, 410, "Upgrades: an install without .cpf-manifest (from the former installers) is never overwritten.", "s"),
      text(480, 430, "It is skipped (exit 3) or, with --migrate-legacy, moved to ~/.code-project-flow-backups/<time>/. Nothing is deleted.", "s")]
svg("install-components.svg", 960, 460, "code-project-flow: components and install targets",
    "The installer copies the skill into a skills folder and, for DSH, also installs the plan-arm plugin and a preset block in every profile patch layer.", b)

# 3. four documents ----------------------------------------------------------
b = [text(480, 34, "Four documents: decisions on disk, not in chat", "h")]
docs = [
    ("Doc 1  AGENTS.md", "rules", ["written by you only", "4 overriding principles", "who owns what"], "AGENTS.md", "AGENTS.md", "gate"),
    ("Doc 2  MAP.md", "design", ["agent proposes, you approve", "features, structure,", "user flow, data flow"], "docs/MAP.md", "MAP.md", "box"),
    ("Doc 3  HARNESS.md", "regression loops", ["agent proposes, you approve", "registered loops only,", "code lives in harness/"], "docs/HARNESS.md", "HARNESS.md", "box"),
    ("Doc 4  TASK.md", "this round only", ["agent writes, you confirm", "7 sections, down to", "functions and paths"], "docs/TASK.md", "TASK.md", "acc"),
]
for i, (t, sub, lines, p1, p2, cls) in enumerate(docs):
    x = 20 + i * 235
    b += [box(x, 60, 215, 210, cls), text(x + 107, 88, t, "b"), text(x + 107, 108, sub)]
    for j, l in enumerate(lines):
        b.append(text(x + 107, 136 + j * 19, l))
    b += [text(x + 14, 222, "skill:", "s", "start"), text(x + 60, 222, p1, "m", "start"),
          text(x + 14, 244, "DSH:", "s", "start"), text(x + 60, 244, p2, "m", "start")]
b.append(path("M20,300 L 700,300"))
b.append(text(360, 322, "a new session reads Docs 1, 2, 3 (DSH auto-loads them from the project root)"))
b.append(text(842, 300, "deleted at close-out", "s"))
b.append(text(842, 322, "its existence = round in progress", "s"))
svg("four-documents.svg", 960, 350, "code-project-flow: the four documents",
    "AGENTS.md holds the rules, MAP.md the design, HARNESS.md the registered regression loops, TASK.md the current round. Paths differ between the skill layout (docs/) and the DSH layout (project root).", b)

# 4. DSH plan-arm plugin -----------------------------------------------------
b = [text(480, 34, "DSH quick dev mode: when the plugin opens plan mode", "h")]
b += card(20, 80, 190, 76, "Session event", ["agent/created, and", "agent/pre-step (re-arm)"], "box")
b += card(260, 80, 190, 76, "Subagent?", ["header.origin ==", "\u201csubagent\u201d"], "box")
b += card(500, 80, 210, 76, "Plan due?", ["AGENTS.md in cwd", "and no TASK.md"], "acc")
b += card(760, 80, 180, 76, "Arm plan mode", ["planMode.set(agent, true)", "never auto-approves"], "gate")
b.append(arrow(210, 118, 256, 118)); b.append(arrow(450, 118, 496, 118)); b.append(arrow(710, 118, 756, 118, "lg", "g"))
b.append(text(475, 108, "no")); b.append(text(733, 108, "yes"))
b += [box(260, 200, 190, 50, "ok"), text(355, 230, "skip, never arm", "b")]
b.append(arrow(355, 156, 355, 196)); b.append(text(370, 182, "yes", "s", "start"))
b += [box(500, 200, 210, 50, "ok"), text(605, 230, "do nothing", "b")]
b.append(arrow(605, 156, 605, 196)); b.append(text(620, 182, "no", "s", "start"))
b += [box(20, 280, 920, 84, "box"),
      text(480, 306, "Re-arm only after a round ends: the plugin saw TASK.md, it is now gone, AGENTS.md is still there, and plan mode is off.", "s"),
      text(480, 328, "It reads two file paths and flips plan mode on. It adds no tools, blocks no tool call, and errors only log a warning,", "s"),
      text(480, 348, "so a failure can never stop a session from opening. You still approve or refine every plan yourself.", "s")]
svg("dsh-plan-arm.svg", 960, 380, "code-project-flow: DSH plan-arm plugin",
    "On session creation the plugin arms plan mode for root agents when AGENTS.md exists and TASK.md does not. Subagents are skipped. It re-arms after a round's TASK.md disappears.", b)
print("ok")
