"""
### CODE OWNERS: Kyle Baird, Shea Parkes

### OBJECTIVE:
  Write the results to the shared network location for delivery to the client

### DEVELOPER NOTES:
  <none>
"""
import json
import hashlib
from pathlib import Path
import pprint as pp
from smtplib import SMTP
from email.message import EmailMessage

LOCAL_SMTP = 'smtp.milliman.com'

SUBPATH_NETWORK_SHARE_ROOT = r":\PHI\0273NYP\NewYorkMillimanShare"

WHITELIST_CLIENT_IDS = ["0273NYP"]
FILE_EXTENSIONS_SCRAPE = [
    ".sqlite",
    ".sas7bdat",
    ".xlsx",
    ".sas7bndx",
    ".html",
    ]

# =============================================================================
# LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE
# =============================================================================




def load_params(path_param_json):
    """Return a dictionary of parameters"""
    def _wrap_json_load(path_json):
        """Returns a dictionary of a loaded JSON file"""
        with path_json.open("r") as fh_input:
            return json.load(fh_input)
    return {k: Path(v) for k, v in _wrap_json_load(path_param_json).items()}

def generate_file_checksum(path_file):
    """Get the MD5 hash of the file"""
    hsh = hashlib.md5()
    with path_file.open("rb") as f:
        for chunk in iter(lambda: f.read(128 * hsh.block_size), b''):
            hsh.update(chunk)
    return hsh.hexdigest()

if __name__ == '__main__':
    import datetime
    import shutil
    import sys
    import os
    sys.path.append(
        os.path.join(
            os.environ['USERPROFILE'],
            'HealthBI_LocalData',
            )
        )
    import healthbi_env

    CLIENT_ID = healthbi_env.META["client_id"]
    PATH_NETWORK_SHARE_ROOT = Path(healthbi_env.META['data_drive'] + SUBPATH_NETWORK_SHARE_ROOT)
    assert PATH_NETWORK_SHARE_ROOT.is_dir(), "Network share directory not available"

    if CLIENT_ID.lower() not in \
        [whitelist.lower() for whitelist in WHITELIST_CLIENT_IDS]:
        print("Client ID {} is not available for sharing".format(CLIENT_ID))
        sys.exit(0)

    POSTBOARDING_ARGS = load_params(
        Path(healthbi_env.META["path_project_data"]) / "postboarding" \
        / "postboarding_directories.json"
        )

    DELIVERABLE_FILES = {
        path_: generate_file_checksum(path_)
        for path_ in POSTBOARDING_ARGS["post050"].iterdir()
        if path_.suffix.lower() in FILE_EXTENSIONS_SCRAPE
        }

    PATH_DIR_OUTPUT = PATH_NETWORK_SHARE_ROOT / healthbi_env.META["project_id"] \
        / healthbi_env.META["deliverable_name"] \
        / datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S")
    PATH_DIR_OUTPUT.mkdir(parents=True)

    print(
        "Promoting {} files to network share location:\n\n{}".format(
            len(DELIVERABLE_FILES),
            str(PATH_DIR_OUTPUT)
            )
        )
    PATH_FILE_TRIGGER = PATH_DIR_OUTPUT / "PRM_Analytics.trg"
    with PATH_FILE_TRIGGER.open("w") as fh_trg:
        fh_trg.write('filename~md5\n')
        for path_, hash_ in DELIVERABLE_FILES.items():
            print("Promoting {}...".format(path_.name))
            shutil.copy(str(path_), str(PATH_DIR_OUTPUT))
            fh_trg.write("{}~{}\n".format(path_.name, hash_))

    print('\nSending notification email to interested parties.\n')
    msg = EmailMessage()
    msg['Subject'] = 'PRM Notification: New {}-{} Comparator Report Data Mart Available'.format(
        healthbi_env.META["project_id"],
        healthbi_env.META["deliverable_name"],
        )
    msg['From'] = 'prm.operations@milliman.com'
    with (PATH_NETWORK_SHARE_ROOT / 'email_notification_list.txt').open() as fh_notify_list:
        msg['To'] = ', '.join(fh_notify_list.readlines()).replace('\n', '')
    msg.set_content(
        'A new comparator reporting datamart is available here:\n{dir_root}\n\n'
        'Output files (and their MD5 values) include:\n{list_files}\n\n'
        'Major project level metadata includes:\n{project_meta}\n\n'
        '\n'.format(
            dir_root=PATH_DIR_OUTPUT,
            list_files=pp.pformat({
                p.name: k
                for p, k in DELIVERABLE_FILES.items()
                }),
            project_meta=pp.pformat({
                k: v
                for k, v in healthbi_env.META.items()
                if not isinstance(k, tuple) and not isinstance(v, (list, dict))
                })
            )
        )

    with SMTP(LOCAL_SMTP) as smtp:
        smtp.send_message(msg)
