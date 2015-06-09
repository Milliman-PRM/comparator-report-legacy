/*
### CODE OWNERS: Jason Altieri

### OBJECTIVE:
	Reconcile metrics against the cost_util table to ensure we are delivering
	consistent results.

### DEVELOPER NOTES:
	<none>
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname post050 "&post050.";

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
	where upcase(mems.prm_coverage_type) = "MEDICAL" and metrics.metric_id = "memmos_sum"
	;
quit;

data memmos_diff;
set memmos_check;
where round(memmos_check,1) ne round(memmos_metric,1);
run;

%AssertDatasetNotPopulated(memmos_diff,ReturnMessage=The memmos table does not match the reported member months.)

/*Check a variety of calculated metrics by re-calculating them from the Cost_Util table*/

proc sql;
	create table cost_util_rollup as
	select
		name_client
		,time_period
		,elig_status_1
		,sum(prm_costs) as costs_check
	from post050.cost_util
	where upcase(prm_coverage_type) = "MEDICAL"
	group by
		name_client
		,time_period
		,elig_status_1	
	;
quit;


proc sql;
	create table costs_check as
	select
		cost.name_client
		,cost.time_period
		,cost.elig_status_1
		,costs_check
		,metrics.metric_value as metric_costs
	from cost_util_rollup as cost
	left join post050.metrics_key_value as metrics on
		cost.name_client = metrics.name_client and
		cost.time_period = metrics.time_period and
		cost.elig_status_1 = metrics.elig_status_1
	where metrics.metric_id = "prm_costs_sum_all_services"
	;
quit;

data costs_diff;
set costs_check;
where round(costs_check) ne round(metric_costs);
run;

%AssertDatasetNotPopulated(costs_diff,ReturnMessage=The costs calculated from the cost_util table do not match the metric value.)


%put System Return Code = &syscc.;
