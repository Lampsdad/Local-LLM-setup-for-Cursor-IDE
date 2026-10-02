#!/usr/bin/env python3
"""
Bring this checkout up to date from GitHub. This is the backend for
`kiln self-update` and for the kiln row on the status board.

TWO CHANNELS
------------
    release   the newest vX.Y.Z tag. This is the default. It only moves
              when a release is published, so work in progress on main
              never reaches someone who just wants the next working
              version.
    main      the tip of origin/main, so every change arrives the day
              it lands.

The choice is saved in this clone's own git config as kiln.channel.
Running `kiln self-update --main` once keeps following main from then
on, and --release switches back.

IT ONLY FAST-FORWARDS
---------------------
The update is a `git merge --ff-only`. models/, llama-bin/,
api_key.txt and anything else git does not track are never touched,
and a checkout that cannot move cleanly is left exactly as it was. It
refuses when:

    - this is not a git clone (GitHub's "Download ZIP" has no history)
    - HEAD is not the main branch
    - a tracked file has local edits, which the update would overwrite
    - main has commits GitHub does not have, which it would have to drop

It does nothing when the checkout is already at or past the target.
That keeps a clone of main that is ahead of the newest release where it
is, rather than moving it backwards.

THE STATUS BOARD CHECK
----------------------
--notice asks GitHub what is there with `git ls-remote`, which
downloads nothing. It does this at most once a day, caches the answer
inside .git, and gives up after a few seconds when offline. Set
KILN_NO_UPDATE_CHECK=1 to turn off the network part.

Usage:
    selfupdate.py              update on the saved channel
    selfupdate.py --main       follow main from now on, then update
    selfupdate.py --release    follow releases from now on, then update
    selfupdate.py --check      say whether an update exists, change nothing
    selfupdate.py --notice     KEY=VALUE lines for the status board

The exit status is 0 when nothing needed doing or the update went
through, and 1 when it refused or could not reach GitHub. --notice
always exits 0.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

REPO_URL = "https://github.com/Lampsdad/Local-LLM-setup-for-Cursor-IDE"
REMOTE = "origin"
BRANCH = "main"
CHANNELS = ("release", "main")
DEFAULT_CHANNEL = "release"
# Releases are tagged v1.2.3. Anything else (v2-beta, a test tag) is
# not a release and is never installed.
RELEASE_TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")

CHECK_EVERY = 24 * 3600    # seconds between status-board checks
CHECK_TIMEOUT = 5          # the board waits no longer than this
FETCH_TIMEOUT = 300
CACHE_NAME = "kiln-update-check.json"
SHOW_COMMITS = 20

# The command a user types differs by platform. This is only used to
# print the next step.
KILN = "kiln" if os.name == "nt" else "./kiln.sh"


class Refused(Exception):
    """The checkout cannot be updated safely. The message says why."""


def say(*lines):
    for line in lines:
        print((" " + line) if line else "")


# ---- git ----------------------------------------------------

def run(root, *args, timeout=None):
    env = dict(os.environ)
    # Never stop to ask for a password: a prompt nobody can see is a
    # hang, and on the status board it would hang every render.
    env["GIT_TERMINAL_PROMPT"] = "0"
    try:
        return subprocess.run(
            ["git", "-C", root] + list(args), env=env,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, encoding="utf-8", errors="replace",
            timeout=timeout)
    except FileNotFoundError:
        raise Refused("git is not installed, or is not on PATH.")
    except subprocess.TimeoutExpired:
        raise Refused("git %s gave no answer in %d seconds. "
                      "Is GitHub reachable?" % (args[0], timeout))


def git(root, *args, timeout=None):
    """Run git in root and return its stdout, or raise Refused."""
    p = run(root, *args, timeout=timeout)
    if p.returncode != 0:
        raise Refused("git %s failed:\n\n%s"
                      % (args[0], p.stderr.strip() or "(no output)"))
    return p.stdout.strip()


def is_ancestor(root, a, b):
    """True when commit a is already part of b's history."""
    return run(root, "merge-base", "--is-ancestor", a, b).returncode == 0


