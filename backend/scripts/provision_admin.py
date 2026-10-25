"""One-time CLI utility to provision the initial PharmaTrace Administrator account.

Usage:
    python scripts/provision_admin.py --username admin --email admin@example.org --password <secure_password>
"""
import argparse
import sys
from pathlib import Path

backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from services import auth  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Provision the initial PharmaTrace Administrator account (one-time setup)."
    )
    parser.add_argument("--username", required=True, help="Administrator username")
    parser.add_argument("--email", required=True, help="Administrator email address")
    parser.add_argument("--password", required=True, help="Administrator password (min 6 characters)")
    parser.add_argument(
        "--org-name",
        default="PharmaTrace Regulatory Authority",
        help="Administrator organization/authority name",
    )
    args = parser.parse_args()

    try:
        record = auth.provision_initial_admin(
            username=args.username,
            email=args.email,
            password=args.password,
            org_name=args.org_name,
        )
        print("Initial Administrator provisioned successfully:")
        print(f"  Username: {record['username']}")
        print(f"  Email:    {record['email']}")
        print(f"  Wallet:   {record['address']}")
        print(f"  Org:      {record['org_name']}")
        return 0
    except PermissionError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    except ValueError as exc:
        print(f"Validation Error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
