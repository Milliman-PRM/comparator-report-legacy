"""
### CODE OWNERS: Jason Altieri, Matthew Hawthorne, Eric Hamilton

### OBJECTIVE:
  Create client_member and client_member_time for NextGen ACOs

### DEVELOPER NOTES:
  NGALIGN file should be pipe delimited text. MNGREB will likely be a xml type file saved as xls.
  This process checks first if the MNGREB file is a text file, then an excel file, and finally
  processes as an xml file if it is not an excel or text file.
"""
import logging
import re
import json
import shutil

from collections import namedtuple
from operator import attrgetter
from bs4 import BeautifulSoup
from xlrd import XLRDError
from datetime import datetime

import pyspark.sql.functions as F
from pyspark.sql import DataFrame, Row, Window
from pyspark.sql.types import StructType

import prm.meta.project
from prm.meta.output_datamart import DataMart
from prm.spark.app import SparkApp
from prmclient.spark.spark_utils import append_df, convert_string_to_date, propercase, create_member_months, remove_blank_field_labels
from prmclient.client_functions import process_excel_sheet_to_pyspark

from prm.spark.io_sas import read_sas_data
from prm.spark.spark_mocks import mock_dataframe

from indypy.file_utils import IndyPyPath

LOGGER = logging.getLogger(__name__)
PRM_META = prm.meta.project.parse_project_metadata()

_REFERENCES = PRM_META['path_project_received_ref']
_HEADER_LIST = ['HICNO', 'First Name',
                'Last Name', 'Reason for Exclusion']
_FIELD_NAMES = ['hicno', 'not_applicable', 'first_name', 'last_name', 'address', 'address2',
                'address3', 'address4', 'address5', 'address6', 'address7', 'address8', 'state',
                'zip_code', 'gender', 'birth_date', 'date_of_exclusion', 'exclusion_reason']
_NG_YEAR = {'10': 1, '11': 1, '12': 1, '01': 0, '02': 0, '03': 0}

_NA_FILL = {
    'mem_dependent_status': 'P',
    'mem_prv_id_align': 'Unknown',
    'mem_report_hier_1': 'All',
    'mem_report_hier_3': 'Not Implemented',
    'assignment_indicator': 'N'
}

_MEMBER_METADATA = {
                        'mem_prv_id_align': {'label':'Assigned Physician'},
                        'mem_report_hier_1': {'label':'All members (Hier)'},
                        'mem_report_hier_2': {'label':'Assigned Physician (Hier)'},
                        'mem_report_hier_3': {'label':'Not Implemented (Hier)'},
                        'assignment_indicator': {'label':'Assigned Patient'}
                    }

_MEMBER_TIME_METADATA = {
                            'mem_prv_id_align': {'label': 'Assigned Physician'},
                            'assignment_indicator': {'label': 'Assigned Patient'}
                        }

_PROVIDER_METADATA = {
    'prv_name': {'label': 'ACO Provider'},
    'prv_hier_1': {'label': 'Provider Primary Specialty'},
    'prv_net_hier_1': {'label': 'ACO'}
}

# =============================================================================
# LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE
# =============================================================================


def derive_performance_year(df_ngalign: DataFrame) -> str:
    """
    Derive the performance year from the ngalign files
    Args:
        df_ngalign: NGALIGN DataFrame

    Returns: String value for the performance year from the ngalign files

    """
    return df_ngalign.select(
        F.max(F.col('filedate')).alias('file_date')
    ).collect()[0]['file_date']


def derive_date_latestpaid(df_claims: DataFrame) -> datetime:
    """
    Use the CCLF1 Part A Header Claims to find the maximum paid date.
    Args:
        df_claims: CCLF1 Part A DataFrame

    Returns:
        datetime object of the date latest paid

    """
    data_thru_string = PRM_META['deliverable_name']
    data_thru_date_string = re.search("\d{6}", data_thru_string).group()
    data_thru_date = datetime.strptime(data_thru_date_string, "%Y%m")
    max_paiddate_df = df_claims.select(
        F.last_day(F.max(F.col('clm_idr_ld_dt'))).alias('max_paiddate')
    )
    data_thru_df = max_paiddate_df.withColumn(
        "data_thru_date",
        F.last_day(F.lit(data_thru_date))
    )
    return data_thru_df.select(
        F.least(F.col('max_paiddate'), F.col('data_thru_date'))
    ).collect()[0][0]


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


