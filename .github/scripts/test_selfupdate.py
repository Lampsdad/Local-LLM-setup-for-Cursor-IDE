#!/usr/bin/env python3
"""Tests for scripts/selfupdate.py, the `kiln self-update` backend.

It rewrites the user's checkout, so the refusals are what is worth
pinning down: never discard a local edit, never drop a local commit,
never move a branch other than main, never move a checkout backwards.
Each refusal must also leave HEAD exactly where it was.

Hermetic: "GitHub" is a bare repository in a temporary directory, the
maintainer and the user are two clones of it, and git's global and
system config are both replaced so a signing hook or a defaultBranch
setting on the machine running the tests cannot change the outcome.
"""
import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
sys.dont_write_bytecode = True
import selfupdate  # noqa: E402


def sh(cwd, *args):
    p = subprocess.run(["git", "-C", cwd] + list(args),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       universal_newlines=True)
    if p.returncode != 0:
        raise AssertionError("git %s: %s" % (" ".join(args), p.stderr))
    return p.stdout.strip()


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.saved_env = dict(os.environ)
        self.saved_root = selfupdate.ROOT
        gitconfig = os.path.join(self.tmp.name, "gitconfig")
        with open(gitconfig, "w") as fh:
            fh.write("[user]\n\tname = kiln test\n\temail = test@example.com\n"
                     "[commit]\n\tgpgsign = false\n[tag]\n\tgpgsign = false\n")
        os.environ.update(HOME=self.tmp.name, GIT_CONFIG_NOSYSTEM="1",
                          GIT_CONFIG_GLOBAL=gitconfig)
        os.environ.pop("KILN_NO_UPDATE_CHECK", None)

        # GitHub, the maintainer's working copy, and v1.0.0 published.
        self.origin = self.path("origin.git")
        sh(self.tmp.name, "init", "--quiet", "--bare", self.origin)
        sh(self.origin, "symbolic-ref", "HEAD", "refs/heads/main")
        self.dev = self.path("dev")
        sh(self.tmp.name, "init", "--quiet", self.dev)
        sh(self.dev, "symbolic-ref", "HEAD", "refs/heads/main")
        sh(self.dev, "remote", "add", "origin", self.origin)
        self.publish("kiln.sh", "one", tag="v1.0.0")

        self.user = self.path("user")
        sh(self.tmp.name, "clone", "--quiet", self.origin, self.user)
        selfupdate.ROOT = self.user

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self.saved_env)
        selfupdate.ROOT = self.saved_root
        self.tmp.cleanup()

    def path(self, *parts):
        return os.path.join(self.tmp.name, *parts)

    def commit(self, repo, name, text):
        with open(os.path.join(repo, name), "w") as fh:
            fh.write(text)
        sh(repo, "add", name)
        sh(repo, "commit", "--quiet", "-m", "change %s" % name)
        return sh(repo, "rev-parse", "HEAD")

    def publish(self, name, text, tag=None, annotated=True):
        """The maintainer commits, optionally tags, and pushes."""
        sha = self.commit(self.dev, name, text)
        if tag:
            if annotated:
                sh(self.dev, "tag", "-a", tag, "-m", tag)
            else:
                sh(self.dev, "tag", tag)
        sh(self.dev, "push", "--quiet", "origin", "main", "--tags")
        return sha

    def head(self):
        return sh(self.user, "rev-parse", "HEAD")

    def run_cli(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = selfupdate.main(list(argv))
        return code, out.getvalue()

    def notice(self):
        code, out = self.run_cli("--notice")
        self.assertEqual(code, 0)
        return dict(line.split("=", 1) for line in out.splitlines())


class ReleaseChannelTest(Base):
    def test_up_to_date(self):
        before = self.head()
        code, out = self.run_cli()
        self.assertEqual(code, 0)
        self.assertIn("Up to date: v1.0.0", out)
        self.assertEqual(self.head(), before)

    def test_moves_to_the_newest_release_not_past_it(self):
        released = self.publish("kiln.sh", "two", tag="v1.1.0")
        self.publish("kiln.sh", "unreleased work")
        code, out = self.run_cli()
        self.assertEqual(code, 0, out)
        self.assertEqual(self.head(), released)
        self.assertIn("Updated to v1.1.0", out)

    def test_lightweight_tags_are_releases_too(self):
        released = self.publish("kiln.sh", "two", tag="v1.1.0",
                                annotated=False)
        self.assertEqual(self.run_cli()[0], 0)
        self.assertEqual(self.head(), released)

    def test_a_tag_moved_on_github_is_followed(self):
        self.publish("kiln.sh", "two", tag="v1.1.0")
        self.assertEqual(self.run_cli()[0], 0)
        fixed = self.commit(self.dev, "kiln.sh", "two, fixed")
        sh(self.dev, "tag", "-f", "-a", "v1.1.0", "-m", "v1.1.0")
        sh(self.dev, "push", "--quiet", "--force", "origin", "main", "v1.1.0")
        code, out = self.run_cli()
        self.assertEqual(code, 0, out)
        self.assertEqual(self.head(), fixed)

    def test_a_checkout_past_the_newest_release_is_not_moved_back(self):
        tip = self.publish("kiln.sh", "unreleased work")
        sh(self.user, "pull", "--quiet", "--ff-only")
        code, out = self.run_cli()
        self.assertEqual(code, 0)
        self.assertEqual(self.head(), tip)
        self.assertIn("already past the newest", out)
        self.assertIn("--main", out)

    def test_versions_compare_as_numbers(self):
        self.assertEqual(selfupdate.newest_release(
            ["v1.9.0", "v1.10.0", "v2-beta", "v3.0.0-rc1", "latest"]),
            "v1.10.0")
        self.assertIsNone(selfupdate.newest_release(["nightly"]))


class MainChannelTest(Base):
    def test_follows_main_and_remembers_it(self):
        first = self.publish("kiln.sh", "two")
        code, out = self.run_cli("--main")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.head(), first)
        self.assertEqual(sh(self.user, "config", "kiln.channel"), "main")

        second = self.publish("kiln.sh", "three")
        self.assertEqual(self.run_cli()[0], 0)
        self.assertEqual(self.head(), second)

    def test_release_switches_back(self):
        self.publish("kiln.sh", "two")
        self.run_cli("--main")
        self.publish("kiln.sh", "three")
        before = self.head()
        self.assertEqual(self.run_cli("--release")[0], 0)
        self.assertEqual(sh(self.user, "config", "kiln.channel"), "release")
        self.assertEqual(self.head(), before)


