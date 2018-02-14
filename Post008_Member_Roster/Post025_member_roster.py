"""
### CODE OWNERS: Umang Gupta, Pierre Cornell
### OBJECTIVE:
  Recreate Members Table from ACOI Outputs
### DEVELOPER NOTES:
    TEMP
"""


import logging

import pyspark.sql.functions as spark_funcs
from prm.spark.io_sas import write_sas_data

import aco_insight.meta.project
from prm.spark.app import SparkApp

LOGGER = logging.getLogger(__name__)
META_SHARED = aco_insight.meta.project.gather_metadata()

NAME_MODULE = 'outputs'
PATH_INPUTS = META_SHARED['path_data_aco_insight'] / NAME_MODULE
PATH_OUTPUTS = META_SHARED['path_project_data'] / 'postboarding' / 'Post008_Member_Roster'

def main() -> int:
    sparkapp = SparkApp(META_SHARED['pipeline_signature'])
    
    dfs_input = {
        path.stem: sparkapp.load_df(path)
        for path in [
                PATH_INPUTS / 'members.parquet',
                PATH_INPUTS / 'members_rolling.parquet',
                PATH_INPUTS / 'member_months.parquet'
                ]
        }
        
    max_member_months = dfs_input['member_months'].filter(
        spark_funcs.col('month').between(('2016-10-01'),
            ('2017-09-30')),
        ).select(
            'member_id',
            'month',
        ).groupBy(
            'member_id',
        ).agg(
            spark_funcs.max('month').alias('max_elig'),
        )
    
    
    elig_status = dfs_input['member_months'].join(
            max_member_months,
            on=(dfs_input['member_months'].member_id == max_member_months.member_id) 
            & (dfs_input['member_months'].month == max_member_months.max_elig),
            how='inner',
        ).select(
            dfs_input['member_months'].member_id, 
            spark_funcs.col('elig_status_1_timeline'),
        )
    
    
    members = dfs_input['members'].join(
            elig_status,
            on='member_id',
            how='left_outer',
        ).join(
            dfs_input['members_rolling'].filter('month_rolling = "2017-09-30"'),
            on='member_id',
            how='left_outer',
        ).filter(
            'assignment_indicator_current = "Y"'
        ).select(
            spark_funcs.lit('2016Q4_2017Q3').alias('time_period'),
            dfs_input['members'].member_id,       
            spark_funcs.col('elig_status_1_timeline').alias('elig_status_1'),       
            spark_funcs.col('mem_prv_id_align_current').alias('mem_prov_id_align'),        
            spark_funcs.col('prv_name_align_current').alias('prv_name_align'),        
            spark_funcs.lit('CMS HCC Risk Score').alias('riskscr_1_type'),        
            spark_funcs.col('dob'),       
            spark_funcs.col('gender'),       
            spark_funcs.col('mem_name'),        
            spark_funcs.col('age_current').alias('age'),        
            spark_funcs.col('memmos_rolling').alias('memmos'),       
            spark_funcs.col('risk_score_rolling').alias('riskscr_1'),       
            spark_funcs.col('memmos_rolling').alias('riskscr_memmos'),   
        ).filter(
            'memmos != 0'
        )
    
    write_sas_data(
            members,
            PATH_OUTPUTS / 'members.sas7bdat',
            )
    
    return 0

if __name__ == '__main__':
    # pylint: disable=wrong-import-position, wrong-import-order, ungrouped-imports
    import sys
    import prm.utils.logging_ext
    import prm.spark.defaults_prm

    prm.utils.logging_ext.setup_logging_stdout_handler()
    SPARK_DEFAULTS_PRM = prm.spark.defaults_prm.get_spark_defaults(META_SHARED)

    with SparkApp(META_SHARED['pipeline_signature'], **SPARK_DEFAULTS_PRM):
        RETURN_CODE = main()

    sys.exit(RETURN_CODE)