def _load_ngalign_files(sparkapp: SparkApp, file_list: list, delim_list: list,
                        xref_df: DataFrame) -> DataFrame:
    """

    Args:
        sparkapp:   sparkapp reference to call read.csv
        file_list:  list of ngalign files to load
        delim_list: list of potential delimiters for NGALIGN files
        xref_df: dataframe mapping old hicnos to new hicnos

    Returns:
        DataFrame with stacked NGALIGN files tagged by date
    """
    ngalign_df = None
    for file in file_list:
        LOGGER.info("Processing {}".format(file))
        date = re.findall(r'D\d{6}', str(file))[0][1:]
        month = date[2:4]
        year = '20' + str(int(date[0:2]) + _NG_YEAR[month])

        delim = _find_delimiter(file, delim_list)
        import_df = sparkapp.session.read.csv(
            str(file),
            sep=delim,
            header=True
        )
        update_fields_df = import_df.select(
            [F.col(name).alias('_'.join(name.lower().strip().split())) for name in
             import_df.columns]
        )
        joined_xref_df = update_fields_df.join(
            xref_df,
            update_fields_df.hicn_number_id == xref_df.prvs_hic_num,
            'left_outer'
        )
        hicno_update_df = joined_xref_df.withColumn(
            'hicn_number_id',
            F.coalesce(F.col('crnt_hic_num'), F.col('hicn_number_id'))
        )

        if not ngalign_df:
            ngalign_df = hicno_update_df.withColumn(
                'filedate',
                F.lit(year)
            )
        else:
            align_with_date_df = hicno_update_df.withColumn(
                'filedate',
                F.lit(year)
            )
            ngalign_df = append_df(ngalign_df, align_with_date_df, de_dup=True)

    trim_fields_df = ngalign_df.select([F.trim(F.col(field)).alias(field) for field in ngalign_df.columns])
    return trim_fields_df.withColumnRenamed('hicn_number_id', 'hicno')


def _process_csv_mngreb_files(sparkapp: SparkApp, file: IndyPyPath,
                              csv_config: dict, poss_delim: list) -> DataFrame:
    """

    Returns:

    """
    delim = _find_delimiter(file, poss_delim)
    df_init = sparkapp.session.read.csv(str(file), header=True, sep=delim)
    return df_init.select(
        [F.col(field).alias(
            csv_config['new_column'] if
            field.lower().find(csv_config['old_column']) > -1 else field
        ) for field in df_init.columns]
    )


def _process_excel_mngreb_files(
        sparkapp: SparkApp,
        file_path: IndyPyPath,
        file_config: dict
) -> DataFrame:
    """

    Args:
        sparkapp: SparkApp to create Spark DataFrame from a pandas DataFrame
        file_path:  IndyPyPath
        file_config: dictionary with parameters for the process_excel_sheet_to_pandas call
                     (sheet_name, header_hints)

    Returns:
        Spark DataFrame

    """
    sheet = file_config['sheet']
    header_hint = file_config['header_hints']
    return process_excel_sheet_to_pyspark(sparkapp, file_path, sheet, header_hints=header_hint)


