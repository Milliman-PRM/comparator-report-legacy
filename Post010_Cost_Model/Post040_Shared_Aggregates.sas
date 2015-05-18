/*
### CODE OWNERS: Aaron Hoch

### OBJECTIVE:
	Centralize common aggregated items such as average risk scores, total costs, member counts, etc.

### DEVELOPER NOTES:
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.pudd_methods\*.sas";

/* Libnames */
libname post008 "&post008." access=readonly;
libname post010 "&post010.";

%let assign_name_client = name_client = "&name_client.";
%put assign_name_client = &assign_name_client.;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/





/***** GENERATE RAW SOURCE DATA *****/

%agg_claims(
	IncStart=&list_inc_start.
	,IncEnd=&list_inc_end.
	,PaidThru=&list_paid_thru.
	,Med_Rx=Med
	,Ongoing_Util_Basis=&post_ongoing_util_basis.
	,Force_Util=&post_force_util.
	,Dimensions=member_id~elig_status_1
	,Time_Slice=&list_time_period.
	,Where_Claims=
	,Where_Elig=
	,Date_DateTime=
	,Suffix_Output=member
	)

data agg_claims_med_coalesce;
	set agg_claims_med_member;
	elig_status_1 = coalescec(elig_status_1,"Unknown");
	rename time_slice = time_period;
	&assign_name_client.;
run;

proc sql;
	create table costs_sum_all_services  as
	select
			src.name_client
			,src.time_period
			,src.elig_status_1
			,sum(src.prm_costs) as PRM_costs
			,sum(src.discharges) as Discharges

	from agg_claims_med_coalesce as src
	inner join 
		post008.members as limit 
			on
			src.member_id eq limit.member_id
			and src.time_period eq limit.time_period

	group by 
			src.name_client
			,src.time_period
			,src.elig_status_1
	;
quit;


proc sql;
	create table post010.basic_aggregation_elig_status as
		select
				cost.name_client
				,cost.time_period
				,coalescec("Basic") as metric_category label= "Metric Category"
				,cost.elig_status_1 label= "Beneficiary Status"
				,sum(mems.memmos) as memmos_sum label= "Sum of Member Months"
				,sum(mems.riskscr_1 * mems.memmos)/sum(mems.memmos) as riskscr_1_avg label= "Average Risk Score"
				,sum(cost.PRM_costs) as prm_costs_sum_all_services label= "Sum of PRM Costs"
				,sum(cost.discharges) as discharges_sum_all_services label= "Sum of Discharges"

	from post008.members as mems
	left join 
		costs_sum_all_services as cost
			on mems.time_period = cost.time_period
			and mems.elig_status_1 = cost.elig_status_1

	group by
			cost.name_client
			,cost.time_period
			,cost.elig_status_1
	;
quit;

%LabelDataSet(post010.basic_aggregation_elig_status)

proc sql;
	create table post010.basic_aggregation as
		select
				cost.name_client
				,cost.time_period
				,coalescec("Basic") as metric_category label= "Metric Category"
				,sum(mems.memmos) as memmos_sum label= "Sum of Member Months"
				,sum(mems.riskscr_1 * mems.memmos)/sum(mems.memmos) as riskscr_1_avg label= "Avgerage Risk Score"
				,sum(cost.PRM_costs) as prm_costs_sum_all_services label= "Sum of PRM Costs"
				,sum(cost.discharges) as discharges_sum_all_services label= "Sum of Discharges"

	from post008.members as mems
	left join 
		costs_sum_all_services as cost
			on mems.time_period = cost.time_period

	group by
			cost.name_client
			,cost.time_period
	;
quit;

%LabelDataSet(post010.basic_aggregation)


proc transpose data=post010.basic_aggregation 
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
