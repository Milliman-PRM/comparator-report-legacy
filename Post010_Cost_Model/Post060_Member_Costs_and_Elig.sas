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
	create table post010.member_cost as
	select 
		"&name_client." as name_client format $256. length 256,
		elig.*, 
		coalesce(costs.prm_costs, 0) as total_cost
	from costs_by_mem as costs
	full outer join post010.elig_summary as elig
	on costs.member_id = elig.member_id
	and costs.time_period = elig.time_period
	;
quit;

%LabelDataSet(post010.elig_cost_summary)

/*Assert that the total memmos reconcile with the member table. 
Round to avoid floating point differences*/
proc summary nway missing data=post008.members;
	class member_id time_period;
	var memmos;
	output out = base_test (drop = _TYPE_)sum=;
run;

proc summary nway missing data=post010.member_cost;
	class member_id time_period;
	var months_total;
	output out = new_test (drop = _TYPE_)sum=;
run;

proc sql;
	create table memmos_mismatch as
	select
		base.member_id
		,base.time_period
		,round(base.memmos,.01) as base_memmos
		,new.months_total as new_memmos
	from base_test as base
	full outer join new_test as new
		on base.member_id = new.member_id and
		base.time_period = new.time_period
	where round(base.memmos,.01) ne round(new.months_total,.01)
	;
quit;

%AssertDatasetNotPopulated(memmos_mismatch ,ReturnMessage=Members months do not reconcile with the Members table.);


%put System Return Code = &syscc.;