def _clean_xml_file(file_path: IndyPyPath) -> IndyPyPath:
    """

    Args:
        file_path:

    Returns:

    """
    temp_dir_path = file_path.parent / 'temp'
    if not temp_dir_path.exists():
        temp_dir_path.mkdir()
    temp_file_path = temp_dir_path / file_path.name
    with file_path.open('rb') as infile:
        with temp_file_path.open('wb') as outfile:
            for line in infile:
                clean_line = line.replace(b'\x3D', b'').replace(b'\r\n', b'')
                outfile.write(clean_line)
    return temp_file_path


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
        columns = [x.contents[0] if x.contents else '_c{}'.format(n) for n, x in enumerate(row.findAll('td'))]

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
    temp_path = _clean_xml_file(file_path)
    with temp_path.open(encoding="cp1252") as xml_path:
        soup = BeautifulSoup(xml_path, "lxml")
    header_row, headers = _sniff_xml_header(parsed_xml=soup, header_hints=header_hints)

    # HICNO, First name, Last name, Addr, Date of Exclusion, Reason for Exclusion
    reduced_headers = headers[:4] + headers[8:10]
    rdd_list = []

    for n, row in enumerate(soup.findAll('tr')):
        columns = [x.contents[0] if x.contents else None for x in row.findAll('td')]
        if n > header_row:
            if any(columns):
                reduced_columns = columns[:4] + columns[13:15]
                zip_values = zip(reduced_headers, reduced_columns)
                value_dict = {key: value.strip() if value else None for key, value in zip_values}
                rdd_row = Row(**value_dict)
                rdd_list.append(rdd_row)
            else:
                break

    shutil.rmtree(str(temp_path.parent))
    return sparkapp.session.createDataFrame(rdd_list)


def _load_mngreb_files(sparkapp: SparkApp, file_list: list, file_config: dict,
                       poss_delim: list, xref_df: DataFrame) -> DataFrame:
    """

    Args:
        sparkapp:   sparkapp reference to call read.csv
        file_list:  list of ngalign files to load

    Returns:
        DataFrame of stacked MNGREB files tagged by date
    """
    mngreb_df = None
    for file in file_list:
        LOGGER.info("Processing {}".format(file))
        if file.suffix == '.csv':
            pd_df = _process_csv_mngreb_files(sparkapp, file, file_config['csv_mngreb'], poss_delim)
        else:
            try:
                pd_df = _process_excel_mngreb_files(sparkapp, file, file_config['excel_mngreb'])
            except XLRDError:
                pd_df = _process_xml_mngreb_files(sparkapp, file, file_config['xml_mngreb'])

        update_columns_df = pd_df.select(
            [F.col(field).alias('_'.join(field.lower().strip().split())) for field in pd_df.columns]
        )
        exclusion_date_df = update_columns_df.withColumn(
            'exclusion_date',
            convert_string_to_date('date_of_exclusion_(1)_(2)', 'M/d/yyyy')
        )
        agg_exclusion_df = exclusion_date_df.groupBy(
            F.year(F.col('exclusion_date')).alias('year')
        ).agg(
            F.count('*').alias('record_count')
        )
        performance_year = str(agg_exclusion_df.orderBy(
            F.col('record_count').desc()
        ).limit(1).collect()[0]['year'])

        mngreb_xref_df = update_columns_df.join(
            F.broadcast(xref_df),
            update_columns_df.hicno == xref_df.prvs_hic_num,
            'left_outer'
        )
        hicno_update_df = mngreb_xref_df.withColumn(
            'hicno',
            F.coalesce(F.col('crnt_hic_num'), F.col('hicno'))
        )

        final_selections = file_config['final_headers']

        loaded_df = hicno_update_df.select([F.trim(F.col(field)).alias(field) for field in final_selections])

        file_df = loaded_df.withColumn('file_of_origin', F.lit(str(file)))

        if not mngreb_df:
            mngreb_df = file_df.withColumn('filedate', F.lit(performance_year))
        else:
            mngreb_with_date_df = file_df.withColumn('filedate', F.lit(performance_year))
            mngreb_df = append_df(mngreb_df, mngreb_with_date_df, de_dup=True)

    file_window = Window.orderBy(F.col('filedate'), F.col('file_of_origin').desc()).partitionBy(F.col('filedate'), F.col('hicno'))
    return mngreb_df.select(
        '*',
        F.row_number().over(file_window).alias('reason_order')
    ).where(
        F.col('reason_order') == 1
    )


