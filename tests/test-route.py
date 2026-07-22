#!/usr/bin/env python3
from __future__ import annotations

import importlib.machinery
import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
LOADER = importlib.machinery.SourceFileLoader("bf_route", str(ROOT / "tools" / "bf-route"))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[LOADER.name] = MODULE
LOADER.exec_module(MODULE)


class ClassificationTests(unittest.TestCase):
    def test_routine_work_uses_volume(self):
        decision = MODULE.classify("Update these documentation headings")
        self.assertEqual(decision.tier, "local-volume")
        self.assertFalse(decision.owner_gated)

    def test_complex_work_uses_quality(self):
        decision = MODULE.classify("Investigate the root cause of this flaky concurrency bug")
        self.assertEqual(decision.tier, "local-quality")

    def test_review_uses_codex_judgment(self):
        decision = MODULE.classify("Perform the final independent review")
        self.assertEqual(decision.tier, "judgment")

    def test_owner_gate_wins_over_complexity(self):
        decision = MODULE.classify("Debug the authentication session migration")
        self.assertEqual(decision.tier, "judgment")
        self.assertTrue(decision.owner_gated)

    def test_migration_file_is_owner_gated(self):
        decision = MODULE.classify("Fix the typo", ["supabase/migrations/20260722.sql"])
        self.assertEqual(decision.tier, "judgment")
        self.assertTrue(decision.owner_gated)

    def test_review_session_is_judgment_but_not_owner_gated(self):
        decision = MODULE.classify("Start a full review session")
        self.assertEqual(decision.tier, "judgment")
        self.assertFalse(decision.owner_gated)

    def test_no_claude_route_exists(self):
        outcomes = {
            MODULE.classify("Edit docs").tier,
            MODULE.classify("Investigate root cause").tier,
            MODULE.classify("Final independent review").tier,
        }
        self.assertEqual(outcomes, {"local-volume", "local-quality", "judgment"})
        self.assertNotIn("claude", outcomes)


class FleetParsingTests(unittest.TestCase):
    def test_reads_private_tiers(self):
        content = """
| Tier | Endpoint / harness | Use for |
|---|---|---|
| local-quality | `http://host:8000/v1` (`quality-model`, 131072 context) | hard work |
| local-volume | `http://host:8001/v1` (`volume-model`, 131072 context) | routine work |
"""
        with tempfile.TemporaryDirectory() as directory:
            fleet = pathlib.Path(directory) / "fleet.md"
            fleet.write_text(content, encoding="utf-8")
            tiers = MODULE.load_tiers(fleet)
        self.assertEqual(tiers["local-quality"].model, "quality-model")
        self.assertEqual(tiers["local-volume"].endpoint, "http://host:8001/v1")

    def test_shipped_template_matches_router_schema(self):
        template = ROOT / "prometheus-template" / "config" / "fleet.md"
        with self.assertRaisesRegex(RuntimeError, "template placeholders"):
            MODULE.load_tiers(template)
        self.assertIn("Controller SSH host", template.read_text(encoding="utf-8"))

    def test_reads_worker_host(self):
        content = "- Controller SSH host: `worker-alias`\n"
        with tempfile.TemporaryDirectory() as directory:
            fleet = pathlib.Path(directory) / "fleet.md"
            fleet.write_text(content, encoding="utf-8")
            self.assertEqual(MODULE.load_worker_host(fleet), "worker-alias")


class ApplySafetyTests(unittest.TestCase):
    def make_repo(self, directory):
        repo = pathlib.Path(directory)
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        subprocess.run(["git", "-C", str(repo), "config", "user.name", "Test"], check=True)
        subprocess.run(["git", "-C", str(repo), "config", "user.email", "test@invalid"], check=True)
        (repo / "value.txt").write_text("BEFORE\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(repo), "add", "value.txt"], check=True)
        subprocess.run(["git", "-C", str(repo), "commit", "-qm", "baseline"], check=True)
        commit = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "HEAD"], check=True, text=True, stdout=subprocess.PIPE
        ).stdout.strip()
        return repo, commit

    def test_clean_exact_checkout_accepts_patch(self):
        with tempfile.TemporaryDirectory() as directory:
            repo, commit = self.make_repo(directory)
            patch = repo.parent / "change.patch"
            patch.write_text(
                "diff --git a/value.txt b/value.txt\n"
                "--- a/value.txt\n+++ b/value.txt\n@@ -1 +1 @@\n-BEFORE\n+AFTER\n",
                encoding="utf-8",
            )
            MODULE.apply_patch(repo, commit, patch)
            self.assertEqual((repo / "value.txt").read_text(), "AFTER\n")

    def test_dirty_checkout_rejects_patch(self):
        with tempfile.TemporaryDirectory() as directory:
            repo, commit = self.make_repo(directory)
            patch = repo.parent / "change.patch"
            patch.write_text("not used", encoding="utf-8")
            (repo / "value.txt").write_text("DIRTY\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "dirty or HEAD moved"):
                MODULE.apply_patch(repo, commit, patch)

    def test_generated_migration_patch_is_owner_gated(self):
        with tempfile.TemporaryDirectory() as directory:
            repo, commit = self.make_repo(directory)
            migration = repo / "supabase" / "migrations" / "20260722.sql"
            migration.parent.mkdir(parents=True)
            migration.write_text("select 1;\n", encoding="utf-8")
            subprocess.run(["git", "-C", str(repo), "add", "-N", "."], check=True)
            patch = repo.parent / "migration.patch"
            with patch.open("w", encoding="utf-8") as handle:
                subprocess.run(
                    ["git", "-C", str(repo), "diff", "--binary", commit],
                    check=True,
                    text=True,
                    stdout=handle,
                )
            subprocess.run(["git", "-C", str(repo), "reset", "-q", "HEAD"], check=True)
            subprocess.run(["git", "-C", str(repo), "clean", "-fdq"], check=True)
            with self.assertRaisesRegex(RuntimeError, "owner-gated generated patch"):
                MODULE.apply_patch(repo, commit, patch)

    def test_generated_sensitive_content_is_owner_gated(self):
        with tempfile.TemporaryDirectory() as directory:
            repo, commit = self.make_repo(directory)
            (repo / "value.txt").write_text("authentication token\n", encoding="utf-8")
            patch = repo.parent / "sensitive.patch"
            with patch.open("w", encoding="utf-8") as handle:
                subprocess.run(
                    ["git", "-C", str(repo), "diff", "--binary", commit],
                    check=True,
                    text=True,
                    stdout=handle,
                )
            subprocess.run(["git", "-C", str(repo), "restore", "value.txt"], check=True)
            with self.assertRaisesRegex(RuntimeError, "owner-gated generated patch"):
                MODULE.apply_patch(repo, commit, patch)

    def test_explicit_local_tier_cannot_bypass_owner_gate(self):
        decision = MODULE.forced_decision("volume", "Change the auth migration", [])
        self.assertEqual(decision.tier, "judgment")
        self.assertTrue(decision.owner_gated)

    def test_deploy_and_release_are_owner_gated(self):
        for task in ("Deploy the app", "Cut a release"):
            with self.subTest(task=task):
                decision = MODULE.classify(task)
                self.assertEqual(decision.tier, "judgment")
                self.assertTrue(decision.owner_gated)


if __name__ == "__main__":
    unittest.main()
