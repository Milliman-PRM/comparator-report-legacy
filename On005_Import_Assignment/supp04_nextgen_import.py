"""
### CODE OWNERS: Jason Altieri

### OBJECTIVE:
  Create client_member and client_member_time for NextGen ACOs

### DEVELOPER NOTES:
  NGALIGN file should be pipe delimited text. MNGREB should be .xlsx or .csv
"""
import logging
import re
import pandas as pd
import pyspark.sql.functions as F
from pyspark.sql import DataFrame


import prm.meta.project
from prm.spark.app import SparkApp
from prmclient.spark.spark_utils import append_df
from prmclient.client_functions import process_excel_files_to_pandas

from indypy.file_utils import IndyPyPath

LOGGER = logging.getLogger(__name__)
PRM_META = prm.meta.project.parse_project_metadata()

_REFERENCES = PRM_META['path_project_received_ref']
_HEADER_LIST = ['HICNO', 'First Name',
                'Last Name', 'Reason for Exclusion']
_FIELD_NAMES = ['hicno', 'not_applicable', 'first_name', 'last_name', 'address', 'address2',
                'address3', 'address4', 'address5', 'address6', 'address7', 'address8', 'state',
                'zip_code', 'gender', 'birth_date', 'date_of_exclusion', 'exclusion_reason']

# =============================================================================
# LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE
# =============================================================================


def _load_ngalign_files(sparkapp: SparkApp, file_list: list) -> DataFrame:
    """

    Args:
        sparkapp:   sparkapp reference to call read.csv
        file_list:  list of ngalign files to load

    Returns:
        DataFrame with stacked NGALIGN files tagged by date
    """
    ngalign_df = None
    for file in file_list:
        date = re.findall(r'D\d{6}', str(file))[0][1:]
        import_df = sparkapp.session.read.csv(str(file),
                                              sep='|',
                                              header=True
                                              )
        if not ngalign_df:
            ngalign_df = import_df.withColumn('filedate', F.lit(date))
        else:
            align_with_date_df = import_df.withColumn('filedate', F.lit(date))
            ngalign_df = append_df(ngalign_df, align_with_date_df)

    return ngalign_df.select([F.col(name).alias(name.lower().strip().replace(' ', '_')) for name in
                              ngalign_df.columns])


def _load_mngreb_files(sparkapp: SparkApp, file_list: list, file_config: list) -> DataFrame:
    """

    Args:
        sparkapp:   sparkapp reference to call read.csv
        file_list:  list of ngalign files to load

    Returns:
        DataFrame of stacked MNGREB files tagged by date
    """
    mngreb_df = None
    for file in file_list:
        date = re.findall(r'D\d{6}', str(file))[0][1:]
        read_dict = process_excel_files_to_pandas(
            file,
            mssp_flag=False,
            header_row=1
        )
        pandas_df = [read_dict.get(key) for key in read_dict.keys()][0]
        pandas_df.columns = _FIELD_NAMES
        for field in _FIELD_NAMES:
            pandas_df[field] = pandas_df[field].astype(str)
        loaded_df = sparkapp.session.createDataFrame(pandas_df)
        for column in loaded_df.columns:
            loaded_df = loaded_df.withColumn(column, F.when(F.col(column) == F.lit('nan'),
                                                                 F.lit(None)).otherwise(F.col(
                column)))
        if not mngreb_df:
            mngreb_df = loaded_df.withColumn('filedate', F.lit(date))
        else:
            mngreb_with_date_df = loaded_df.withColumn('filedate', F.lit(date))
            mngreb_df = append_df(mngreb_df, mngreb_with_date_df)
    return mngreb_df


def _build_client_member_time(ngalign_df: DataFrame, mngreb_df: DataFrame)-> DataFrame:
    """

    Args:
        ngalign_df:    DataFrame of stacked ngalign files
        mngreb_df:     DataFrame of stacked mngreb files

    Returns:
        DataFrame with eligibility spans by member
    """
    member_exclusions_df = ngalign_df.join(mngreb_df,
                                           'hicno',
                                           'left_outer'
                                           )
    member_assign_df = member_exclusions_df.withColumn('date_start',
                                                       F.concat(F.lit('20'),
                                                                F.substring(
                                                                    F.col('filedate'), 0,
                                                                    2),
                                                                F.lit('-01-01')
                                                                ).cast('date')
                                                       ).withColumn('date_end',
                                                                    F.concat(F.lit('20'),
                                                                             F.substring(
                                                                                 F.col(
                                                                                     'filedate'),
                                                                                 0,
                                                                                 2),
                                                                             F.lit(
                                                                                 '-12-31')
                                                                             ).cast(
                                                                        'date')
                                                                    ).withColumn(
        'assignment_indicator',
        F.lit('Y')
    )


    return base_member_assign_df.select(
        F.col('hicno'),
        F.col('date_start'),
        F.col('date_end'),
        F.col('assignment_indicator'),
        F.col('mem_excluded_reason')
    )



def main() -> int:
    """A function to enclose the execution of business logic."""
    LOGGER.info('Preparing to create client member and client member time')
    sparkapp = SparkApp(PRM_META['pipeline_signature'])

    LOGGER.info('Loading NGALIGN files')
    ngalign_list = _REFERENCES.collect_files_regex('NGALIGN')
    alignment_df = _load_ngalign_files(sparkapp, ngalign_list)

    LOGGER.info('Loading MNGREB files')
    mngreb_list = _REFERENCES.collect_files_regex('MNGREB')
    mngreb_df = _load_mngreb_files(sparkapp, mngreb_list, _HEADER_LIST)

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
