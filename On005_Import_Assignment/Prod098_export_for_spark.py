"""
### CODE OWNERS: Chas Busenburg

### OBJECTIVE:
    Convert all .sas files for module to .parquet

### DEVELOPER NOTES:
    <none>
"""
import logging

import prm.meta.project
from prm.spark.app import SparkApp
from prm.meta.output_datamart import DataMart

LOGGER = logging.getLogger(__name__)
PRM_META = prm.meta.project.parse_project_metadata()

# =============================================================================
# LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE
# =============================================================================



def main() -> int:
    """A function to enclose the execution of business logic."""
    LOGGER.info('Ensuring Parquet files are written for %s', PRM_META[(18,"out")])
    sparkapp = SparkApp(PRM_META['pipeline_signature'])

    dm_references_client = DataMart("references_client")
    dm_references_client.ensure_parquet(sparkapp, PRM_META[(18, "out")])

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
