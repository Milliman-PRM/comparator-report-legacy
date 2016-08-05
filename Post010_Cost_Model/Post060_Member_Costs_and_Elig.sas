/*
### CODE OWNERS: Jason Altieri, Brandon Patterson

### OBJECTIVE:
	Create a table that gives the total costs and eligibility-months by member and time window.

### DEVELOPER NOTES:

*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;

/* Libnames */
libname post008 "&post008." access=readonly;
libname post010 "&post010."; 

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/
proc summary nway missing data=post010.agg_claims_limited;
	class time_period member_id;
	var PRM_Costs;
	output out = costs_by_mem (drop = _:)sum=;
run;

/*Coalesce 0 for costs and capped costs since some members don't have claims*/
proc sql;
	create table post010.elig_cost_summary as
	select elig.*, coalesce(costs.prm_costs, 0) as cost
	from costs_by_mem as costs
	full outer join post010.elig_summary as elig
	on costs.member_id = elig.member_id
	and costs.time_period = elig.time_period
	;
quit;

%LabelDataSet(post010.elig_cost_summary)

%put System Return Code = &syscc.;