def build_providers(phys_df: DataFrame, npi_df: DataFrame, ref_taxonomy_df: DataFrame,
                    performance_year: str, file_config: dict) -> DataFrame:
    """

    Args:
        phys_df:
        npi_df:
        ref_taxonomy_df:
        performance_year:
        file_config:

    Returns:

    """
    phys_window = Window.partitionBy(
        F.col('cur_clm_uniq_id'), F.col('bene_hic_num'), F.col('rndrg_prvdr_npi_num')
    ).orderBy(
        F.col('cur_clm_uniq_id'), F.col('bene_hic_num'), F.col('rndrg_prvdr_npi_num')
    )

    reduced_phys_df = phys_df.withColumn(
        'potential_pcp_claim',
        F.when(
            F.sum(
                F.when(
                    F.col('clm_line_hcpcs_cd').isin(file_config['pcp_visits']) &
                    F.col('clm_prvdr_spclty_cd').isin(file_config['pcp_spec']),
                    F.lit(1)
                ).otherwise(
                    F.lit(0)
                )
            ).over(phys_window) > 0,
            F.lit(1)
        ).otherwise(
            F.lit(0)
        )
    ).where(
        F.col('clm_from_dt') >= performance_year + '-01-01'
    )

    agg_phys_df = reduced_phys_df.groupBy(
        F.col('bene_hic_num'), F.col('rndrg_prvdr_npi_num')
    ).agg(
        F.sum(F.col('potential_pcp_claim')).alias('pcp_visit_count'),
        F.max(F.col('clm_from_dt')).alias('last_service_date')
    )

    member_window = Window.partitionBy(F.col('bene_hic_num')).orderBy(F.col('bene_hic_num'), F.col('pcp_visit_count').desc(), F.col('last_service_date').desc())

    assign_phys_df = agg_phys_df.withColumn(
        'pcp_order',
        F.row_number().over(member_window)
    ).where(
        (F.col('pcp_order') == 1) & (F.col('pcp_visit_count') > 0)
    )
    reduce_npi_df = npi_df.select(
        F.col("npi_npi"),
        F.col('npi_prv_name_npi_prop').alias('prv_name'),
        F.col('npi_prv_addr_line_1_npi').alias('prv_addr_street'),
        F.split(F.col('npi_prv_addr_city_st_zip'), ',')[0].alias('prv_addr_city'),
        F.col('npi_prv_addr_state').alias('prv_addr_state'),
        F.col('npi_prv_addr_zip').alias('prv_addr_zip'),
        F.col('npi_prv_specialty').alias('prv_specialty'),
        F.col('npi_primary_taxonomy_cd').alias('prv_taxonomy_cd')
    )
    update_spec_df = reduce_npi_df.join(
        ref_taxonomy_df.select(
            F.col('taxonomy_code').alias('prv_taxonomy_cd'),
            F.col('classification').alias('prv_hier_1')
        ),
        'prv_taxonomy_cd',
        'left_outer'
    ).withColumn(
        'prv_hier_1',
        F.coalesce(F.col('prv_hier_1'), F.lit('Unknown'))
    ).drop('prv_taxonomy_cd')
    return assign_phys_df.join(
        update_spec_df,
        assign_phys_df.rndrg_prvdr_npi_num == update_spec_df.npi_npi,
        'left_outer'
    ).select(
        F.col('bene_hic_num').alias('hicno'),
        F.col('rndrg_prvdr_npi_num').alias('prv_id'),
        F.lit('NPI').alias('prv_id_name'),
        F.lit(None).alias('prv_id_alt'),
        F.lit(None).alias('prv_id_alt_name'),
        F.col('prv_name'),
        F.col('prv_addr_street'),
        F.col('prv_addr_city'),
        F.col('prv_addr_state'),
        F.col('prv_addr_zip'),
        F.col('prv_specialty'),
        F.col('prv_hier_1'),
        F.lit(None).alias('prv_hier_2'),
        F.lit(None).alias('prv_hier_3'),
        F.lit(None).alias('prv_hier_4'),
        F.lit(None).alias('prv_hier_5'),
        F.lit('ACO').alias('prv_net_hier_1'),
        F.lit(None).alias('prv_net_hier_2'),
        F.lit(None).alias('prv_net_hier_3'),
        F.lit('Y').alias('prv_net_aco_yn')
    )


