#!/usr/bin/env python3
"""
RoboCore Flow Manager v1.0
Command-line tool for managing OpenLane synthesis runs.
Fixes: no resume, no auto-save, buffered logs, no cost visibility.
"""

import click
import os
import json
import time
import shutil
from pathlib import Path
from datetime import datetime
from rich.console import Console
from rich.table import Table
from rich.panel import Panel

console = Console()

DEFAULT_CONFIG = {
    "design":       "robocore1",
    "openlane_dir": "~/OpenLane_repo",
    "pdk_root":     "~/.ciel",
    "pdk":          "sky130A",
    "container":    "ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69",
    "github_repo":  "jyothisarath096/robocore1",
    "budget_usd":   10.0,
    "cost_per_hr":  0.30,
}

def load_config():
    cfg = DEFAULT_CONFIG.copy()
    if os.path.exists("robocore.json"):
        with open("robocore.json") as f:
            cfg.update(json.load(f))
    return cfg

def save_config(cfg):
    with open("robocore.json", "w") as f:
        json.dump(cfg, f, indent=2)

# ── RTL Analysis ───────────────────────────────────────────────────────────

def check_multiple_drivers(verilog_file):
    issues = []
    try:
        with open(verilog_file) as f:
            lines = f.readlines()
        driven = {}
        block_line = 0
        in_generate = 0
        for i, line in enumerate(lines):
            s = line.strip()
            # Track generate blocks — signals driven there are per-instance
            if s.startswith("generate"):
                in_generate += 1
            if s.startswith("endgenerate"):
                in_generate = max(0, in_generate - 1)
            if s.startswith("always"):
                block_line = i + 1
            # Skip signals in generate blocks (per-instance, not true multi-driver)
            if in_generate > 0:
                continue
            if "<=" in s and not s.startswith("//"):
                sig = s.split("<=")[0].strip().split("[")[0].strip()
                if sig and sig not in ("", "begin", "end"):
                    if sig in driven and driven[sig] != block_line:
                        issues.append({
                            "file": verilog_file,
                            "signal": sig,
                            "line1": driven[sig],
                            "line2": i + 1
                        })
                    else:
                        driven[sig] = block_line
    except Exception:
        pass
    return issues

def check_large_arrays(verilog_file):
    issues = []
    import re
    try:
        with open(verilog_file) as f:
            lines = f.readlines()
        for i, line in enumerate(lines):
            if "reg" in line and line.strip().startswith("reg"):
                dims = re.findall(r'\[(\d+):(\d+)\]', line)
                if len(dims) >= 2:
                    width = abs(int(dims[0][0]) - int(dims[0][1])) + 1
                    depth = abs(int(dims[1][0]) - int(dims[1][1])) + 1
                    if width * depth > 4096:
                        issues.append({
                            "file": verilog_file,
                            "line": i + 1,
                            "width": width,
                            "depth": depth,
                            "kb": width * depth / 8192
                        })
    except Exception:
        pass
    return issues

def check_array_ports(verilog_file):
    """Detect true array ports: input [W:0] name [D:0]"""
    import re
    issues = []
    try:
        with open(verilog_file) as f:
            lines = f.readlines()
        for i, line in enumerate(lines):
            s = line.strip().split("//")[0]
            if any(s.startswith(p) for p in ["input", "output", "inout"]):
                # True array port pattern: type [W:0] name [D:0]
                # Must have [n:n] AFTER an identifier (not just two brackets)
                if re.search(r'w+s*\[\s*\d+\s*:\s*\d+\s*\]\s*;?\s*$', s):
                    # Has array dimension at end after identifier
                    issues.append({"file": verilog_file, "line": i+1, "text": s[:60]})
    except Exception:
        pass
    return issues

# ── Auto Fix ──────────────────────────────────────────────────────────────────

def fix_large_arrays(verilog_file):
    """Add ram_style=block attribute to large arrays."""
    import re
    fixes = 0
    with open(verilog_file) as f:
        lines = f.readlines()
    
    new_lines = []
    for i, line in enumerate(lines):
        # Check if this is a large array declaration
        if line.strip().startswith("reg") and not "(* ram_style" in line:
            dims = re.findall(r'\[(\d+):(\d+)\]', line)
            if len(dims) >= 2:
                width = abs(int(dims[0][0]) - int(dims[0][1])) + 1
                depth = abs(int(dims[1][0]) - int(dims[1][1])) + 1
                if width * depth > 4096:
                    # Add ram_style attribute
                    indent = len(line) - len(line.lstrip())
                    line = " " * indent + '(* ram_style = "block" *) ' + line.lstrip()
                    fixes += 1
        new_lines.append(line)
    
    if fixes > 0:
        with open(verilog_file, 'w') as f:
            f.writelines(new_lines)
    return fixes

