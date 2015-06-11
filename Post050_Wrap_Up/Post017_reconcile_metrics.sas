/*
### CODE OWNERS: Jason Altieri, Shea Parkes

### OBJECTIVE:
	Reconcile metrics against the cost_util table to ensure we are delivering
	consistent results.

### DEVELOPER NOTES:
	<none>
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;

libname post050 "&post050." access=readonly;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Check that Member Months are reported accurately*/

proc sql;
	create table memmos_check as
	select
		mems.name_client
		,mems.time_period
		,mems.elig_status_1
		,sum(mems.prm_memmos) as memmos_check
		,sum(metrics.metric_value) as memmos_metric
	from post050.memmos as mems
	left join post050.metrics_key_value as metrics on
		mems.name_client = metrics.name_client and
		mems.time_period = metrics.time_period and
		mems.elig_status_1 = metrics.elig_status_1
	where 
		upcase(mems.prm_coverage_type) = "MEDICAL" and
		upcase(metrics.metric_id) = "MEMMOS_SUM"
	;
quit;

data memmos_diff;
	set memmos_check;
	where round(memmos_check,1) ne round(memmos_metric,1);
run;

%AssertDatasetNotPopulated(memmos_diff,ReturnMessage=The memmos table does not match the reported member months.)

/*Check basic metrics by re-calculating them from the Cost_Util table*/
%macro BasicMetricsTest(
	metric_id /*The metric_id to be verified*/
	,cost_util_field /*The field to be summed from the cost_util table*/
	);
		proc sql;
			create table cost_util_rollup as
			select
				name_client
				,time_period
				,elig_status_1
				,sum(&cost_util_field.) as check
			from post050.cost_util
			where upcase(prm_coverage_type) = "MEDICAL"
			group by
				name_client
				,time_period
				,elig_status_1	
			;
		quit;


		proc sql;
			create table &cost_util_field._check as
			select
				cost.name_client
				,cost.time_period
				,cost.elig_status_1
				,check
				,metrics.metric_value
			from cost_util_rollup as cost
			left join post050.metrics_key_value as metrics on
				cost.name_client = metrics.name_client and
				cost.time_period = metrics.time_period and
				cost.elig_status_1 = metrics.elig_status_1
			where upcase(metrics.metric_id) = "%upcase(&metric_id.)"
			;
		quit;

		data &metric_id._diff;
			set &cost_util_field._check;
			where round(check) ne round(metric_value);
		run;

		%AssertDatasetNotPopulated(&metric_id._diff,ReturnMessage=The &metric_id. calculated from the cost_util table does not match the metrics_key_value table.)

%mend BasicMetricsTest;


/*Check sum of costs and sum of discharges*/
%BasicMetricsTest(prm_costs_sum_all_services,prm_costs)
%BasicMetricsTest(discharges_sum_all_services,prm_discharges)


