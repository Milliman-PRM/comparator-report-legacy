/*
### CODE OWNERS: Jason Altieri

### OBJECTIVE:
	Create a table that gives the total and truncated costs by member.

### DEVELOPER NOTES:

*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;

/* Libnames */
libname post008 "&post008." access=readonly;
libname post010 "&post010."; 

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

data truncation_limits;
	infile "%GetParentFolder(1)Post002_References\truncation_thresholds.csv"
	dlm = ','
	dsd
	missover
	firstobs=2
	;

	input
		bene_status :$15.
		threshold :12.
		;
run;

proc sql;
	create table members_w_limits as
	select
		mem.*
		,(lim.threshold / 12) * memmos as threshold
	from post008.members as mem
	left join truncation_limits as lim on
		upcase(mem.elig_status_1) eq upcase(lim.bene_status)
	;
quit;

proc summary nway missing data=post010.agg_claims_limited;
	class time_period member_id;
	var PRM_Costs;
	output out = costs_by_mem (drop = _:)sum=;
run;

/*Coalesce 0 for costs and capped costs since some members don't have claims*/
proc sql;
	create table post010.mem_capped_cost as
	select
		mem.*
		,coalesce(clm.prm_costs, 0) as total_cost
		,case when clm.prm_costs gt mem.threshold then mem.threshold
			else coalesce(clm.prm_costs, 0) end as capped_costs
	from members_w_limits as mem
	left join costs_by_mem as clm
		on mem.member_id = clm.member_id
			and mem.time_period = clm.time_period
	;
quit;

%LabelDataSet(post010.mem_capped_cost)

%put System Return Code = &syscc.;