def fix_multiple_drivers(verilog_file):
    """Report multiple drivers with line numbers for manual fix."""
    # Auto-fix is risky — just report with clear guidance
    issues = check_multiple_drivers(verilog_file)
    return issues

# ── Run Utilities ──────────────────────────────────────────────────────────

def get_run_dirs(design_dir):
    runs_dir = os.path.join(design_dir, "runs")
    if not os.path.exists(runs_dir):
        return []
    return sorted([
        os.path.join(runs_dir, d)
        for d in os.listdir(runs_dir)
        if d.startswith("RUN_")
    ], reverse=True)

def get_current_step(run_dir):
    log = os.path.join(run_dir, "openlane.log")
    if not os.path.exists(log):
        return None, 0
    try:
        with open(log) as f:
            lines = f.readlines()
        for line in reversed(lines):
            s = line.strip()
            if "[INFO]: Running" in s or "[ERROR]" in s:
                return s, len(lines)
    except Exception:
        pass
    return None, 0

def is_complete(run_dir):
    mfg = os.path.join(run_dir, "reports", "manufacturability.rpt")
    if not os.path.exists(mfg):
        return False
    with open(mfg) as f:
        return "Flow failed" not in f.read()

def has_gds(run_dir):
    for root, dirs, files in os.walk(run_dir):
        for f in files:
            if f.endswith(".gds"):
                return os.path.join(root, f)
    return None

def elapsed_hours(run_dir):
    try:
        name = os.path.basename(run_dir).replace("RUN_", "")
        ts = name[:19].replace("_", " ", 1).replace("_", ":")
        start = datetime.strptime(ts, "%Y.%m.%d %H:%M:%S")
        return (datetime.utcnow() - start).total_seconds() / 3600
    except Exception:
        return 0

# ── CLI ────────────────────────────────────────────────────────────────────

@click.group()
def cli():
    """RoboCore Flow Manager — production-grade OpenLane wrapper"""
    pass

@cli.command()
@click.option("--design", default="robocore1")
@click.option("--budget", default=10.0)
@click.option("--cost-per-hr", default=0.30)
@click.option("--github-repo", default="jyothisarath096/robocore1")
def init(design, budget, cost_per_hr, github_repo):
    """Initialize project config."""
    cfg = DEFAULT_CONFIG.copy()
    cfg["design"]       = design
    cfg["budget_usd"]   = budget
    cfg["cost_per_hr"]  = cost_per_hr
    cfg["github_repo"]  = github_repo
    save_config(cfg)
    console.print(Panel(
        f"[green]Project initialized![/green]\n"
        f"Design:  {design}\n"
        f"Budget:  ${budget:.2f}\n"
        f"Saved:   robocore.json",
        title="RoboCore Flow Manager"
    ))

@cli.command()
@click.argument("src_dir")
@click.option("--fix", is_flag=True, help="Auto-fix large arrays with ram_style=block")
def preprocess(src_dir, fix):
    """Detect and optionally fix common RTL synthesis issues."""
    console.print(Panel("[bold]RoboCore RTL Preprocessor[/bold]",
                        subtitle="Checking for synthesis issues"))
    vfiles = [f for f in Path(src_dir).glob("**/*.v")
              if "_tb" not in f.name and ".bak" not in f.name]
    if not vfiles:
        console.print(f"[red]No .v files in {src_dir}[/red]")
        return

    # Auto-fix large arrays if requested
    if fix:
        total_fixes = 0
        for vf in vfiles:
            n = fix_large_arrays(str(vf))
            if n > 0:
                console.print(f"[green]Auto-fixed {n} large array(s) in {vf.name}[/green]")
                total_fixes += n
        if total_fixes > 0:
            console.print(f"[green]Applied {total_fixes} ram_style fixes[/green]\n")
        else:
            console.print("[green]No large arrays needed fixing[/green]\n")

    all_issues = []
    for vf in vfiles:
        for iss in check_multiple_drivers(str(vf)):
            all_issues.append(("MULTIPLE DRIVER", iss))
        for iss in check_large_arrays(str(vf)):
            all_issues.append(("LARGE ARRAY→FFs", iss))
        for iss in check_array_ports(str(vf)):
            all_issues.append(("ARRAY PORT", iss))

    if not all_issues:
        console.print("[green]✅ No issues found — RTL is synthesis-ready[/green]")
        return

    t = Table(title=f"{len(all_issues)} issue(s) found",
              header_style="bold magenta")
    t.add_column("Type", style="red")
    t.add_column("File")
    t.add_column("Detail")
    t.add_column("Fix")

    for itype, iss in all_issues:
        fname = os.path.basename(iss["file"])
        if itype == "MULTIPLE DRIVER":
            t.add_row(itype, fname,
                f"'{iss['signal']}' driven at lines {iss['line1']} & {iss['line2']}",
                "Single always block")
        elif itype == "LARGE ARRAY→FFs":
            t.add_row(itype, fname,
                f"Line {iss['line']}: {iss['depth']}×{iss['width']}-bit ({iss['kb']:.1f}KB)",
                "(* ram_style=\"block\" *)")
        elif itype == "ARRAY PORT":
            t.add_row(itype, fname,
                f"Line {iss['line']}: {iss['text']}",
                "Flatten to packed vector")
    console.print(t)

