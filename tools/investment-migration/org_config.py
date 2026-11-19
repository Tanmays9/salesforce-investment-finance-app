"""Load local Salesforce target-org identifiers without committing them."""
from pathlib import Path
import os

_LOCAL_CONFIG_HOME = (
    Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
    if os.name == "nt"
    else Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
)
_ENV_OVERRIDE = os.environ.get("SALESFORCE_PORTFOLIO_ENV_FILE")
_ENV_FILE = (
    Path(_ENV_OVERRIDE).expanduser()
    if _ENV_OVERRIDE
    else _LOCAL_CONFIG_HOME / "SalesforceInvestmentFinanceApp" / ".env"
)
_LOADED = False


def _load_local_env():
    global _LOADED
    if _LOADED:
        return
    _LOADED = True
    if not _ENV_FILE.is_file():
        return
    for raw_line in _ENV_FILE.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        name, value = name.strip(), value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if name:
            os.environ.setdefault(name, value)


def _required(name):
    _load_local_env()
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(
            f"Missing {name}; configure it in the local environment file described in README."
        )
    return value


def org_id_for_stage(stage):
    names = {
        "production": "SALESFORCE_PRODUCTION_ORG_ID",
        "sandbox": "SALESFORCE_SANDBOX_ORG_ID",
    }
    try:
        return _required(names[stage])
    except KeyError as exc:
        raise ValueError("stage must be 'production' or 'sandbox'") from exc


def org_alias_for_stage(stage):
    names = {
        "production": "SALESFORCE_PRODUCTION_ORG_ALIAS",
        "sandbox": "SALESFORCE_SANDBOX_ORG_ALIAS",
    }
    try:
        return _required(names[stage])
    except KeyError as exc:
        raise ValueError("stage must be 'production' or 'sandbox'") from exc


def allowed_org_ids():
    return {org_id_for_stage("production"), org_id_for_stage("sandbox")}


def local_path(name):
    return Path(_required(name)).expanduser()


def aws_region():
    return _required("AWS_REGION")


def cas_auth_secret_name(stage):
    if stage not in {"sandbox", "production"}:
        raise ValueError("stage must be 'production' or 'sandbox'")
    return _required("CAS_AUTH_SECRET_NAME_TEMPLATE").format(stage=stage)