def describe(root, ref="HEAD"):
    """'v1.1.0' at a release, 'v1.1.0 + 3 commits, 1a2b3c4' past one."""
    p = run(root, "describe", "--tags", "--long", "--match", "v[0-9]*", ref)
    m = re.match(r"^(.+)-(\d+)-g([0-9a-f]+)$", p.stdout.strip())
    if p.returncode == 0 and m:
        tag, n, sha = m.group(1), int(m.group(2)), m.group(3)
        if n == 0:
            return tag
        return "%s + %d commit%s, %s" % (tag, n, "" if n == 1 else "s", sha)
    return git(root, "rev-parse", "--short", ref)


def newest_release(tags):
    best = None
    for tag in tags:
        m = RELEASE_TAG.match(tag)
        if m:
            key = tuple(int(x) for x in m.groups())
            if best is None or key > best[0]:
                best = (key, tag)
    return best[1] if best else None


def get_channel(root):
    p = run(root, "config", "--get", "kiln.channel")
    channel = p.stdout.strip()
    return channel if channel in CHANNELS else DEFAULT_CHANNEL


def channel_text(channel):
    if channel == "main":
        return "every change on main"
    return "releases"


# ---- preconditions ------------------------------------------

def same_path(a, b):
    return (os.path.normcase(os.path.realpath(a))
            == os.path.normcase(os.path.realpath(b)))


def require_clone(root):
    p = run(root, "rev-parse", "--show-toplevel")
    # Also refused: a ZIP unpacked inside some other repository, whose
    # history is not kiln's.
    if p.returncode != 0 or not same_path(p.stdout.strip(), root):
        raise Refused(
            "This copy of kiln was not installed with git clone, so there\n"
            "is no history to update from. Clone it fresh:\n"
            "\n"
            "    git clone %s\n"
            "\n"
            "then move models/, llama-bin/ and api_key.txt into the new\n"
            "folder so nothing has to be downloaded again." % REPO_URL)
    if run(root, "remote", "get-url", REMOTE).returncode != 0:
        raise Refused("This clone has no '%s' remote to update from.\n"
                      "Add it:  git remote add %s %s"
                      % (REMOTE, REMOTE, REPO_URL))


def require_main(root):
    p = run(root, "symbolic-ref", "--quiet", "--short", "HEAD")
    branch = p.stdout.strip()
    if p.returncode != 0:
        raise Refused(
            "HEAD is detached, because a commit was checked out directly,\n"
            "so there is no branch to move. Get back onto main first:\n"
            "\n"
            "    git switch %s" % BRANCH)
    if branch != BRANCH:
        raise Refused(
            "This checkout is on branch '%s', not %s. Only %s is updated,\n"
            "so your branch is left alone. Switch first:\n"
            "\n"
            "    git switch %s" % (branch, BRANCH, BRANCH, BRANCH))


def require_clean(root):
    dirty = git(root, "status", "--porcelain", "--untracked-files=no")
    if dirty:
        raise Refused(
            "These tracked files have local edits that an update would\n"
            "overwrite:\n"
            "\n%s\n"
            "\n"
            "Set them aside, update, then bring them back:\n"
            "\n"
            "    git stash\n"
            "    %s self-update\n"
            "    git stash pop"
            % ("\n".join("    " + line for line in dirty.splitlines()), KILN))


# ---- what an update would move to ---------------------------

def remote_target(root, channel, timeout):
    """(label, commit) as GitHub has it now. Reads refs only, fetches nothing."""
    out = git(root, "ls-remote", REMOTE, "refs/heads/" + BRANCH,
              "refs/tags/v*", timeout=timeout)
    refs = {}
    for line in out.splitlines():
        sha, _, name = line.partition("\t")
        refs[name] = sha
    if channel == "main":
        sha = refs.get("refs/heads/" + BRANCH)
        return (BRANCH, sha) if sha else (None, None)
    tags = [n[len("refs/tags/"):] for n in refs
            if n.startswith("refs/tags/") and not n.endswith("^{}")]
    tag = newest_release(tags)
    if tag is None:
        return None, None
    # An annotated tag lists the tag object and then, under ^{}, the
    # commit it points to. Only the commit can be compared with HEAD.
    name = "refs/tags/" + tag
    return tag, refs.get(name + "^{}", refs[name])


