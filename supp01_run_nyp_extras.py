"""
||| CODE OWNERS: <At least 2 names.>
||| OBJECTIVE:
  <What and WHY.>
||| DEVELOPER NOTES:
  <What future developers need to know.>
"""
import logging
import json
import subprocess

import prm.meta.project

from indypy.file_utils import IndyPyPath

LOGGER = logging.getLogger(__name__)
PRM_META = prm.meta.project.parse_project_metadata()


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


def main() -> int:
    """A function to enclose the execution of business logic."""
    LOGGER.info('About to do something awesome.')

    POSTBOARDING_ARGS = load_params(
        PRM_META["path_project_data"] / "postboarding" \
        / "postboarding_directories.json"
        )

    post60_supps = sorted(POSTBOARDING_ARGS['post060'].collect_files_regex('Supp\d{3}'))
    for post60 in post60_supps:
        check = subprocess.run(['sas', str(post60)])
        if check:
            raise RuntimeError("%s failed" % str(post60))

    post70_supps = sorted(POSTBOARDING_ARGS['post070'].collect_filex_regex('Supp\d{3}'))
    for post70 in post70_supps:
        check = subprocess.run(['sas', str(post70)])
        if check:
            raise RuntimeError("%s failed" % str(post70))

    return 0


if __name__ == '__main__':
    # pylint: disable=wrong-import-position, wrong-import-order, ungrouped-imports
    import sys
    import prm.utils.logging_ext

    prm.utils.logging_ext.setup_logging_stdout_handler()

    RETURN_CODE = main()

    sys.exit(RETURN_CODE)