class RefusalTest(Base):
    def setUp(self):
        super().setUp()
        self.publish("kiln.sh", "two", tag="v1.1.0")

    def assertRefused(self, *argv, says):
        before = self.head()
        code, out = self.run_cli(*argv)
        self.assertEqual(code, 1, out)
        self.assertIn(says, out)
        self.assertEqual(self.head(), before)

    def test_local_edits(self):
        # Checked before fetching, not left to git merge, which would
        # refuse too but with git's message rather than the way out.
        with open(os.path.join(self.user, "kiln.sh"), "w") as fh:
            fh.write("my tweak")
        self.assertRefused(says="git stash")
        with open(os.path.join(self.user, "kiln.sh")) as fh:
            self.assertEqual(fh.read(), "my tweak")

    def test_local_commits(self):
        self.commit(self.user, "mine.txt", "mine")
        self.assertRefused(says="GitHub does not have")

    def test_another_branch(self):
        sh(self.user, "switch", "--quiet", "-c", "feature")
        self.assertRefused(says="branch 'feature'")

    def test_detached_head(self):
        sh(self.user, "checkout", "--quiet", "--detach")
        self.assertRefused(says="detached")

    def test_not_a_clone(self):
        plain = self.path("zip-download")
        os.makedirs(plain)
        selfupdate.ROOT = plain
        code, out = self.run_cli()
        self.assertEqual(code, 1)
        self.assertIn("git clone", out)

    def test_no_release_yet(self):
        sh(self.user, "tag", "-d", "v1.0.0")
        sh(self.dev, "push", "--quiet", "origin", ":v1.0.0", ":v1.1.0")
        self.assertRefused(says="--main")