/*Check per 1000 metric values*/
%macro Per1000MetricsTest(
					label /*The identifier for interim datasets*/
					,metric_id /*The metric_id to be verified*/
					,cost_util_field /*The field to sum from the cost_util table*/
					,cost_util_include /*Input for the eqt function determining what type of PRM lines to include */
					,cost_util_exclude=%str("X99") /*Explicit list of excluded PRM lines that would otherwise be included by the eqt.
										This should be written as %str("I31", "O21", ...) Set a nonsense default so it will work with no exclusions*/);

		proc sql;
			create table cost_util_rollup as
			select
				name_client
				,time_period
				,elig_status_1
				,sum(&cost_util_field.) as check
			from post050.cost_util
			where upcase(prm_coverage_type) = "MEDICAL" and
				lowcase(prm_line) eqt %LOWCASE("&cost_util_include.") and
				LOWCASE(prm_line) not in(%LOWCASE(&cost_util_exclude.))
			group by
				name_client
				,time_period
				,elig_status_1	
			;
		quit;


		proc sql;
			create table memmos as
			select
				name_client
				,time_period
				,elig_status_1
				,sum(prm_memmos) as memmos
			from post050.memmos
			where 
				upcase(prm_coverage_type) = "MEDICAL"
			group by 
				name_client
				,time_period
				,elig_status_1
			;
		quit;


		proc sql;
			create table &label._check as
			select
				cost.name_client
				,cost.time_period
				,cost.elig_status_1
				,check/memmos.memmos * 12000 as check_per_1k
				,metrics.metric_value
			from cost_util_rollup as cost
			left join post050.metrics_key_value as metrics on
				cost.name_client = metrics.name_client and
				cost.time_period = metrics.time_period and
				cost.elig_status_1 = metrics.elig_status_1
			left join memmos as memmos on 
				cost.name_client = memmos.name_client and
				cost.time_period = memmos.time_period and
				cost.elig_status_1 = memmos.elig_status_1
			where upcase(metrics.metric_id) = "%upcase(&metric_id.)"
			;
		quit;

		data &label._diff;
			set &label._check;
			where round(check_per_1k) ne round(metric_value);
		run;

		%AssertDatasetNotPopulated(&label._diff,ReturnMessage=The &metric_id. calculated from the cost_util table does not match the metrics_key_value table.)

%mend Per1000MetricsTest;

%Per1000MetricsTest(label=acute_per1k
					,metric_id=acute_per1k
					,cost_util_field=prm_discharges
					,cost_util_include=I
					,cost_util_exclude=%str("I31"));

%Per1000MetricsTest(label=medical_per1k
					,metric_id=medical_per1k
					,cost_util_field=prm_discharges
					,cost_util_include=I11);

%Per1000MetricsTest(label=medical_general_per1k
					,metric_id=medical_general_per1k
					,cost_util_field=prm_discharges
					,cost_util_include=I11a);

%Per1000MetricsTest(label=surgical_per1k
					,metric_id=surgical_per1k
					,cost_util_field=prm_discharges
					,cost_util_include=I12);

%Per1000MetricsTest(label=high_tech_imaging_per1k
					,metric_id=high_tech_imaging_per1k
					,cost_util_field=prm_util
					,cost_util_include=O14);

%Per1000MetricsTest(label=observation_stays_per1k
					,metric_id=observation_stays_per1k
					,cost_util_field=prm_util
					,cost_util_include=O41h);

%Per1000MetricsTest(label=SNF_per1k
					,metric_id=SNF_per1k
					,cost_util_field=prm_discharges
					,cost_util_include=I31);

%Per1000MetricsTest(label=ED_per1k
					,metric_id=ED_per1k
					,cost_util_field=prm_util
					,cost_util_include=O11);


/*Check pct_office_visits_pcp metric*/
proc sql;
	create table cost_util_summary as
	select
		name_client
		,time_period
		,elig_status_1
		,sum(prm_util) as _denom
		,sum((case when lowcase(prm_line) eq "p32c" then prm_util else 0 end)) / calculated _denom as check_value
	from post050.cost_util
	where upcase(prm_coverage_type) = "MEDICAL" and
		lowcase(prm_line) eqt "p32"
	group by
		name_client
		,time_period
		,elig_status_1
	;
quit;


proc sql;
	create table pct_office_visits_pcp_check as
	select
		cost.name_client
		,cost.time_period
		,cost.elig_status_1
		,check_value
		,metrics.metric_value
	from cost_util_summary as cost
	left join post050.metrics_key_value as metrics on
		cost.name_client = metrics.name_client and
		cost.time_period = metrics.time_period and
		cost.elig_status_1 = metrics.elig_status_1
	where upcase(metrics.metric_id) = "%upcase(pct_office_visits_pcp)"
	;
quit;

data pct_office_visits_diff;
	set pct_office_visits_pcp_check;
	where round(check_value) ne round(metric_value);
run;

%AssertDatasetNotPopulated(pct_office_visits_diff,ReturnMessage=The pct_office_visists_pcp calculated from the cost_util table does not match the metrics_key_value table.)


%put System Return Code = &syscc.;
