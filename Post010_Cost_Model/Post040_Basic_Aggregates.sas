/*
### CODE OWNERS: Aaron Hoch, Shea Parkes

### OBJECTIVE:
	Centralize common aggregated items such as average risk scores, total costs, member counts, etc.

### DEVELOPER NOTES:
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

/* Libnames */
libname post008 "&post008." access=readonly;
libname post010 "&post010.";


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/





/**** STAGE EXISTING SUMMARIES ****/

proc sql;
	create table costs_sum_all_services  as
	select
			name_client
			,time_period
			,elig_status_1
			,sum(prm_costs) as PRM_costs_sum
			,sum(prm_discharges) as PRM_Discharges_sum
	from post010.cost_util
	group by 
			name_client
			,time_period
			,elig_status_1
	;
quit;

proc sql noprint;
	select sum(prm_costs) format=32.
	into :costs_sum_input trimmed
	from post010.cost_util
	;
quit;
%put costs_sum_input = &costs_sum_input.;

proc sql;
	create table members_aggregate as
	select
		"&Name_Client." as name_client
		,time_period
		,elig_status_1
		,sum(memmos) as memmos_sum
		,sum(memmos * riskscr_1) as memmos_sum_riskadj
		,sum(memmos * riskscr_1) / sum(memmos) as riskscr_1_avg
	from post008.members
	group by
		time_period
		,elig_status_1
	;
quit;

data post010.Basic_aggs_w_elig;
set members_aggregate;
run;

/**** BRING TOGETHER IN MULTIPLE WIDE AND LONG FORMATS ****/

proc sql;
	create table post010.basic_aggs_elig_status as
	select
		mem.*
		,coalesce(costs.prm_costs_sum, 0) as prm_costs_sum_all_services
		,coalesce(costs.prm_discharges_sum, 0) as discharges_sum_all_services
	from members_aggregate as mem
	left join costs_sum_all_services as costs on
		mem.name_client eq costs.name_client
		and mem.time_period eq costs.time_period
		and mem.elig_status_1 eq costs.elig_status_1
	;
quit;
%LabelDataSet(post010.basic_aggs_elig_status)

%AssertRecordCount(post010.basic_aggs_elig_status,eq,%GetRecordCount(members_aggregate),ReturnMessage=Unexpected cartesianing occured.)

proc sql noprint;
	select sum(prm_costs_sum_all_services) format=32.
	into :costs_sum_output_elig_status trimmed
	from post010.basic_aggs_elig_status
	;
quit;
%put costs_sum_output_elig_status = &costs_sum_output_elig_status.;

%let smape_chksum_elig_status = %sysfunc(round(%sysevalf(%sysfunc(abs(&costs_sum_output_elig_status.-&costs_sum_input.))/(%sysfunc(abs(&costs_sum_output_elig_status.))+%sysfunc(abs(&costs_sum_input.)))),0.0001));
%put smape_chksum_elig_status = &smape_chksum_elig_status.;
%AssertThat(&smape_chksum_elig_status.,lt,0.001,ReturnMessage=Not all costs were aggregated.)


proc sql;
	create table post010.basic_aggs as
	select
		name_client
		,time_period
		,"Basic" as metric_category
		,sum(memmos_sum) as memmos_sum label= "Total Member Months"
		,sum(memmos_sum_riskadj) as memmos_sum_riskadj label= "Total Member Months (Risk Adjusted)"
		,sum(riskscr_1_avg * memmos_sum)/sum(memmos_sum) as riskscr_1_avg label= "Avgerage Risk Score"
		,sum(prm_costs_sum_all_services) as prm_costs_sum_all_services label= "Total Costs (All Services)"
		,sum(discharges_sum_all_services) as discharges_sum_all_services label= "Total Discharges"
	from post010.basic_aggs_elig_status
	group by
		name_client
		,time_period
	;
quit;

%LabelDataSet(post010.basic_aggs)


proc transpose data=post010.basic_aggs 
		out=metrics_transpose (rename=(COL1 = metric_value))
		name=metric_id
		label=metric_name;	
	by name_client time_period metric_category;
run;

data post010.metrics_basic;
	format &metrics_key_value_cgfrmt.;
	set metrics_transpose;
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;

%LabelDataSet(post010.metrics_basic)

%put System Return Code = &syscc.;