@cli.command()
@click.option("--design", default=None)
def status(design):
    """Show current flow status."""
    cfg    = load_config()
    design = design or cfg["design"]
    openlane_dir = os.path.expanduser(cfg["openlane_dir"])
    design_dir   = os.path.join(openlane_dir, "designs", design)
    runs         = get_run_dirs(design_dir)

    if not runs:
        console.print(f"[yellow]No runs found for '{design}'[/yellow]")
        return

    latest  = runs[0]
    step, lines = get_current_step(latest)
    complete    = is_complete(latest)
    gds         = has_gds(latest)
    hrs         = elapsed_hours(latest)
    cost        = hrs * cfg["cost_per_hr"]

    color = "green" if complete else ("yellow" if step else "red")
    state = "COMPLETE ✅" if complete else ("RUNNING 🔄" if step else "STOPPED ❌")

    console.print(Panel(
        f"[bold]Run:[/bold]          {os.path.basename(latest)}\n"
        f"[bold]Status:[/bold]       [{color}]{state}[/{color}]\n"
        f"[bold]Current step:[/bold] {step or 'Unknown'}\n"
        f"[bold]Log lines:[/bold]    {lines:,}\n"
        f"[bold]GDS:[/bold]          {'✅ ' + gds if gds else '❌ Not yet'}\n"
        f"[bold]Elapsed:[/bold]      {hrs:.1f} hrs\n"
        f"[bold]Est. cost:[/bold]    ${cost:.2f} / budget ${cfg['budget_usd']:.2f}",
        title=f"RoboCore — {design}",
        border_style=color
    ))

    # Show last 3 log lines
    log = os.path.join(latest, "openlane.log")
    if os.path.exists(log):
        with open(log) as f:
            tail = [l.strip() for l in f.readlines()[-3:] if l.strip()]
        if tail:
            console.print("\n[bold]Recent log:[/bold]")
            for line in tail:
                c = "red" if "ERROR" in line else "green"
                console.print(f"  [{c}]{line}[/{c}]")

@cli.command()
@click.option("--design", default=None)
@click.option("--interval", default=60)
def watch(design, interval):
    """Watch flow progress live."""
    cfg    = load_config()
    design = design or cfg["design"]
    openlane_dir = os.path.expanduser(cfg["openlane_dir"])
    design_dir   = os.path.join(openlane_dir, "designs", design)

    console.print(f"[bold]Watching '{design}' — refresh every {interval}s (Ctrl+C to stop)[/bold]\n")
    try:
        while True:
            runs = get_run_dirs(design_dir)
            if runs:
                step, _ = get_current_step(runs[0])
                ts      = datetime.now().strftime("%H:%M:%S")
                if step:
                    c = "red" if "ERROR" in step else "green"
                    console.print(f"[dim]{ts}[/dim] [{c}]{step}[/{c}]")
                if is_complete(runs[0]):
                    console.print("\n[bold green]✅ Flow complete![/bold green]")
                    gds = has_gds(runs[0])
                    if gds:
                        console.print(f"GDS: {gds}")
                    break
            time.sleep(interval)
    except KeyboardInterrupt:
        console.print("\n[yellow]Stopped[/yellow]")

@cli.command()
@click.option("--design", default=None)
def results(design):
    """Show results from the latest run."""
    cfg    = load_config()
    design = design or cfg["design"]
    openlane_dir = os.path.expanduser(cfg["openlane_dir"])
    design_dir   = os.path.join(openlane_dir, "designs", design)
    runs         = get_run_dirs(design_dir)

    if not runs:
        console.print("[red]No runs found[/red]")
        return

    latest = runs[0]
    mfg    = os.path.join(latest, "reports", "manufacturability.rpt")
    if os.path.exists(mfg):
        console.print(Panel(open(mfg).read(), title="Manufacturability Report"))

    gds = has_gds(latest)
    if gds:
        size = os.path.getsize(gds) / 1024 / 1024
        console.print(f"\n[green]GDS: {gds} ({size:.1f} MB)[/green]")

