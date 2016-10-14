"""
### CODE OWNERS: Aaron Burgess, Jason Altieri
### OBJECTIVE:
  Move CCLF files from received to NYP Share
### DEVELOPER NOTES:
  <None>
"""
import logging
import typing
from collections import defaultdict
import shutil

import prm.meta.project
from indypy.file_utils import IndyPyPath

LOGGER = logging.getLogger(__name__)
PRM_META = prm.meta.project.parse_project_metadata()

_TEST_PROJECT_PATH = str(PRM_META['path_project_received'])

_TEST_RUN_INDICATOR = False if _TEST_PROJECT_PATH.find('0273NYP') > -1 \
                        and _TEST_PROJECT_PATH.find('5-Support_Files') > -1 else True

SUBPATH_NETWORK_SHARE_ROOT = r":\PHI\0273NYP\NewYorkMillimanShare" if not _TEST_RUN_INDICATOR else r":\PHI\0273NYP\TestShare"

PATH_NETWORK_SHARE_ROOT = IndyPyPath(PRM_META['data_drive'] + SUBPATH_NETWORK_SHARE_ROOT) \
                            if not _TEST_RUN_INDICATOR \
                            else IndyPyPath("K" + SUBPATH_NETWORK_SHARE_ROOT)


# =============================================================================
# LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE
# =============================================================================

def _create_dict_by_date(file_list: typing.List[IndyPyPath]) -> typing.Dict[str, typing.List[IndyPyPath]]:
    """
    Creates a dictionary with datestamp str from CCLF files as keys and list of IndyPyPath

    Args:
        file_list: List of IndyPyPath objects

    Returns:
        Dictionary with datestamp string as key and list of IndyPyPath as values
    """
    file_dict = defaultdict(list)
    for file in file_list:
        date = file.stem.split('.')[-1][1:]
        file_dict[date].append(file)
    return file_dict


def _file_check(list_of_files: typing.List[IndyPyPath], date_path: IndyPyPath) -> typing.List[typing.Optional[IndyPyPath]]:
    """
    Compares files to copy relative to existing files and returns difference

    Args:
        list_of_files: List of IndyPyPath objects
        date_path: IndyPyPath directory

    Returns:
        Difference of existing and new files
    """
    all_date_files = [file for file in date_path.iterdir()]
    return list(set(list_of_files) ^ set(all_date_files))


def _create_dirs_and_move_files(file_dict: typing.Dict[str, typing.List[IndyPyPath]]):
    """
    Creates appropriate directories and moves files in

    Args:
        file_dict: Dict with datestamp string as key and list of IndyPyPath objects as value

    """
    output_directory = PATH_NETWORK_SHARE_ROOT / PRM_META['project_id'] / '_CCLF'
    if not output_directory.exists():
        output_directory.mkdir(parents=True)

    for date, list_of_files in file_dict.items():
        date_path = output_directory / date
        files_to_write = list_of_files
        if date_path.exists():
            files_to_write = _file_check(list_of_files, date_path)
        else:
            date_path.mkdir()
        for file in files_to_write:
            shutil.copy(str(file), str(date_path))


def main() -> int:
    """A function to enclose the execution of business logic."""
    all_cclf = PRM_META['path_project_received'].collect_files_regex('ACO\.CCLF')
    file_dict = _create_dict_by_date(all_cclf)
    _create_dirs_and_move_files(file_dict)

    return 0


if __name__ == '__main__':
    # pylint: disable=wrong-import-position, wrong-import-order, ungrouped-imports
    main()
