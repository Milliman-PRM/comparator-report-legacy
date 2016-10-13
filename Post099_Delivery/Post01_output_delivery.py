"""
### CODE OWNERS: Aaron Burgess
### OBJECTIVE:
  Generate deliverable directory structure for NYP and copy appropriate deliverables to the corresponding
  delivery folder
### DEVELOPER NOTES:
  <None>
"""
import logging
import json
import hashlib

import prm.meta.project
from prmclient.client_functions import send_email
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


def generate_file_checksum(path_file):
    """Get the MD5 hash of the file"""
    hsh = hashlib.md5()
    with path_file.open("rb") as f:
        for chunk in iter(lambda: f.read(128 * hsh.block_size), b''):
            hsh.update(chunk)
    return hsh.hexdigest()

def main() -> int:
    """A function to enclose the execution of business logic."""
    LOGGER.info('About to do something awesome.')

    return 0


if __name__ == '__main__':
    # pylint: disable=wrong-import-position, wrong-import-order, ungrouped-imports
    import sys
    import prm.utils.logging_ext
    import prm.spark.defaults_prm

    prm.utils.logging_ext.setup_logging_stdout_handler()
    SPARK_DEFAULTS_PRM = prm.spark.defaults_prm.get_spark_defaults(PRM_META)

    with SparkApp(PRM_META['pipeline_signature'], **SPARK_DEFAULTS_PRM):
        RETURN_CODE = main()

    sys.exit(RETURN_CODE)