/*
### CODE OWNERS: Jason Altieri, Anna Chen
### OBJECTIVE:
	Create a summary of office administered drugs by HCPCS.

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
libname M025_Out "&M025_Out." access=readonly;
libname post008 "&post008." access=readonly;
libname post010 "&post010.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/


/***** GENERATE RAW SOURCE DATA *****/

data part_b_drug_claims;
	set post010.agg_claims_limited;
	&assign_name_client.;
	providerid = coalescec(providerid, "Unknown");
	where mcrm_line in ("O16", "P34");
	HCPCS = coalescec(HCPCS,"XXXXX");
run;

proc summary nway missing data=part_b_drug_claims;
	class name_client time_period elig_status_1 HCPCS providerid;
	var PRM_Costs;
	output out=part_b_drug_summary(drop = _TYPE_ rename = (_FREQ_ = claim_count))sum=;
run;

proc sql;
	create table part_b_w_prv as
	select
		summ.*
		,coalescec(prv.prv_name, "Unknown") as provider format=$128. length=128
		,coalescec(prv.prv_specialty, "XX") as specialty format=$2. length=2
	from part_b_drug_summary as summ
	left join M025_Out.providers as prv
		on summ.providerid = prv.prv_id
	;
quit;

data post010.office_admin_drug;
	format &office_admin_drug_cgfrmt.;	
	set part_b_w_prv;
run;

%put System Return Code = &syscc.;
