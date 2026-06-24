#!/usr/bin/env python3
"""Validate the YAML files that flow between the stack-it pipeline skills.

Two shapes are validated:

  slots  -- output of identify-stack-slots / input to decide-stack
  stack  -- output of decide-stack / input to install-stack, scaffold-and-verify,
            document-stack

Usage:
    python validate_yaml.py --stage slots path/to/slots.yaml
    python validate_yaml.py --stage stack path/to/stack.yaml
    python validate_yaml.py path/to/stack.yaml          # defaults to --stage stack

Exit codes:
    0  valid
    1  invalid (problems printed one per line)
    2  usage error, or the file could not be read or parsed

This is a deterministic guard so a malformed handoff fails fast instead of
breaking a later stage in a confusing way.
"""
import argparse
import sys

try:
    import yaml
except ImportError:
    sys.stderr.write(
        "PyYAML is required. Install it with: pip install pyyaml --break-system-packages\n"
    )
    sys.exit(2)


def _err(errors, msg):
    errors.append(msg)


def _nonempty_str(value):
    """A real, non-blank string. Guards against lists/dicts/numbers slipping through
    a bare truthiness check (e.g. `slot: [a, b]` is truthy but not a category name)."""
    return isinstance(value, str) and value.strip() != ""


def _check_project(doc, errors):
    project = doc.get("project")
    if not isinstance(project, dict):
        _err(errors, "top-level 'project' is missing or not a mapping")
        return
    if not _nonempty_str(project.get("description")):
        _err(errors, "project.description is missing or not a non-empty string")
    if not _nonempty_str(project.get("type")):
        _err(errors, "project.type is missing or not a non-empty string")
    if not isinstance(project.get("platforms"), list):
        _err(errors, "project.platforms must be a list")


def validate_slots(doc, errors):
    _check_project(doc, errors)
    slots = doc.get("slots")
    if not isinstance(slots, list) or not slots:
        _err(errors, "'slots' must be a non-empty list")
        return
    for i, slot in enumerate(slots):
        where = f"slots[{i}]"
        if not isinstance(slot, dict):
            _err(errors, f"{where} is not a mapping")
            continue
        if not _nonempty_str(slot.get("slot")):
            _err(errors, f"{where}.slot (the category name) must be a non-empty string")
        if not isinstance(slot.get("required"), bool):
            _err(errors, f"{where}.required must be true or false")
        if "rationale" not in slot:
            _err(errors, f"{where}.rationale is missing")
        # preference and source may be null; presence is not required.


_BAD_VERSIONS = {"latest", "*", "newest"}


def _check_version(where, version, errors):
    if version is None:
        _err(errors, f"{where}.version is missing -- versions must be pinned, not 'latest'")
    elif isinstance(version, bool) or not isinstance(version, str):
        # A bare YAML scalar like `version: 3.10` parses as the number 3.1, silently
        # changing the pin -- exactly what pinning exists to prevent. Demand a quoted
        # string so the exact version survives the YAML round-trip.
        _err(
            errors,
            f"{where}.version must be a quoted string (got {type(version).__name__} {version!r}); "
            f'an unquoted value like 3.10 is read as the number 3.1 -- quote it, e.g. "3.10"',
        )
    elif version.strip() == "":
        _err(errors, f"{where}.version is empty -- pin an exact version")
    elif version.strip().lower() in _BAD_VERSIONS:
        _err(errors, f"{where}.version is '{version}' -- pin an exact version instead")


def validate_stack(doc, errors):
    _check_project(doc, errors)
    stack = doc.get("stack")
    if not isinstance(stack, list) or not stack:
        _err(errors, "'stack' must be a non-empty list (and its order is the install order)")
        return
    for i, entry in enumerate(stack):
        where = f"stack[{i}]"
        if not isinstance(entry, dict):
            _err(errors, f"{where} is not a mapping")
            continue
        if not _nonempty_str(entry.get("slot")):
            _err(errors, f"{where}.slot must be a non-empty string")
        if not _nonempty_str(entry.get("choice")):
            _err(errors, f"{where}.choice (the chosen tool) must be a non-empty string")
        _check_version(where, entry.get("version"), errors)
        install = entry.get("install")
        if not isinstance(install, list) or not install:
            _err(errors, f"{where}.install must be a non-empty list of steps")
        else:
            for j, step in enumerate(install):
                if not _nonempty_str(step):
                    _err(errors, f"{where}.install[{j}] must be a non-empty string (got {step!r})")
        caveats = entry.get("caveats", [])
        if caveats is not None and not isinstance(caveats, list):
            _err(errors, f"{where}.caveats must be a list (use [] for none)")


VALIDATORS = {"slots": validate_slots, "stack": validate_stack}


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("path", help="Path to the YAML file to validate")
    parser.add_argument("--stage", choices=sorted(VALIDATORS), default="stack",
                        help="Which schema to validate against (default: stack)")
    args = parser.parse_args()

    try:
        with open(args.path, "r", encoding="utf-8") as fh:
            doc = yaml.safe_load(fh)
    except OSError as exc:
        print(f"cannot read {args.path}: {exc}")
        sys.exit(2)
    except yaml.YAMLError as exc:
        print(f"YAML did not parse: {exc}")
        sys.exit(2)

    if not isinstance(doc, dict):
        print("top-level document must be a mapping")
        sys.exit(1)

    errors = []
    VALIDATORS[args.stage](doc, errors)

    if errors:
        print(f"INVALID ({args.stage}): {len(errors)} problem(s)")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)

    print(f"OK: '{args.path}' is a valid '{args.stage}' document")
    sys.exit(0)


if __name__ == "__main__":
    main()
