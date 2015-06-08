/*
### CODE OWNERS: Michael Menser

### OBJECTIVE:
	Validate that the two details tables (SNF and inpatient) and the cost_util table match up as expected.

### DEVELOPER NOTES:
	<none>
*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname post050 "&post050.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Roll up the snf table to summarize the discharges, days and costs by combination of time period, eligibility
status and client name.*/
proc sql;
	create table details_snf_summary as
	select
		name_client
		,time_period
		,elig_status_1
		,sum(cnt_discharges_snf) as total_discharges_snf
		,sum(sum_days_snf) as total_days_snf
		,sum(sum_costs_snf) as total_costs_snf
	from Post050.details_SNF
	group by
		name_client
		,time_period
		,elig_status_1
	;
quit;
		
/*Now do the same for the cost_util table.*/
proc sql;
	create table cost_util_summary as
	select
		name_client
		,time_period
		,elig_status_1
		,sum(prm_discharges) as total_discharges_snf
		,sum(prm_days) as total_days_snf
		,sum(prm_costs) as total_costs_snf
	from Post050.cost_util
	where UPCASE(prm_line) = 'I31'
	group by
		name_client
		,time_period
		,elig_status_1
	;
quit;