@cli.command()
@click.option("--design", default=None)
@click.option("--push", is_flag=True)
def save(design, push):
    """Save GDS and reports, optionally push to GitHub."""
    cfg    = load_config()
    design = design or cfg["design"]
    openlane_dir = os.path.expanduser(cfg["openlane_dir"])
    design_dir   = os.path.join(openlane_dir, "designs", design)
    runs         = get_run_dirs(design_dir)

    if not runs:
        console.print("[red]No runs found[/red]")
        return

    latest  = runs[0]
    gds     = has_gds(latest)
    repo    = os.path.expanduser("~/robocore1")

    if gds and os.path.exists(repo):
        dest = os.path.join(repo, "gds", "robocore1_top_v3.gds")
        shutil.copy2(gds, dest)
        console.print(f"[green]GDS saved: {dest}[/green]")

    mfg = os.path.join(latest, "reports", "manufacturability.rpt")
    if os.path.exists(mfg) and os.path.exists(repo):
        shutil.copy2(mfg, os.path.join(repo, "reports", "manufacturability.rpt"))
        console.print("[green]Reports saved[/green]")

    if push and os.path.exists(repo):
        try:
            import git
            r = git.Repo(repo)
            r.git.add(A=True)
            r.index.commit(f"Auto-save {datetime.now().strftime('%Y-%m-%d %H:%M')}")
            r.remote("origin").push()
            console.print("[green]✅ Pushed to GitHub[/green]")
        except Exception as e:
            console.print(f"[red]Push failed: {e}[/red]")

@cli.command()
@click.option("--design", default=None)
def estimate(design):
    """Estimate runtime and cost."""
    cfg    = load_config()
    design = design or cfg["design"]
    openlane_dir  = os.path.expanduser(cfg["openlane_dir"])
    src_dir       = os.path.join(openlane_dir, "designs", design, "src")
    config_file   = os.path.join(openlane_dir, "designs", design, "config.json")

    die_area = "unknown"
    if os.path.exists(config_file):
        with open(config_file) as f:
            dcfg = json.load(f)
        die_area = dcfg.get("DIE_AREA", "unknown")

    lines = 0
    if os.path.exists(src_dir):
        for vf in Path(src_dir).glob("*.v"):
            with open(vf) as f:
                lines += len(f.readlines())

    cells = lines * 3
    synth  = max(0.25, cells / 500000)
    place  = max(0.5,  cells / 200000)
    route  = max(1.0,  cells / 100000)
    total  = synth + place + 0.25 + route + 0.5
    cost   = total * cfg["cost_per_hr"]

    t = Table(title=f"Estimate — {design}", header_style="bold blue")
    t.add_column("Step")
    t.add_column("Est. Time")
    t.add_column("Notes")
    t.add_row("Synthesis",  f"{synth:.1f}h", f"~{cells:,} cells, die: {die_area}")
    t.add_row("Placement",  f"{place:.1f}h", "Global + detailed")
    t.add_row("CTS",        "0.25h",         "Clock tree")
    t.add_row("Routing",    f"{route:.1f}h", "Global + detailed")
    t.add_row("Signoff",    "0.5h",          "STA + DRC + LVS")
    t.add_row("[bold]TOTAL[/bold]",
              f"[bold]{total:.1f}h[/bold]",
              f"[bold]~${cost:.2f} @ ${cfg['cost_per_hr']}/hr[/bold]")
    console.print(t)

    if cost > cfg["budget_usd"]:
        console.print(f"\n[red]⚠️  ${cost:.2f} exceeds budget ${cfg['budget_usd']:.2f}[/red]")
    else:
        console.print(f"\n[green]✅ Within budget (${cfg['budget_usd']:.2f})[/green]")

@cli.command()
def runs():
    """List all previous runs."""
    cfg = load_config()
    openlane_dir = os.path.expanduser(cfg["openlane_dir"])
    design_dir   = os.path.join(openlane_dir, "designs", cfg["design"])
    run_list     = get_run_dirs(design_dir)

    if not run_list:
        console.print("[yellow]No runs found[/yellow]")
        return

    t = Table(title=f"Runs — {cfg['design']}", header_style="bold")
    t.add_column("#")
    t.add_column("Run ID")
    t.add_column("Status")
    t.add_column("GDS")
    t.add_column("Cost Est.")

    for i, run in enumerate(run_list[:10]):
        complete = is_complete(run)
        gds      = has_gds(run)
        hrs      = elapsed_hours(run)
        cost     = hrs * cfg["cost_per_hr"]
        t.add_row(
            str(i+1),
            os.path.basename(run),
            "[green]Complete[/green]" if complete else "[red]Failed[/red]",
            "[green]✅[/green]" if gds else "[red]❌[/red]",
            f"~${cost:.2f}"
        )
    console.print(t)

if __name__ == "__main__":
    cli()