def behind(root, commit):
    """True when commit is not yet part of HEAD's history."""
    head = git(root, "rev-parse", "HEAD")
    if commit == head:
        return False
    # A commit that has not been fetched cannot be an ancestor of
    # HEAD, and merge-base reports it as not one.
    return not is_ancestor(root, commit, head)


# ---- the status-board cache ---------------------------------

def cache_path(root):
    return os.path.join(git(root, "rev-parse", "--absolute-git-dir"),
                        CACHE_NAME)


def load_cache(root):
    try:
        with open(cache_path(root), encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError, Refused):
        return {}


def save_cache(root, channel, label, commit):
    try:
        with open(cache_path(root), "w", encoding="utf-8") as fh:
            json.dump({"checked": time.time(), "channel": channel,
                       "label": label, "commit": commit}, fh)
    except (OSError, Refused):
        pass


def board_safe(text):
    # The Windows board splices this into a cmd line. Allow nothing
    # cmd treats as syntax: no % ! ^ & | < > or quotes.
    return re.sub(r"[^A-Za-z0-9 .,+_-]", "", text)


# ---- commands -----------------------------------------------

def notice(root):
    """The status-board row. Prints what it can and never fails."""
    try:
        require_clone(root)
        print("KILN_VERSION=" + board_safe(describe(root)))
        if os.environ.get("KILN_NO_UPDATE_CHECK"):
            return
        require_main(root)
        channel = get_channel(root)
        cache = load_cache(root)
        fresh = (cache.get("channel") == channel
                 and time.time() - cache.get("checked", 0) < CHECK_EVERY)
        if fresh:
            label, commit = cache.get("label"), cache.get("commit")
        else:
            try:
                label, commit = remote_target(root, channel, CHECK_TIMEOUT)
            except Refused:
                # Offline or GitHub is down. Remember that it was tried,
                # so the board does not pay the timeout on every render.
                label, commit = None, None
            save_cache(root, channel, label, commit)
        if label and commit and behind(root, commit):
            print("KILN_UPDATE=" + board_safe(label))
    except Exception:
        pass


def check(root, channel=None):
    require_clone(root)
    saved = get_channel(root)
    channel = channel or saved
    label, commit = remote_target(root, channel, 30)
    if channel == saved:
        save_cache(root, channel, label, commit)
    current = describe(root)
    say("")
    if not label:
        say("GitHub has nothing to update to on that channel yet.",
            "This checkout is on %s." % current)
    elif behind(root, commit):
        say("Update available: %s" % label,
            "This checkout is on %s." % current,
            "",
            "Run:  %s self-update%s"
            % (KILN, "" if channel == saved else " --" + channel))
    else:
        say("Up to date, following %s: %s." % (channel_text(channel), current))
    say("")
    return 0


