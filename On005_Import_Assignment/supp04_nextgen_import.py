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
import typing
from collections import namedtuple
from operator import attrgetter
from bs4 import BeautifulSoup
from xlrd import XLRDError

import pyspark.sql.functions as F
from pyspark.sql import DataFrame, Row

import prm.meta.project
from prm.spark.app import SparkApp
from prmclient.spark.spark_utils import append_df
from prmclient.client_functions import process_excel_sheet_to_pandas

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


def _find_delimiter(path: IndyPyPath, delim_list: list) -> str:
    """

    Args:
        path: IndyPyPath to text file
        delim_list: List of possible delimiters

    Returns:


    """
    with path.open() as file:
        header = file.readline()
    path_delim_object = namedtuple('path_delim_object', ['delim', 'count'])
    delim_count = [path_delim_object(delim, header.count(delim)) for delim in delim_list]
    max_delim = sorted(delim_count, key=attrgetter('count'), reverse=True)[0]
    delim_obj = attrgetter('delim')
    count_obj = attrgetter('count')
    if count_obj(max_delim) < 1:
        raise AssertionError('The delimiter could not be determined from the delim list.')
    return delim_obj(max_delim)


def _load_ngalign_files(sparkapp: SparkApp, file_list: list, delim_list: list) -> DataFrame:
    """

    Args:
        sparkapp:   sparkapp reference to call read.csv
        file_list:  list of ngalign files to load
        delim_list: list of potential delimiters for NGALIGN files

    Returns:
        DataFrame with stacked NGALIGN files tagged by date
    """
    ngalign_df = None
    for file in file_list:
        date = re.findall(r'D\d{6}', str(file))[0][1:]
        delim = _find_delimiter(file, delim_list)
        import_df = sparkapp.session.read.csv(str(file),
                                              sep=delim,
                                              header=True
                                              )
        if not ngalign_df:
            ngalign_df = import_df.withColumn('filedate', F.lit(date))
        else:
            align_with_date_df = import_df.withColumn('filedate', F.lit(date))
            ngalign_df = append_df(ngalign_df, align_with_date_df)

    return ngalign_df.select([F.col(name).alias(name.lower().strip().replace(' ', '_')) for name in
                              ngalign_df.columns])


def _process_excel_mngreb_files(
        sparkapp: SparkApp,
        file_path: IndyPyPath,
        file_config: dict
) -> typing.Union[DataFrame, None]:
    """

    Args:
        sparkapp: SparkApp to create Spark DataFrame from a pandas DataFrame
        file_path:  IndyPyPath
        file_config: dictionary with parameters for the process_excel_sheet_to_pandas call
                     (sheet_name, header_hints) and final headers for import to spark

    Returns:
        Spark DataFrame

    """
    sheet = file_config['sheet']
    header_hint = file_config['header_hints']
    pd_df = process_excel_sheet_to_pandas(file_path, sheet, header_hints=header_hint)
    return sparkapp.session.createDataFrame(pd_df)


def _sniff_xml_header(parsed_xml: BeautifulSoup, header_hints: list):
    """

    Args:
        parsed_xml:
        header_hints:

    Returns:

    """
    n = 0
    header_row = False
    for row in parsed_xml.findAll('tr'):
        columns = [x.contents[0] if x.contents else None for x in row.findAll('td')]
        if set(header_hints).issubset(set(columns)):
            return n, columns
        n += 1
    if not header_row:
        raise AssertionError("Headers were not found in the xml")


def _process_xml_mngreb_files(sparkapp: SparkApp, file_path: IndyPyPath,
                              file_config: dict) -> DataFrame:
    """

    Args:
        file_path:
        file_config:

    Returns:

    """
    header_hints = file_config['header_hints']
    with file_path.open() as xml_path:
        soup = BeautifulSoup(xml_path, "lxml")
    header_row, headers = _sniff_xml_header(parsed_xml=soup, header_hints=header_hints)
    rdd_list = []
    for n, row in enumerate(soup.findAll('tr')):
        columns = [x.contents[0] if x.contents else None for x in row.findAll('td')]
        if n > header_row:
            if any(columns):
                zip_values = zip(headers, columns)
                value_dict = {key: value.strip() for key, value in zip_values}
                rdd_row = Row(**value_dict)
                rdd_list.append(rdd_row)
            else:
                break
    return sparkapp.session.createDataFrame(rdd_list)


def _load_mngreb_files(sparkapp: SparkApp, file_list: list, file_config: dict) -> DataFrame:
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
        if file.suffix == '.csv':
            pd_df = _process_csv_mngreb_files(file, file_config)
        else:
            try:
                pd_df = _process_excel_mngreb_files(sparkapp, file, file_config)
            except XLRDError:
                pd_df = _process_xml_mngreb_files(sparkapp, file, file_config)

        loaded_df = sparkapp.session.createDataFrame(pd_df)
        for column in loaded_df.columns:
            loaded_df = loaded_df.withColumn(column, F.when(F.col(column) == F.lit('nan'),
                                                                 F.lit(None)).otherwise(F.col(
                column)))
        if not mngreb_df:
            mngreb_df = loaded_df.withColumn('filedate', F.lit(date))
        else:
            mngreb_with_date_df = loaded_df.withColumn('filedate', F.lit(date))
            mngreb_df = append_df(mngreb_df, mngreb_with_date_df, de_dup=True)
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

    possible_delimiters = ['\t', ',', '|']

    LOGGER.info('Loading NGALIGN files')
    ngalign_list = _REFERENCES.collect_files_regex('NGALIGN')
    alignment_df = _load_ngalign_files(sparkapp, ngalign_list, possible_delimiters)

    LOGGER.info('Loading MNGREB files')
    mngreb_list = _REFERENCES.collect_files_regex('MNGREB')
    mngreb_df = _load_mngreb_files(sparkapp, mngreb_list, _HEADER_LIST, possible_delimiters)

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
