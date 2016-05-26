/*
### CODE OWNERS: Jason Altieri
### OBJECTIVE:
	Use the PRM outputs to create a claims probability distribution.

### DEVELOPER NOTES:
	Rx claims and eligibility will not be included because their
	costs are not available in the CCLF data
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M008_cde.func06_build_metadata_table.sas";
%include "&M073_Cde.pudd_methods\*.sas";

/* Libnames */
libname M015_Out "&M015_Out." access=readonly;
libname post008 "&post008." access=readonly;
libname post010 "&post010.";

%let range_stmt = case 
					when PRM_Costs le 500 then "0-500"
					when PRM_Costs le 1000 then "501-1000"
					when PRM_Costs le 1750 then "1001-1750"
					when PRM_Costs le 2500 then "1751-2500"
					when PRM_Costs le 3500 then "2501-3500"
					when PRM_Costs le 5000 then "3501-5000"
					when PRM_Costs le 7500 then "5001-7500"
					when PRM_Costs le 15000 then "7501-15000"
					when PRM_Costs le 25000 then "15001-25000"
					when PRM_Costs le 50000 then "25001-50000"
					when PRM_Costs le 100000 then "50001-100000"
					when PRM_Costs le 200000 then "100001-200000"
					else "200000+"
				end as Cost_Bucket;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/***** GENERATE RAW SOURCE DATA *****/

data agg_claims_annaual_cost;
	set post010.agg_claims_limited;

	PRM_Costs = (PRM_Costs/memmos)*12;
run;

proc summary nway missing data=agg_claims_annaual_cost;
	class member_id time_period elig_status_1;
	var PRM_Costs;
	output out = costs_by_member (drop = _:)sum=;
run;

proc sql;
	create table costs_w_ranges as
	select
		time_period
		,elig_status_1
		,member_id
		,PRM_Costs
		,&range_stmt.
	from costs_by_member
	;
quit;

proc summary nway missing data=costs_w_ranges;
	class time_period elig_status_1 cost_bucket;
	var PRM_Costs;
	output out = claims_distribution (drop = _TYPE_ rename = (_FREQ_ = member_count))sum=;
run;

/*Prepare final output*/
data Post010.claims_distribution;
	format &claims_distribution_cgfrmt.;	
	set claims_distribution;
	&assign_name_client.;
run;

%put System Return Code = &syscc.;