def update(root, channel=None):
    require_clone(root)
    require_main(root)
    require_clean(root)

    say("")
    if channel and channel != get_channel(root):
        git(root, "config", "--local", "kiln.channel", channel)
        other = "--release" if channel == "main" else "--main"
        say("Following %s from now on. To switch back:  %s self-update %s"
            % (channel_text(channel), KILN, other), "")
    channel = get_channel(root)

    say("Fetching from GitHub...")
    # The target is what GitHub lists now, not the newest tag in this
    # clone. A tag deleted on GitHub, or one made here and never
    # pushed, stays in the clone and would otherwise be updated to.
    label, target = remote_target(root, channel, FETCH_TIMEOUT)
    if label is None and channel == "main":
        raise Refused("GitHub has no %s branch to update to." % BRANCH)
    if label is None:
        raise Refused("GitHub has no vX.Y.Z release to update to yet.\n"
                      "To follow main instead:  %s self-update --main" % KILN)
    # Forced (+) so a tag moved on GitHub replaces the local copy
    # instead of failing the fetch with "would clobber existing tag".
    # --no-prune, or fetch.prune=true in the user's git config deletes
    # every local tag GitHub does not have, and a tag can be the only
    # name for a commit.
    git(root, "fetch", "--quiet", "--no-tags", "--no-prune", REMOTE,
        "+refs/heads/%s:refs/remotes/%s/%s" % (BRANCH, REMOTE, BRANCH),
        "+refs/tags/*:refs/tags/*", timeout=FETCH_TIMEOUT)

    # Fresh information, so the board's next check can use it.
    save_cache(root, channel, label, target)
    head = git(root, "rev-parse", "HEAD")
    current = describe(root)

    if target == head:
        say("Up to date: %s." % current, "")
        return 0

    if is_ancestor(root, target, head):
        if channel == "release":
            say("This checkout, %s, is already past the newest" % current,
                "release, %s, so it stays where it is. To keep getting" % label,
                "changes as they land on main:",
                "",
                "    %s self-update --main" % KILN, "")
        else:
            say("Up to date: %s. It already has everything on GitHub's main."
                % current, "")
        return 0

    if not is_ancestor(root, head, target):
        local = int(git(root, "rev-list", "--count",
                        "refs/remotes/%s/%s..HEAD" % (REMOTE, BRANCH)))
        if local:
            raise Refused(
                "main has %d commit%s that GitHub does not have, and a\n"
                "fast-forward would have to drop them. See them with:\n"
                "\n"
                "    git log %s/%s..%s\n"
                "\n"
                "Move them onto a branch of their own, then point main back\n"
                "at GitHub's copy, before updating."
                % (local, "" if local == 1 else "s", REMOTE, BRANCH, BRANCH))
        raise Refused("%s is not on this checkout's history, so it cannot be\n"
                      "reached by fast-forwarding." % label)

    log = git(root, "log", "--no-decorate", "--format=%h %s",
              "HEAD.." + target).splitlines()
    say("Updating %s to %s:" % (current, label), "")
    for line in log[:SHOW_COMMITS]:
        say("  " + line)
    if len(log) > SHOW_COMMITS:
        say("  ... and %d more" % (len(log) - SHOW_COMMITS))
    say("")

    git(root, "merge", "--ff-only", "--quiet", target)

    say("Updated to %s. CHANGELOG.md says what changed." % describe(root),
        "If a server is running, restart it to pick the changes up:",
        "",
        "    %s stop" % KILN,
        "    %s start" % KILN, "")
    return 0


def main(argv=None):
    # Commit subjects are UTF-8. A Windows console that cannot show a
    # character should print a ? rather than raise mid-update.
    try:
        sys.stdout.reconfigure(errors="replace")
    except AttributeError:
        pass

    ap = argparse.ArgumentParser(
        prog="kiln self-update",
        description="Update kiln itself from GitHub.")
    channel = ap.add_mutually_exclusive_group()
    channel.add_argument("--main", dest="channel", action="store_const",
                         const="main",
                         help="follow every change on main from now on")
    channel.add_argument("--release", dest="channel", action="store_const",
                         const="release",
                         help="follow tagged releases from now on (default)")
    ap.add_argument("--check", action="store_true",
                    help="say whether an update exists, change nothing")
    ap.add_argument("--notice", action="store_true", help=argparse.SUPPRESS)
    args = ap.parse_args(argv)

    if args.notice:
        notice(ROOT)
        return 0
    try:
        if args.check:
            return check(ROOT, args.channel)
        return update(ROOT, args.channel)
    except Refused as e:
        say("")
        for line in str(e).splitlines():
            say(line)
        say("")
        return 1


if __name__ == "__main__":
    sys.exit(main())