class UntrackedFilesTest(Base):
    def test_weights_binaries_and_key_survive(self):
        released = self.publish("kiln.sh", "two", tag="v1.1.0")
        keep = {"models/Qwen3.8-27B-UD-Q5_K_XL.gguf": "weights",
                "llama-bin/llama-server": "binary",
                "api_key.txt": "secret"}
        for rel, text in keep.items():
            os.makedirs(os.path.dirname(self.path("user", rel)), exist_ok=True)
            with open(self.path("user", rel), "w") as fh:
                fh.write(text)
        self.assertEqual(self.run_cli()[0], 0)
        self.assertEqual(self.head(), released)
        for rel, text in keep.items():
            with open(self.path("user", rel)) as fh:
                self.assertEqual(fh.read(), text)


class CheckTest(Base):
    def test_reports_without_moving(self):
        self.publish("kiln.sh", "two", tag="v1.1.0")
        before = self.head()
        code, out = self.run_cli("--check")
        self.assertEqual(code, 0)
        self.assertIn("Update available: v1.1.0", out)
        self.assertEqual(self.head(), before)


class NoticeTest(Base):
    def cache_file(self):
        return os.path.join(self.user, ".git", selfupdate.CACHE_NAME)

    def test_version_and_update(self):
        self.assertEqual(self.notice(), {"KILN_VERSION": "v1.0.0"})
        os.remove(self.cache_file())
        self.publish("kiln.sh", "two", tag="v1.1.0")
        self.assertEqual(self.notice(), {"KILN_VERSION": "v1.0.0",
                                         "KILN_UPDATE": "v1.1.0"})

    def test_asks_github_at_most_once_a_day(self):
        self.notice()
        self.publish("kiln.sh", "two", tag="v1.1.0")
        self.assertNotIn("KILN_UPDATE", self.notice())

        with open(self.cache_file()) as fh:
            cache = json.load(fh)
        cache["checked"] -= selfupdate.CHECK_EVERY + 1
        with open(self.cache_file(), "w") as fh:
            json.dump(cache, fh)
        self.assertEqual(self.notice().get("KILN_UPDATE"), "v1.1.0")

    def test_offline_still_prints_the_version(self):
        sh(self.user, "remote", "set-url", "origin", self.path("gone.git"))
        self.assertEqual(self.notice(), {"KILN_VERSION": "v1.0.0"})
        self.assertTrue(os.path.exists(self.cache_file()))

    def test_opt_out_never_asks(self):
        os.environ["KILN_NO_UPDATE_CHECK"] = "1"
        self.publish("kiln.sh", "two", tag="v1.1.0")
        self.assertEqual(self.notice(), {"KILN_VERSION": "v1.0.0"})
        self.assertFalse(os.path.exists(self.cache_file()))

    def test_no_update_offered_after_updating(self):
        self.publish("kiln.sh", "two", tag="v1.1.0")
        self.assertEqual(self.notice().get("KILN_UPDATE"), "v1.1.0")
        self.run_cli()
        self.assertEqual(self.notice(), {"KILN_VERSION": "v1.1.0"})

    def test_version_past_a_release(self):
        self.publish("kiln.sh", "two")
        self.run_cli("--main")
        version = self.notice()["KILN_VERSION"]
        self.assertRegex(version, r"^v1\.0\.0 \+ 1 commit, [0-9a-f]+$")

    def test_nothing_cmd_would_parse_reaches_the_board(self):
        self.assertEqual(selfupdate.board_safe('v1 & del "x" | %PATH% ^!'),
                         "v1  del x  PATH ")


if __name__ == "__main__":
    unittest.main(verbosity=2)