def _build_client_all_member(ngalign_df: DataFrame, mngreb_df: DataFrame,
                             provider_df: DataFrame)-> DataFrame:
    """

    Args:
        ngalign_df:    DataFrame of stacked ngalign files
        mngreb_df:     DataFrame of stacked mngreb files
        provider_df:   Reduced DataFrame of the client provider table with HICNO

    Returns:
        DataFrame with eligibility spans by member
    """

    changed_filedate_mngreb_df = mngreb_df.withColumnRenamed('filedate', 'mngreb_filedate')

    member_exclusions_df = ngalign_df.join(changed_filedate_mngreb_df, 'hicno', 'left_outer')

    base_member_assign_df = member_exclusions_df.withColumn(
        'date_start',
        F.concat(
            F.when(
                F.col('mngreb_filedate').isNull(),
                F.col('filedate')
            ).otherwise(
                F.col('mngreb_filedate')
            ), F.lit('-01-01')
        ).cast('date')
    ).withColumn(
        'date_end',
        F.concat(
            F.when(
                F.col('mngreb_filedate').isNull(),
                F.col('filedate')
            ).otherwise(
                F.col('mngreb_filedate')
            ), F.lit('-12-31')
        ).cast('date')
    ).withColumn(
        'assignment_indicator',
        F.when(
            F.col('reason_for_exclusion').isNull(),
            F.lit('Y')
        ).otherwise(
            F.lit('N')
        )
    ).withColumn(
        'mem_dependent_status',
        F.lit('P')
    ).withColumn(
        'member_name',
        F.concat(
            propercase(member_exclusions_df['beneficiary_last_name']),
            F.lit(', '),
            propercase(member_exclusions_df['beneficiary_first_name'])
        )
    )

    base_member_phys_df = base_member_assign_df.join(
        provider_df.distinct(),
        'hicno',
        'left_outer'
    ).withColumn(
        'mem_prv_id_align',
        F.when(
            F.col('prv_id').isNull(),
            F.when(
                F.col('assignment_indicator').isin('Y'),
                F.lit('Unknown')
            ).otherwise(
                F.lit('Unassigned')
            )
        ).otherwise(
            F.col('prv_id')
        )
    ).withColumn(
        'mem_addr_zip',
        F.col('bene_zip_5_id')
    ).withColumn(
        'mem_addr_street',
        F.when(
            F.col('beneficiary_line_2_address').isNotNull(),
            F.concat(
                base_member_assign_df['beneficiary_line_1_address'],
                F.lit(' '),
                base_member_assign_df['beneficiary_line_2_address'],
            )
        ).otherwise(
            F.col('beneficiary_line_1_address')
        )
    ).withColumn(
        'mem_addr_city',
        propercase(base_member_assign_df['bene_city_id'])
    ).withColumn(
        'mem_report_hier_1',
        F.lit('All')
    ).withColumn(
        'mem_report_hier_3',
        F.lit('Not Implemented')
    ).withColumn(
        'mem_report_hier_4',
        F.lit(None).cast('string')
    ).withColumn(
        'mem_report_hier_5',
        F.lit(None).cast('string')
    ).withColumn(
        'mem_care_coordinator',
        F.lit(None).cast('string')
    ).withColumn(
        'riskscr_client',
        F.lit(None).cast('string')
    )

    if base_member_assign_df.count() != base_member_phys_df.count():
        raise AssertionError("The count of members does not equal the count of members after "
                             "assigning physicians. Please check that the physician table "
                             "does not have duplication.")

    return base_member_phys_df.select(
        F.col('hicno').alias('member_id'),
        F.col('mem_prv_id_align'),
        F.col('assignment_indicator'),
        F.col('date_start'),
        F.col('date_end'),
        F.col('member_name').alias('mem_name'),
        F.col('mem_dependent_status'),
        F.col('mem_addr_street'),
        F.col('mem_addr_city'),
        F.col('bene_usps_state_code_id').alias('mem_addr_state'),
        F.col('mem_addr_zip'),
        F.col('mem_report_hier_1'),
        F.coalesce(F.col('prv_name'), F.col('mem_prv_id_align')).alias('mem_report_hier_2'),
        F.col('mem_report_hier_3'),
        F.col('mem_report_hier_4'),
        F.col('mem_report_hier_5'),
        F.col('reason_for_exclusion').alias('mem_excluded_reason'),
        F.col('mem_care_coordinator'),
        F.col('riskscr_client'),
    )


