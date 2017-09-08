"""
### CODE OWNERS: Matthew Hawthorne

### OBJECTIVE:
  Run assignment logic for MSSP and NextGen clients

### DEVELOPER NOTES:

"""
# pylint: disable=no-member
import logging
import datetime
import subprocess

import pyspark.sql.functions as F

import prm.meta.project
from prm.meta.output_datamart import DataMart
from prm.spark.app import SparkApp

from prm.spark.io_sas import read_sas_data, write_sas_data

from prmclient.mssp.next_gen_assignment import run_next_gen_assignment

from indypy.file_utils import IndyPyPath

LOGGER = logging.getLogger(__name__)
PRM_META = prm.meta.project.parse_project_metadata()
REF_CLIENT = DataMart("references_client")


# =============================================================================
# LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE
# =============================================================================

def _build_logfile_name(path_program, path_log):
    """Create a timestamped log filename"""
    _datetime_start = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    assert path_log.is_dir(), "Log directory {} not found.".format(path_log)
    return path_log / "{}_{}.log".format(path_program.stem, _datetime_start)


def _run_sas_subprocess(path_program):
    """Subprocess call to run sas program"""
    log_path = _build_logfile_name(
        path_program,
        PRM_META['path_project_logs'] / '_Onboarding' / path_program.parent.stem
    )
    program_return = subprocess.run(
        ['sas',
         '-SYSIN',
         str(path_program),
         '-log',
         str(log_path),
         '-print',
         str(log_path.with_suffix('.lst')),
         '-icon',
         '-nosplash',
         '-rsasuser'
        ]
    )
    return program_return.returncode


def collect_nextgen_reference_files(ref_path: IndyPyPath) -> dict:
    """
    Collect reference files from the references folder and organize them into a dictionary
    Args:
        ref_path: IndyPyPath to the References Folder
    Returns:
        Dictionary for each type of file in the References folder
    """
    return {
        "mngreb_files": ref_path.collect_files_regex('MNGREB'),
        "ngalign_files": ref_path.collect_files_regex('NGALIGN'),
    }


def process_mssp_assignments(sparkapp: SparkApp) -> int:
    """
    Run MSSP Assignment and join Beneficiary Exclusion
    Args:
        sparkapp: SparkApp instance for loading sas tables
    """
    mssp_assignment_path = IndyPyPath(__file__).parent / 'supp02_run_mssp_assignment.sas'
    mssp_return = _run_sas_subprocess(mssp_assignment_path)
    if mssp_return:
        raise AssertionError('MSSP Assignment failure. Please check SAS logs.')
    bene_excl_path = PRM_META[17, 'out'] / 'bene_exclusion.sas7bdat'
    if bene_excl_path.exists():
        df_client_member = read_sas_data(sparkapp, PRM_META[18, 'out'] / 'client_member.sas7bdat')
        df_bene_excl = read_sas_data(sparkapp, bene_excl_path)
        df_updated_client_member = df_client_member.join(
            df_bene_excl,
            df_client_member.member_id == df_bene_excl.HICN,
            'left_outer'
        ).withColumn(
            'mem_excluded_reason',
            F.coalesce(F.col('BeneExcReason'), F.lit(None))
        ).drop('HICN').drop('BeneExcReason')
        write_sas_data(df_updated_client_member, PRM_META[18, 'out'] / 'client_member.sas7bdat')
        df_client_member.unpersist()
        df_bene_excl.unpersist()
    LOGGER.info('Converting client reference tables to parquets')
    REF_CLIENT.ensure_parquet(sparkapp, PRM_META[18, 'out'])
    return 0


def process_nextgen_assignments(sparkapp: SparkApp, ngalign_files: list, mngreb_files: list) -> int:
    """
    Run NextGen Assignment pgoram and export dataframes to parquet and sas
    """
    next_gen_dict = run_next_gen_assignment(
        sparkapp,
        ngalign_files,
        mngreb_files,
        PRM_META,
        REF_CLIENT.generate_structtypes()
    )
    for key, value in next_gen_dict['client_dataframes'].items():
        LOGGER.info('Serializing %s to parquet and sas7bdat files', key)
        sparkapp.save_df(value, PRM_META[18, 'out'] / (key + '.parquet'))
        write_sas_data(value, PRM_META[18, 'out'] / (key + '.sas7bdat'))
    LOGGER.info('Cleaning up persisted datafames')
    for dataframe in next_gen_dict['unpersist_dataframes']:
        dataframe.unpersist()
    return 0


def main() -> int:
    """A function to enclose the execution of business logic."""
    LOGGER.info('Generating MSSP Assignments')
    sparkapp = SparkApp(PRM_META['pipeline_signature'])
    LOGGER.info('Running ShortCircuit program to load CCLF files')
    shortcircuit_path = IndyPyPath(__file__).parent / 'supp01_shortcircuit_cclf_import.sas'
    shortcircuit_return = _run_sas_subprocess(shortcircuit_path)
    if shortcircuit_return:
        raise AssertionError('ShortCircuit program failure. Please check SAS logs.')
    LOGGER.info('Checking to determine correct assignment logic')
    nextgen_dict = collect_nextgen_reference_files(PRM_META['path_project_received_ref'])
    nextgen_file_count = len(nextgen_dict['mngreb_files']) + len(nextgen_dict['ngalign_files'])
    if not nextgen_file_count:
        LOGGER.info('Running MSSP Assignment')
        return process_mssp_assignments(sparkapp)
    else:
        LOGGER.info('Running NextGen Assignment')
        return process_nextgen_assignments(
            sparkapp,
            nextgen_dict['ngalign_files'],
            nextgen_dict['mngreb_files']
        )



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

