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
	var prm_paid;
	output out = member_costs_calc (drop = _:)sum=total_cost;
run;

proc sql;
	create table post010.member_costs as
	select
		"&name_client." as name_client format $256. length 256,
		*
	from member_costs_calc
	;
quit;

%LabelDataSet(post010.member_costs)

/*Assert that the total costs reconcile between tables.*/

proc summary nway missing data=post010.member_costs;
	class time_period;
	var total_cost;
	output out = new_cost_sum (drop = _:)sum=;
run;

data medical_costs;
	set post010.cost_util;
	where upcase(prm_coverage_type) = "MEDICAL";
run;

proc summary nway missing data=medical_costs;
	class time_period;
	var prm_paid;
	output out=base_cost_sum (drop = _:)sum=;
run;

proc sql;
	create table cost_mismatch as
	select
		base.time_period,
		round(base.prm_paid,.01) as base_costs,
		round(new.total_cost,.01) as new_costs,
		(round(base.prm_paid,.01) - round(new.total_cost,.01)) as diff
	from base_cost_sum as base
	left join new_cost_sum as new
		on base.time_period = new.time_period
	where calculated base_costs ne calculated new_costs
	;
quit;

%AssertDatasetNotPopulated(cost_mismatch ,ReturnMessage=Costs do not reconcile with the cost_util table.);

%put System Return Code = &syscc.;
