#!/usr/bin/env python3
from __future__ import annotations

import importlib.machinery
import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock


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

    def test_migration_word_is_owner_gated(self):
        decision = MODULE.classify("Update the database migration")
        self.assertEqual(decision.tier, "judgment")
        self.assertTrue(decision.owner_gated)

    def test_migration_file_is_owner_gated(self):
        decision = MODULE.classify("Fix the typo", ["supabase/migrations/20260722.sql"])
        self.assertEqual(decision.tier, "judgment")
        self.assertTrue(decision.owner_gated)

    def test_camel_case_sensitive_files_are_owner_gated(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = pathlib.Path(directory)
            for path in (
                "src/AuthManager.swift",
                "src/AuthView.swift",
                "src/UserSession.swift",
                "src/PermissionsView.swift",
                "src/PaymentService.swift",
                "src/SecretStore.swift",
                "src/ReleaseBuilder.swift",
            ):
                with self.subTest(path=path):
                    decision = MODULE.classify("Fix the typo", [path], repo)
                    self.assertEqual(decision.tier, "judgment")
                    self.assertTrue(decision.owner_gated)

    def test_build_cut_paths_are_owner_gated(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = pathlib.Path(directory)
            for path in ("scripts/build.py", ".github/workflows/build.yml", "build.sh"):
                with self.subTest(path=path):
                    decision = MODULE.classify("Update the step", [path], repo)
                    self.assertEqual(decision.tier, "judgment")
                    self.assertTrue(decision.owner_gated)

    def test_root_sensitive_filename_in_task_is_gated_before_dispatch(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = pathlib.Path(directory)
            for task in (
                "Update build.sh",
                "Change App.entitlements",
                "Fix AuthManager.swift",
                "Update .env",
            ):
                with self.subTest(task=task):
                    decision = MODULE.classify(task, repo=repo)
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

    def test_legacy_local_large_aliases_to_quality(self):
        content = """
| Tier | Endpoint / harness | Use for |
|---|---|---|
| local-large | `http://host:8000/v1` (`large-model`, 131072 context) | hard work |
| local-volume | `http://host:8001/v1` (`volume-model`, 131072 context) | routine work |
"""
        with tempfile.TemporaryDirectory() as directory:
            fleet = pathlib.Path(directory) / "fleet.md"
            fleet.write_text(content, encoding="utf-8")
            tiers = MODULE.load_tiers(fleet)
        self.assertEqual(tiers["local-quality"].model, "large-model")
        self.assertEqual(tiers["local-quality"].endpoint, "http://host:8000/v1")

    def test_legacy_endpoint_only_rows_use_worker_model_discovery(self):
        content = """
| Tier | Endpoint / harness | Use for |
|---|---|---|
| local-volume | `http://legacy-host:8001/v1` | routine work |
| local-large | `http://legacy-host:8000/v1` | hard work |
"""
        with tempfile.TemporaryDirectory() as directory:
            fleet = pathlib.Path(directory) / "fleet.md"
            fleet.write_text(content, encoding="utf-8")
            tiers = MODULE.load_tiers(fleet)
            self.assertEqual(tiers["local-volume"].model, "__auto__")
            self.assertEqual(tiers["local-quality"].model, "__auto__")
            with self.assertRaisesRegex(RuntimeError, "legacy configurations must add"):
                MODULE.load_worker_host(fleet)
            self.assertEqual(MODULE.load_task_timeout(fleet), 900)
            self.assertEqual(MODULE.load_transport_timeout(fleet), 120)

    def test_relative_brain_pointer_is_resolved_from_pointer_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            home = pathlib.Path(directory)
            pointer_dir = home / ".config" / "borrowedfire"
            pointer_dir.mkdir(parents=True)
            expected = pointer_dir / "relative-brain"
            expected.mkdir()
            (pointer_dir / "brain").write_text("relative-brain\n", encoding="utf-8")
            with mock.patch.dict(MODULE.os.environ, {"HOME": str(home)}, clear=False):
                with mock.patch.object(MODULE.pathlib.Path, "home", return_value=home):
                    self.assertEqual(MODULE.brain_dir(), expected.resolve())

    def test_rejects_shell_metacharacters_in_private_tiers(self):
        content = """
| Tier | Endpoint / harness | Use for |
|---|---|---|
| local-quality | `http://host:8000/v1;touch /tmp/pwned` (`quality-model`, 131072 context) | hard work |
| local-volume | `http://host:8001/v1` (`volume-model`, 131072 context) | routine work |
"""
        with tempfile.TemporaryDirectory() as directory:
            fleet = pathlib.Path(directory) / "fleet.md"
            fleet.write_text(content, encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "unsafe endpoint"):
                MODULE.load_tiers(fleet)

    def test_rejects_endpoint_without_explicit_worker_port(self):
        content = """
| Tier | Endpoint / harness | Use for |
|---|---|---|
| local-quality | `http://host/v1` (`quality-model`, 131072 context) | hard work |
| local-volume | `http://host:8001/v1` (`volume-model`, 131072 context) | routine work |
"""
        with tempfile.TemporaryDirectory() as directory:
            fleet = pathlib.Path(directory) / "fleet.md"
            fleet.write_text(content, encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "unsafe endpoint"):
                MODULE.load_tiers(fleet)

    def test_rejects_https_endpoint_the_worker_cannot_preserve(self):
        content = """
| Tier | Endpoint / harness | Use for |
|---|---|---|
| local-quality | `https://host:8000/v1` (`quality-model`, 131072 context) | hard work |
| local-volume | `http://host:8001/v1` (`volume-model`, 131072 context) | routine work |
"""
        with tempfile.TemporaryDirectory() as directory:
            fleet = pathlib.Path(directory) / "fleet.md"
            fleet.write_text(content, encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "unsafe endpoint"):
                MODULE.load_tiers(fleet)

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

    def test_reads_bounded_task_timeout(self):
        content = "- Local task timeout seconds: `900`\n"
        with tempfile.TemporaryDirectory() as directory:
            fleet = pathlib.Path(directory) / "fleet.md"
            fleet.write_text(content, encoding="utf-8")
            self.assertEqual(MODULE.load_task_timeout(fleet), 900)

    def test_reads_paid_whitelist_and_numeric_cap(self):
        content = """
- Paid task whitelist: review, plan, escalate. Everything else defaults to local.
- Escalation cap: 2
"""
        with tempfile.TemporaryDirectory() as directory:
            fleet = pathlib.Path(directory) / "fleet.md"
            fleet.write_text(content, encoding="utf-8")
            policy = MODULE.load_paid_policy(fleet)
        self.assertEqual(policy.whitelist, ("review", "plan", "escalate"))
        self.assertEqual(policy.escalation_cap, 2)

    def test_pending_paid_cap_fails_safe_to_one(self):
        content = """
- Paid task whitelist: review, plan, escalate
- Escalation cap: pending owner setting; default to brief rather than repeated paid retries.
"""
        with tempfile.TemporaryDirectory() as directory:
            fleet = pathlib.Path(directory) / "fleet.md"
            fleet.write_text(content, encoding="utf-8")
            self.assertEqual(MODULE.load_paid_policy(fleet).escalation_cap, 1)

    def test_reads_bounded_transport_timeout(self):
        content = "- Local transport timeout seconds: `120`\n"
        with tempfile.TemporaryDirectory() as directory:
            fleet = pathlib.Path(directory) / "fleet.md"
            fleet.write_text(content, encoding="utf-8")
            self.assertEqual(MODULE.load_transport_timeout(fleet), 120)

    def test_worker_seals_untrusted_artifacts_without_following_links(self):
        helper = (ROOT / "tools" / "bf-local-agent-remote").read_text(encoding="utf-8")
        self.assertIn('untrusted_dir="$run_dir/untrusted"', helper)
        self.assertIn('artifact_dir="$run_dir/artifacts"', helper)
        self.assertIn("os.O_NOFOLLOW", helper)
        self.assertIn("stat.S_ISREG", helper)
        self.assertIn("source_stat.st_nlink != 1", helper)
        self.assertIn("BF_RESULT_${result_nonce}_PATCH", helper)

    def test_worker_uses_a_kernel_released_lock(self):
        helper = (ROOT / "tools" / "bf-local-agent-remote").read_text(encoding="utf-8")
        self.assertIn('exec 9>"$lock_file"', helper)
        self.assertIn("flock -n 9", helper)
        self.assertNotIn('mkdir "$lock_dir"', helper)
        installer = (ROOT / "tools" / "install-local-agent-worker").read_text(encoding="utf-8")
        self.assertIn("docker flock git python3 timeout", installer)

    def test_worker_resolves_the_container_side_model_port(self):
        helper = (ROOT / "tools" / "bf-local-agent-remote").read_text(encoding="utf-8")
        self.assertIn(".NetworkSettings.Ports", helper)
        self.assertIn('internal_endpoint="http://model-$port:$container_port/v1"', helper)
        self.assertIn('timeout --signal=TERM --kill-after=30s "${task_timeout}s"', helper)
        self.assertIn("--pull=never", helper)

    def test_worker_preserves_ignored_tracked_files_and_uses_configured_discovery_endpoint(self):
        helper = (ROOT / "tools" / "bf-local-agent-remote").read_text(encoding="utf-8")
        self.assertIn('git -C "$workspace" add -f -A', helper)
        self.assertIn('python3 - "$endpoint/models"', helper)
        self.assertNotIn('http://127.0.0.1:{port}/v1/models', helper)


class ApplySafetyTests(unittest.TestCase):
    def setUp(self):
        self.brain = tempfile.TemporaryDirectory()
        self.brain_environment = mock.patch.dict(
            "os.environ", {"PROMETHEUS_DIR": self.brain.name}
        )
        self.brain_environment.start()

    def tearDown(self):
        self.brain_environment.stop()
        self.brain.cleanup()

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

    def test_generated_key_assignment_is_owner_gated(self):
        with tempfile.TemporaryDirectory() as directory:
            repo, commit = self.make_repo(directory)
            (repo / "value.txt").write_text('API_KEY = "xyz789"\n', encoding="utf-8")
            patch = repo.parent / "key.patch"
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

    def test_generated_destructive_data_operations_are_owner_gated(self):
        for content in (
            'await supabase.from("users").delete().eq("id", user_id)\n',
            "DELETE FROM users WHERE id = 1;\n",
            "INSERT INTO users (id) VALUES (1);\n",
            "UPDATE users SET role = 'admin';\n",
            'await supabase.from("users").update({"role": "admin"})\n',
        ):
            with self.subTest(content=content), tempfile.TemporaryDirectory() as directory:
                repo, commit = self.make_repo(directory)
                (repo / "value.txt").write_text(content, encoding="utf-8")
                patch = repo.parent / "destructive.patch"
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

    def test_generated_schema_and_rls_ddl_are_owner_gated(self):
        statements = (
            "ALTER TABLE users ADD COLUMN display_name text;",
            "CREATE TABLE audit_log (id bigint);",
            "CREATE POLICY own_rows ON users USING (auth.uid() = id);",
            "ALTER TABLE users ENABLE ROW LEVEL SECURITY;",
            "GRANT SELECT ON users TO authenticated;",
        )
        for statement in statements:
            with self.subTest(statement=statement), tempfile.TemporaryDirectory() as directory:
                repo, commit = self.make_repo(directory)
                (repo / "value.txt").write_text(statement + "\n", encoding="utf-8")
                patch = repo.parent / "ddl.patch"
                patch.write_text(
                    subprocess.check_output(["git", "-C", str(repo), "diff", commit], text=True),
                    encoding="utf-8",
                )
                subprocess.run(["git", "-C", str(repo), "restore", "value.txt"], check=True)
                with self.assertRaisesRegex(RuntimeError, "owner-gated generated patch"):
                    MODULE.apply_patch(repo, commit, patch)

    def test_generated_release_build_commands_are_owner_gated(self):
        commands = (
            "npm run build",
            "./gradlew bundleRelease",
            '"build": "vite build"',
            "release: docker build .",
            "git push origin main",
        )
        for command in commands:
            with self.subTest(command=command), tempfile.TemporaryDirectory() as directory:
                repo, commit = self.make_repo(directory)
                (repo / "value.txt").write_text(command + "\n", encoding="utf-8")
                patch = repo.parent / "build.patch"
                patch.write_text(
                    subprocess.check_output(["git", "-C", str(repo), "diff", commit], text=True),
                    encoding="utf-8",
                )
                subprocess.run(["git", "-C", str(repo), "restore", "value.txt"], check=True)
                with self.assertRaisesRegex(RuntimeError, "owner-gated generated patch"):
                    MODULE.apply_patch(repo, commit, patch)

    def test_generated_session_permission_and_schema_logic_is_owner_gated(self):
        for content in (
            "session.refresh()\n",
            "permissions.add(role)\n",
            "schema.create_table(name)\n",
            "enable_rls(table)\n",
        ):
            with self.subTest(content=content), tempfile.TemporaryDirectory() as directory:
                repo, commit = self.make_repo(directory)
                (repo / "value.txt").write_text(content, encoding="utf-8")
                patch = repo.parent / "policy.patch"
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

    def test_generated_binary_patch_is_owner_gated(self):
        with tempfile.TemporaryDirectory() as directory:
            repo, commit = self.make_repo(directory)
            (repo / "safe.dat").write_bytes(b"PRIVATE KEY\0SECRET_TOKEN=abcd123456789\0")
            subprocess.run(["git", "-C", str(repo), "add", "-N", "."], check=True)
            patch = repo.parent / "binary.patch"
            with patch.open("wb") as handle:
                subprocess.run(
                    ["git", "-C", str(repo), "diff", "--binary", commit],
                    check=True,
                    stdout=handle,
                )
            subprocess.run(["git", "-C", str(repo), "reset", "-q", "HEAD"], check=True)
            subprocess.run(["git", "-C", str(repo), "clean", "-fdq"], check=True)
            with self.assertRaisesRegex(RuntimeError, "binary content"):
                MODULE.apply_patch(repo, commit, patch)

    def test_rename_from_owner_gated_path_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = pathlib.Path(directory) / "repo"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            subprocess.run(["git", "-C", str(repo), "config", "user.name", "Test"], check=True)
            subprocess.run(["git", "-C", str(repo), "config", "user.email", "test@invalid"], check=True)
            (repo / "config").mkdir()
            (repo / "config" / "development.yaml").write_text("safe: true\n", encoding="utf-8")
            subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
            subprocess.run(["git", "-C", str(repo), "commit", "-qm", "baseline"], check=True)
            commit = subprocess.run(
                ["git", "-C", str(repo), "rev-parse", "HEAD"],
                check=True,
                text=True,
                stdout=subprocess.PIPE,
            ).stdout.strip()
            subprocess.run(
                ["git", "-C", str(repo), "mv", "config/development.yaml", "safe.txt"],
                check=True,
            )
            patch = repo.parent / "rename.patch"
            with patch.open("w", encoding="utf-8") as handle:
                subprocess.run(
                    ["git", "-C", str(repo), "diff", "--binary", commit],
                    check=True,
                    text=True,
                    stdout=handle,
                )
            subprocess.run(["git", "-C", str(repo), "reset", "--hard", "-q", commit], check=True)
            paths = MODULE.patch_paths(repo, patch)
            self.assertIn("config/development.yaml", paths)
            self.assertIn("safe.txt", paths)
            with self.assertRaisesRegex(RuntimeError, "owner-gated generated patch"):
                MODULE.apply_patch(repo, commit, patch)

    def test_malformed_patch_fails_closed_with_a_readable_error(self):
        with tempfile.TemporaryDirectory() as directory:
            repo, _ = self.make_repo(directory)
            patch = repo.parent / "malformed.patch"
            patch.write_text("not a patch\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "cannot inspect generated patch"):
                MODULE.patch_paths(repo, patch)

    def test_authoritative_denylist_covers_backfills_and_environment_config(self):
        with tempfile.TemporaryDirectory() as directory:
            repo, _ = self.make_repo(directory)
            paths, _ = MODULE.authoritative_patch_patterns(repo)
        for path in (
            "scripts/backfill.py",
            "config/development.yaml",
            "environments/staging.tfvars",
            "App/Release.xcconfig",
            "App/App.entitlements",
        ):
            with self.subTest(path=path):
                self.assertTrue(MODULE.matches_any(path, paths))

    def test_project_denylist_extra_is_loaded_from_matching_registry_page(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            repo = root / "Widget"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "remote", "add", "origin", "git@github.com:BorrowedFire/Widget.git"],
                check=True,
            )
            projects = root / "brain" / "projects"
            projects.mkdir(parents=True)
            (projects / "widget.md").write_text(
                "repo: BorrowedFire/Widget\ndenylist_extra: [analytics/**, audit log]\n",
                encoding="utf-8",
            )
            with mock.patch.dict("os.environ", {"PROMETHEUS_DIR": str(root / "brain")}):
                self.assertEqual(MODULE.project_denylist_extras(repo), ["analytics/**", "audit log"])

    def test_project_policy_matches_non_github_remote_and_different_clone_name(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            repo = root / "widget-copy"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "remote", "add", "origin", "https://gitlab.com/acme/widget.git"],
                check=True,
            )
            projects = root / "brain" / "projects"
            projects.mkdir(parents=True)
            (projects / "widget.md").write_text(
                "repo: acme/widget\ndenylist_extra: [analytics/**]\n",
                encoding="utf-8",
            )
            with mock.patch.dict("os.environ", {"PROMETHEUS_DIR": str(root / "brain")}):
                self.assertEqual(MODULE.project_denylist_extras(repo), ["analytics/**"])

    def test_unregistered_project_uses_authoritative_defaults(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            repo = root / "Widget"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "remote", "add", "origin", "https://gitlab.com/acme/widget.git"],
                check=True,
            )
            projects = root / "brain" / "projects"
            projects.mkdir(parents=True)
            (projects / "other.md").write_text("repo: acme/other\n", encoding="utf-8")
            with mock.patch.dict("os.environ", {"PROMETHEUS_DIR": str(root / "brain")}):
                self.assertEqual(MODULE.project_denylist_extras(repo), [])

    def test_ambiguous_project_policy_resolution_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            repo = root / "Widget"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            projects = root / "brain" / "projects"
            projects.mkdir(parents=True)
            (projects / "one.md").write_text("repo: acme/Widget\n", encoding="utf-8")
            (projects / "two.md").write_text("repo: other/Widget\n", encoding="utf-8")
            with mock.patch.dict("os.environ", {"PROMETHEUS_DIR": str(root / "brain")}):
                with self.assertRaisesRegex(RuntimeError, "cannot uniquely resolve project policy"):
                    MODULE.project_denylist_extras(repo)

    def test_task_embedded_sensitive_path_is_gated_before_dispatch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            repo = root / "Widget"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "remote", "add", "origin", "git@github.com:BorrowedFire/Widget.git"],
                check=True,
            )
            projects = root / "brain" / "projects"
            projects.mkdir(parents=True)
            (projects / "widget.md").write_text("repo: BorrowedFire/Widget\n", encoding="utf-8")
            with mock.patch.dict("os.environ", {"PROMETHEUS_DIR": str(root / "brain")}):
                decision = MODULE.forced_decision(
                    "volume", "Update supabase/migrations/20260722.sql", [], repo
                )
                self.assertEqual(decision.tier, "judgment")
                self.assertTrue(decision.owner_gated)

    def test_authoritative_and_project_paths_are_gated_before_dispatch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            repo = root / "Widget"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "remote", "add", "origin", "git@github.com:BorrowedFire/Widget.git"],
                check=True,
            )
            projects = root / "brain" / "projects"
            projects.mkdir(parents=True)
            (projects / "widget.md").write_text(
                "repo: BorrowedFire/Widget\ndenylist_extra: [analytics/**]\n",
                encoding="utf-8",
            )
            with mock.patch.dict("os.environ", {"PROMETHEUS_DIR": str(root / "brain")}):
                for path in (
                    "config/development.yaml",
                    ".env",
                    "App/App.entitlements",
                    "analytics/events.py",
                ):
                    with self.subTest(path=path):
                        decision = MODULE.forced_decision("volume", "Fix the typo", [path], repo)
                        self.assertEqual(decision.tier, "judgment")
                        self.assertTrue(decision.owner_gated)

    def test_transport_exception_reaches_paid_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            repo, _ = self.make_repo(directory)
            args = types.SimpleNamespace(
                repo=str(repo),
                ref="HEAD",
                task="Fix the typo",
                file=[],
                tier="auto",
                dry_run=False,
                allow_paid=True,
                worker="worker",
                mode="code",
                apply=False,
            )
            tiers = {
                "local-volume": MODULE.Tier("local-volume", "http://host:1/v1", "volume"),
                "local-quality": MODULE.Tier("local-quality", "http://host:2/v1", "quality"),
            }
            with (
                mock.patch.object(MODULE, "load_tiers", return_value=tiers),
                mock.patch.object(MODULE, "load_task_timeout", return_value=900),
                mock.patch.object(MODULE, "load_transport_timeout", return_value=120),
                mock.patch.object(MODULE, "local_attempt", side_effect=RuntimeError("worker offline")),
                mock.patch.object(
                    MODULE, "paid_call_allowed", return_value=(True, "test permits paid")
                ),
                mock.patch.object(MODULE, "paid_runtime_preflight"),
                mock.patch.object(MODULE, "paid_attempt", return_value=(0, None, None, "paid-run")) as paid,
                mock.patch.object(MODULE, "append_ledger"),
            ):
                self.assertEqual(MODULE.command_run(args), 0)
                paid.assert_called_once()

    def test_paid_policy_blocks_disallowed_tasks_and_repeated_attempts(self):
        repo = pathlib.Path("/tmp/Widget")
        commit = "a" * 40
        task_hash = "b" * 64
        routine = MODULE.RouteDecision("local-volume", "bounded work default")
        with (
            mock.patch.object(
                MODULE,
                "load_paid_policy",
                return_value=MODULE.PaidPolicy(("review", "plan", "escalate"), 1),
            ),
            mock.patch.object(MODULE, "paid_attempt_count", return_value=0),
        ):
            allowed, reason = MODULE.paid_call_allowed(
                repo, commit, "Fix the typo", task_hash, routine
            )
            self.assertFalse(allowed)
            self.assertIn("not on", reason)
            allowed, _ = MODULE.paid_call_allowed(
                repo, commit, "Escalate the parser failure", task_hash, routine
            )
            self.assertTrue(allowed)
        with (
            mock.patch.object(
                MODULE,
                "load_paid_policy",
                return_value=MODULE.PaidPolicy(("review",), 1),
            ),
            mock.patch.object(MODULE, "paid_attempt_count", return_value=1),
        ):
            allowed, reason = MODULE.paid_call_allowed(
                repo, commit, "Review the parser", task_hash, routine
            )
            self.assertFalse(allowed)
            self.assertIn("cap reached", reason)

    def test_archive_cleanup_timeout_is_a_transport_failure(self):
        archive = mock.Mock()
        archive.stdout = mock.Mock()
        archive.wait.return_value = 0
        completed = subprocess.CompletedProcess([], 0)
        failed = subprocess.CompletedProcess([], 1)
        with (
            mock.patch.object(MODULE.subprocess, "Popen", return_value=archive),
            mock.patch.object(
                MODULE.subprocess,
                "run",
                side_effect=[completed, failed, subprocess.TimeoutExpired(["ssh"], 120)],
            ),
            self.assertRaisesRegex(RuntimeError, "timed out while cleaning"),
        ):
            MODULE.stream_archive("worker", pathlib.Path("."), "a" * 40, "/remote/work", 120)

    def test_remote_artifact_must_match_current_artifact_shape(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError, "unsafe artifact path"):
                MODULE.copy_remote_artifact(
                    "worker",
                    "/home/worker",
                    "Widget",
                    "/home/worker/.local/state/borrowedfire-route/Widget/other/final.txt",
                    "final.txt",
                    pathlib.Path(directory) / "final.txt",
                    120,
                )

    def test_remote_artifact_rejects_parent_traversal(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError, "unsafe artifact path"):
                MODULE.copy_remote_artifact(
                    "worker",
                    "/home/worker",
                    "Widget",
                    "/home/worker/.local/state/borrowedfire-route/Widget/../artifacts/final.txt",
                    "final.txt",
                    pathlib.Path(directory) / "final.txt",
                    120,
                )

    def test_missing_codex_does_not_reserve_paid_attempt(self):
        with tempfile.TemporaryDirectory() as directory:
            repo, _ = self.make_repo(directory)
            args = types.SimpleNamespace(
                repo=str(repo),
                ref="HEAD",
                task="Review the change",
                file=[],
                tier="auto",
                dry_run=False,
                allow_paid=True,
                worker=None,
                mode="advice",
                apply=False,
            )
            with (
                mock.patch.object(MODULE.shutil, "which", return_value=None),
                mock.patch.object(MODULE, "paid_call_allowed") as policy,
                mock.patch.object(MODULE, "append_ledger") as ledger,
                self.assertRaisesRegex(RuntimeError, "Codex CLI is not installed"),
            ):
                MODULE.command_run(args)
            policy.assert_not_called()
            ledger.assert_not_called()

    def test_remote_artifact_copy_timeout_is_a_transport_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            with (
                mock.patch.object(
                    MODULE,
                    "run_checked",
                    side_effect=subprocess.TimeoutExpired(["scp"], 120),
                ),
                self.assertRaisesRegex(RuntimeError, "timed out while retrieving final.txt"),
            ):
                MODULE.copy_remote_artifact(
                    "worker",
                    "/home/worker",
                    "Widget",
                    "/home/worker/.local/state/borrowedfire-route/Widget/run/artifacts/final.txt",
                    "final.txt",
                    pathlib.Path(directory) / "final.txt",
                    120,
                )

    def test_success_requires_authenticated_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            final = pathlib.Path(directory) / "final.txt"
            final.write_text("done\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "without an authenticated patch"):
                MODULE.validate_attempt_artifacts("code", 0, None, final)
            with self.assertRaisesRegex(RuntimeError, "without an authenticated final"):
                MODULE.validate_attempt_artifacts("advice", 0, None, None)
            MODULE.validate_attempt_artifacts("advice", 0, None, final)

    def test_paid_success_is_rejected_without_final_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            state = pathlib.Path(directory) / "state"
            state.mkdir()
            completed = subprocess.CompletedProcess([], 0, stdout="", stderr="")
            with (
                mock.patch.object(MODULE.shutil, "which", return_value="/usr/bin/codex"),
                mock.patch.object(MODULE, "state_root", return_value=state),
                mock.patch.object(MODULE, "run_checked", return_value=completed),
                mock.patch.object(MODULE.subprocess, "run", return_value=completed),
                mock.patch.object(MODULE, "git", return_value=completed),
                self.assertRaisesRegex(RuntimeError, "without an authenticated final"),
            ):
                MODULE.paid_attempt(pathlib.Path(directory), "a" * 40, "Review this", "advice")

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
