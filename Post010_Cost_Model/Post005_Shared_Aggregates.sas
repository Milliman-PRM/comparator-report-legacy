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
%include "&M008_cde.func06_build_metadata_table.sas";
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
run;

proc sql;
	create table costs_sum_all_services  as
	select
			src.time_period
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
			src.time_period
			,src.elig_status_1
	;
quit;


proc sql;
	create table time_period_aggregates as
		select
				cost.time_period
				,cost.elig_status_1
				,sum(mems.memmos) as memmos_sum
				,sum(mems.riskscr_1 * mems.memmos) as memmos_sum_riskadj
				,sum(cost.PRM_costs) as PRM_costs
				,sum(cost.discharges) as Discharges

	from post008.members as mems
	left join 
		costs_sum_all_services as cost
			on mems.time_period = cost.time_period
			and mems.elig_status_1 = cost.elig_status_1

	group by
			cost.time_period
			,cost.elig_status_1
	;
quit;


%put System Return Code = &syscc.;