def _create_member_df(client_member_list: DataFrame)-> DataFrame:
    """
    Args:
        client_member_list:    DataFrame returned from _build_client_all_member

    Returns:
        DataFrame ready for exporting to a client_member table.
    """
    window_member = Window.partitionBy(F.col('member_id')).orderBy(F.col('member_id'), F.col('date_start').desc())
    df_latest_member_id = client_member_list.select(
        '*',
        F.row_number().over(window_member).alias('mem_order')
    ).where(
        F.col('mem_order') == 1
    )

    return df_latest_member_id.select(
        F.col('member_id'),
        F.col('mem_name'),
        F.col('mem_dependent_status'),
        F.col('mem_prv_id_align'),
        F.col('mem_addr_street'),
        F.col('mem_addr_city'),
        F.col('mem_addr_state'),
        F.col('mem_addr_zip'),
        F.col('mem_report_hier_1'),
        F.col('mem_report_hier_2'),
        F.col('mem_report_hier_3'),
        F.col('mem_report_hier_4'),
        F.col('mem_report_hier_5'),
        F.col('mem_excluded_reason'),
        F.col('mem_care_coordinator'),
        F.col('riskscr_client'),
        F.col('assignment_indicator')
    )


def _create_member_time_df(client_member_list: DataFrame, date_latestpaid: datetime)-> DataFrame:
    """
    Args:
        client_member_list: DataFrame returned from _build_client_all_member
        date_latestpaid: Derived date_latestpaid datetime

    Returns:
       DataFrame ready for exporting to a client_member_time table.
    """

    exploded_df = create_member_months(client_member_list, 'hicno', 'date_start',
                                       'date_end', date_latestpaid).drop(
        'global_start'
    ).drop(
        'global_end'
    ).drop(
        'windows_array_split'
    )

    return exploded_df.select(
        F.col('member_id'),
        F.col('mem_prv_id_align'),
        F.col('assignment_indicator'),
        F.col('date_start'),
        F.col('date_end')
    )


def _update_metadata(struct: StructType, metadata_dict: dict) -> StructType:
    """
    Update metadata based on member metadata dictionary
    Args:
        struct: StructType from DataMart
        metadata_dict: Dictionary with Member Report Hierarchies and Eligibility Splits
    Returns:
        StructType with metadata updated with member labels
    """

    for field in struct:
        if metadata_dict.get(field.name):
            struct[field.name].metadata.update(metadata_dict[field.name])
    return struct


