#!/usr/bin/env python3
"""Install a per-user macOS updater with an explicit source and brain binding."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

LABEL = 'com.borrowedfire.fleet-sync'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--brain', required=True, type=Path)
    parser.add_argument('--openclaw-workspace', type=Path)
    parser.add_argument('--interval', type=int, default=900)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    if args.interval < 60:
        parser.error('interval must be at least 60 seconds')
    source, brain = args.source.resolve(), args.brain.resolve()
    for repo in (source, brain):
        top = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', '--show-toplevel'], text=True).strip()
        if Path(top).resolve() != repo:
            parser.error('source and brain must be exact Git roots')
    if not (source / 'tools/sync-fleet.py').is_file():
        parser.error('source does not contain sync-fleet.py')
    home = Path.home()
    state = home / '.local/share/borrowedfire-sync'
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    harnesses = []
    for root, context in [(home / '.claude', 'CLAUDE.md'),
                          (Path(os.environ.get('CODEX_HOME', home / '.codex')), 'AGENTS.md'),
                          (home / '.qwen', 'QWEN.md')]:
        if root.is_dir():
            harnesses.append({'skills': str(root / 'skills'), 'context': str(root / context)})
    if args.openclaw_workspace:
        workspace = args.openclaw_workspace.resolve()
        if not workspace.is_dir():
            parser.error('OpenClaw workspace does not exist')
        harnesses.append({'skills': str(workspace / 'skills'), 'context': str(workspace / 'AGENTS.md')})
    if not harnesses:
        parser.error('no installed harnesses found')
    config = {'source': str(source), 'brain': str(brain), 'harnesses': harnesses}
    if args.openclaw_workspace:
        config['copy'] = True
        config['openclaw_workspace'] = str(workspace)
    config_path = state / 'config.json'
    if config_path.exists():
        try:
            previous = json.loads(config_path.read_text())
            if not isinstance(previous, dict):
                raise ValueError('config must be an object')
        except (OSError, ValueError) as exc:
            parser.error('existing updater config is unreadable: ' + str(exc))
        for key in ('private_context', 'private_context_targets', 'git_identity_policy'):
            if key in previous:
                config[key] = previous[key]
    config_path.write_text(json.dumps(config, indent=2) + '\n')
    config_path.chmod(0o600)
    agents = home / 'Library/LaunchAgents'
    agents.mkdir(parents=True, exist_ok=True)
    plist_path = agents / (LABEL + '.plist')
    plist = {'Label': LABEL, 'ProgramArguments': [sys.executable, str(source / 'tools/sync-fleet.py'),
                                               '--config', str(config_path)],
             'RunAtLoad': True, 'StartInterval': args.interval,
             'EnvironmentVariables': {'PATH': '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin',
                                      **({'CODEX_HOME': os.environ['CODEX_HOME']} if 'CODEX_HOME' in os.environ else {})},
             'StandardOutPath': str(state / 'launchd.log'), 'StandardErrorPath': str(state / 'launchd-error.log')}
    plist_path.write_bytes(plistlib.dumps(plist))
    plist_path.chmod(0o600)
    if not args.prepare_only:
        domain = 'gui/' + str(os.getuid())
        subprocess.run(['launchctl', 'bootout', domain + '/' + LABEL], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['launchctl', 'bootstrap', domain, str(plist_path)], check=True)
        subprocess.run(['launchctl', 'print', domain + '/' + LABEL], check=True, stdout=subprocess.DEVNULL)
    print(json.dumps({'config': str(config_path), 'launch_agent': str(plist_path), 'loaded': not args.prepare_only}))

if __name__ == '__main__':
    main()
