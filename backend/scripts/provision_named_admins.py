"""Secure, idempotent provisioning script for PharmaTrace Platform Administrators.

Usage:
    # 1. Provision from untracked JSON config file (e.g. backend/data/admin_provision.json):
    python scripts/provision_named_admins.py --config backend/data/admin_provision.json

    # 2. Or provision a single administrator interactively or via CLI:
    python scripts/provision_named_admins.py --name "Lekshmy" --username admin_L --email admin_L@gmail.com --password adminLekshmy
"""
import argparse
import json
import os
import sys
from pathlib import Path

backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from services import auth  # noqa: E402


def provision_accounts_from_list(accounts: list[dict]) -> list[dict]:
    results = []
    for acct in accounts:
        name = acct.get("name") or acct.get("username", "")
        username = acct.get("username", "")
        email = acct.get("email", "")
        password = acct.get("password", "")
        org_name = acct.get("org_name", "PharmaTrace Regulatory Authority")

        record, created = auth.provision_admin_account(
            username=username,
            email=email,
            password=password,
            name=name,
            org_name=org_name,
        )
        results.append({
            "name": name,
            "username": username,
            "email": email,
            "wallet": record.get("address"),
            "status": "Created" if created else "Already Existed (Preserved)",
        })
    return results


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Idempotently provision PharmaTrace Administrator accounts."
    )
    parser.add_argument(
        "--config",
        help="Path to untracked JSON file containing administrator provisioning list.",
    )
    parser.add_argument("--name", help="Administrator display name")
    parser.add_argument("--username", help="Administrator username")
    parser.add_argument("--email", help="Administrator email address")
    parser.add_argument("--password", help="Administrator password")

    args = parser.parse_args()

    config_path = args.config
    if not config_path:
        default_data_config = backend_dir / "data" / "admin_provision.json"
        if default_data_config.is_file():
            config_path = str(default_data_config)

    accounts_to_provision = []

    if config_path:
        p = Path(config_path)
        if not p.is_file():
            print(f"Error: Config file not found at {p}", file=sys.stderr)
            return 1
        try:
            raw = p.read_text(encoding="utf-8")
            data = json.loads(raw)
            if isinstance(data, list):
                accounts_to_provision = data
            elif isinstance(data, dict) and "administrators" in data:
                accounts_to_provision = data["administrators"]
            else:
                print("Error: Config JSON must be a list of accounts or object with 'administrators' key.", file=sys.stderr)
                return 1
        except Exception as exc:
            print(f"Error reading config JSON: {exc}", file=sys.stderr)
            return 1
    elif args.username and args.email and args.password:
        accounts_to_provision = [{
            "name": args.name or args.username,
            "username": args.username,
            "email": args.email,
            "password": args.password,
        }]
    else:
        print("Error: Provide --config <file> or --username, --email, and --password.", file=sys.stderr)
        return 1

    try:
        results = provision_accounts_from_list(accounts_to_provision)
        print("Administrator Provisioning Summary:")
        print("-" * 65)
        for r in results:
            print(f"  [{r['status']}] {r['name']} ({r['username']} | {r['email']}) -> {r['wallet']}")
        print("-" * 65)
        print(f"Successfully processed {len(results)} administrator account(s).")
        return 0
    except Exception as exc:
        print(f"Provisioning error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