def main() -> int:
    """A function to enclose the execution of business logic."""
    LOGGER.info('Preparing to create client member and client member time')

    LOGGER.info("Collecting NGALIGN Files and MNGREB Files")
    ngalign_list = _REFERENCES.collect_files_regex('NGALIGN')
    mngreb_list = _REFERENCES.collect_files_regex('MNGREB')

    ngalign_file_count = len(ngalign_list) + len(mngreb_list)
    if not ngalign_file_count:
        LOGGER.info("There were no NGALIGN or MNGREB files found. Moving on to the next program.")
        return 0

    sparkapp = SparkApp(PRM_META['pipeline_signature'])
    xref_path = PRM_META[20, 'out'] / 'cclf9_bene_xref.sas7bdat'
    xref_df = read_sas_data(sparkapp.session, xref_path)

    phys_path = PRM_META[20, 'out'] / 'cclf5_partb_phys.sas7bdat'
    phys_df = read_sas_data(sparkapp.session, phys_path)

    claim_header_path = PRM_META[20, 'out'] / 'cclf1_parta_header.sas7bdat'
    claim_header_df = read_sas_data(sparkapp.session, claim_header_path)
    derived_date_latestpaid = derive_date_latestpaid(claim_header_df)

    npi_df = sparkapp.load_df(PRM_META['path_product_ref'] / (PRM_META['filename_sas_npi'] + '.parquet'))

    taxonomy_xref_df = sparkapp.load_df(PRM_META[15, 'out'] / 'ref_tax_spec_xwalk.parquet')

    next_gen_config_path = IndyPyPath(__file__).parent / 'next_gen_config.json'
    with next_gen_config_path.open() as json_file:
        next_gen_config = json.load(json_file)
    possible_delimiters = ['\t', ',', '|']

    LOGGER.info('Loading NGALIGN files')
    alignment_df = _load_ngalign_files(sparkapp, ngalign_list, possible_delimiters, xref_df)
    derived_performance_year = derive_performance_year(alignment_df)

    LOGGER.info('Loading MNGREB files')
    mngreb_df = _load_mngreb_files(sparkapp, mngreb_list, next_gen_config, possible_delimiters,
                                   xref_df)

    client_providers_list = build_providers(phys_df, npi_df, taxonomy_xref_df,
                                            derived_performance_year, next_gen_config)
    client_member_list = _build_client_all_member(alignment_df, mngreb_df, client_providers_list)

    member_df = _create_member_df(client_member_list)
    member_time_df = _create_member_time_df(client_member_list, derived_date_latestpaid)

    member_df.validate.assert_unique("member_id")

    LOGGER.info('Loading metadata')

    client_references = DataMart('References_Client')
    
    structtypes = client_references.generate_structtypes()

    facility_structs = structtypes['client_facility']
    
    mock_facility = mock_dataframe(sparkapp, facility_structs)
    
    prm.spark.io_sas.export_dataframe(
        mock_facility,
        PRM_META[(18, 'out')] / 'client_facility.sas7bdat',
    )
    sparkapp.save_df(mock_facility, PRM_META[(18, 'out')] / 'client_facility.parquet')

    member_time_structs = structtypes['client_member_time']
    member_structs = structtypes['client_member']
    provider_structs = structtypes['client_provider']

    member_time_updated_metadata = _update_metadata(member_time_structs, _MEMBER_TIME_METADATA)
    member_updated_metadata = _update_metadata(member_structs, _MEMBER_METADATA)
    provider_updated_metadata = _update_metadata(provider_structs, _PROVIDER_METADATA)

    remove_blank_field_labels(member_time_updated_metadata)
    remove_blank_field_labels(member_updated_metadata)
    remove_blank_field_labels(provider_updated_metadata)

    member_all_fill_df = member_df.na.fill(_NA_FILL)

    member_time_fill_df = member_time_df.select(
        [F.col(field.name).cast(field.dataType).aliasWithMetadata(
            field.name,metadata=field.metadata)
         for field in member_time_updated_metadata]
    ).orderBy(F.col('member_id'), F.col('date_start'))

    member_fill_df = member_all_fill_df.select(
        [F.col(field.name).cast(field.dataType).aliasWithMetadata(
            field.name, metadata=field.metadata)
         for field in member_updated_metadata]
    ).orderBy(F.col('member_id'))

    client_provider_df = client_providers_list.select(
        [F.col(field.name).cast(field.dataType).aliasWithMetadata(
            field.name, metadata=field.metadata)
         for field in provider_updated_metadata]
    )

    prm.spark.io_sas.export_dataframe(
        member_fill_df,
        PRM_META[(18, 'out')] / 'client_member.sas7bdat',
    )
    sparkapp.save_df(member_fill_df, PRM_META[(18, 'out')] / 'client_member.parquet')

    prm.spark.io_sas.export_dataframe(
        member_time_fill_df,
        PRM_META[(18, 'out')] / 'client_member_time.sas7bdat',
    )
    sparkapp.save_df(member_time_fill_df, PRM_META[(18, 'out')] / 'client_member_time.parquet')

    prm.spark.io_sas.write_sas_data(
        client_provider_df,
        PRM_META[18, 'out'] / 'client_provider.sas7bdat'
    )
    sparkapp.save_df(client_provider_df, PRM_META[18, 'out'] / 'client_provider.parquet')

    xref_df.unpersist()
    phys_df.unpersist()
    claim_header_df.unpersist()

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
