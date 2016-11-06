"""
### CODE OWNERS: Aaron Burgess
### OBJECTIVE:
  Run NYP extras upon client request and/or payment
### DEVELOPER NOTES:
  <none>
"""
import logging
import json
import hashlib
import typing
from datetime import datetime
import shutil
import sys
import pprint as pp
import subprocess

import prm.meta.project
from prmclient.client_functions import send_email
from indypy.file_utils import IndyPyPath

LOGGER = logging.getLogger(__name__)
PRM_META = prm.meta.project.parse_project_metadata()
CLIENT_ID = PRM_META["client_id"]

_TEST_PROJECT_PATH = str(PRM_META['path_project_received'])

_TEST_RUN_INDICATOR = False if _TEST_PROJECT_PATH.find('0273NYP') > -1 \
                        and _TEST_PROJECT_PATH.find('5-Support_Files') > -1 else True

SUBPATH_NETWORK_SHARE_ROOT = r":\PHI\0273NYP\NewYorkMillimanShare" if not _TEST_RUN_INDICATOR else r":\PHI\0273NYP\TestShare"

PATH_NETWORK_SHARE_ROOT = IndyPyPath(PRM_META['data_drive'] + SUBPATH_NETWORK_SHARE_ROOT) \
                            if not _TEST_RUN_INDICATOR \
                            else IndyPyPath("K" + SUBPATH_NETWORK_SHARE_ROOT)

WHITELIST_CLIENT_IDS = ["0273NYP"]
FILE_EXTENSIONS_SCRAPE = [
    ".sqlite",
    ".sas7bdat",
    ".xlsx",
    ".sas7bndx",
    ".html",
    ".txt"
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
    return {k: IndyPyPath(v) for k, v in _wrap_json_load(path_param_json).items()}


def generate_file_checksum(path_file):
    """Get the MD5 hash of the file"""
    hsh = hashlib.md5()
    with path_file.open("rb") as f:
        for chunk in iter(lambda: f.read(128 * hsh.block_size), b''):
            hsh.update(chunk)
    return hsh.hexdigest()


def _get_deliverable_files(postboarding_folder: str, postboarding_config: dict) -> typing.Dict[IndyPyPath, str]:
    """
    Acquires files and checksums for those files from a given postboarding module

    Args:
        postboarding_folder (str): String reference to postboarding folder name (e.g. post060)

    Returns:
        Dictionary with files (IndyPyPath) as keys and checksum as values
    """
    return {
        path_: generate_file_checksum(path_)
        for path_ in postboarding_config[postboarding_folder].iterdir()
        if path_.suffix.lower() in FILE_EXTENSIONS_SCRAPE
        }


def _generate_directories(drive: IndyPyPath) -> typing.Dict[str, IndyPyPath]:
    """
    Generate the appropriate directories for delivery

    Args:
        drive (IndyPyPath): IndyPyPath representation of delivery drive

    Returns:
        Dict with string representation of deliverable with it's respective output directory as an
        IndyPyPath object

    """
    deliverable_path_parent = drive / PRM_META['project_id'] / PRM_META['deliverable_name'] / \
                     datetime.now().strftime("%Y-%m-%d_%H%M%S")
    deliverable_path_parent.mkdir(parents=True)

    supplemental_path = deliverable_path_parent / 'Supplemental Datamart'
    supplemental_path.mkdir()

    return {
            'deliverable_root': deliverable_path_parent,
            'supplemental': supplemental_path,
            }


def main() -> int:
    """A function to enclose the execution of business logic."""
    LOGGER.info('Collecting postboarding information')

    POSTBOARDING_ARGS = load_params(
        PRM_META["path_project_data"] / "postboarding" \
        / "postboarding_directories.json"
        )

    LOGGER.info('Running Post070 supps...')
    post070_path = IndyPyPath(__file__).parent / 'Post070_Supplemental_Datamart'
    post70_supps = post070_path.collect_files_regex('Supp\d{''3}')
    for post70 in post70_supps:
        subprocess.run(['sas', str(post70)], check=True)
    LOGGER.info('Post070 runs complete')

    assert PATH_NETWORK_SHARE_ROOT.is_dir(), "Network share directory not available"

    if CLIENT_ID.lower() not in \
        [whitelist.lower() for whitelist in WHITELIST_CLIENT_IDS]\
            and not _TEST_RUN_INDICATOR:
        print("Client ID {} is not available for sharing".format(CLIENT_ID))
        sys.exit(0)

    POSTBOARDING_ARGS = load_params(
        PRM_META["path_project_data"] / "postboarding" \
        / "postboarding_directories.json"
        )

    DELIVERABLE_SUPPLEMENTAL = _get_deliverable_files('post070', POSTBOARDING_ARGS)

    file_count = DELIVERABLE_SUPPLEMENTAL

    directories = _generate_directories(PATH_NETWORK_SHARE_ROOT)

    deliverable_mapping = {'supplemental': DELIVERABLE_SUPPLEMENTAL}

    print(
        "Promoting {} files to network share location:\n\n{}".format(
            file_count,
            str(directories['deliverable_root'])
        )
    )

    all_files_super_dict = {}
    PATH_FILE_TRIGGER = directories['deliverable_root'] / "PRM_Analytics.trg"
    with PATH_FILE_TRIGGER.open("w") as fh_trg:
        fh_trg.write('filename~md5\n')
        for deliverable_name, delivery_files in deliverable_mapping.items():
            for path_, hash_ in delivery_files.items():
                all_files_super_dict[path_] = hash_
                print("Promoting {}...".format(path_.name))
                shutil.copy(str(path_), str(directories[deliverable_name]))
                fh_trg.write("{}~{}\n".format(path_.name, hash_))

    subject = 'PRM Notification: New {}-{} Supplemental Data Mart Available'.format(
        PRM_META["project_id"],
        PRM_META["deliverable_name"],
    )

    sender = 'prm.operations@milliman.com'

    with (PATH_NETWORK_SHARE_ROOT / 'email_notification_list.txt').open() as fh_notify_list:
        recipients = ', '.join(fh_notify_list.readlines()).replace('\n', '')

    body = """A new comparator reporting datamart is available here:\n{dir_root}\n\n
        Output files (and their MD5 values) include:\n{list_files}\n\n
        Major project level metadata includes:\n{project_meta}\n\n
        \n""".format(
            dir_root=directories['deliverable_root'],
            list_files=pp.pformat({
                p.name: k
                for p, k in all_files_super_dict.items()
                }),
            project_meta=pp.pformat({
                k: v
                for k, v in PRM_META.items()
                if not isinstance(k, tuple) and not isinstance(v, (list, dict))
                })
            )

    send_email(sender, recipients, subject, body)

    return 0


if __name__ == '__main__':
    # pylint: disable=wrong-import-position, wrong-import-order, ungrouped-imports
    import sys
    import prm.utils.logging_ext

    prm.utils.logging_ext.setup_logging_stdout_handler()

    RETURN_CODE = main()

    sys.exit(RETURN_CODE)
