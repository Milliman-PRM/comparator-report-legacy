/*
### CODE OWNERS: Jason Altieri, Anna Chen

### OBJECTIVE:
	Output the outclaims_prm table with appended passaround fields.

### DEVELOPER NOTES:
	<none>
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "%GetParentFolder(1)share001_derive_output_directory.sas" / source2;

libname M020_Out "&M020_Out." access=readonly;
libname M073_Out "&M073_Out." access=readonly;
libname post060 "&post060.";

/*Pull a copy of outclaims_prm and outpharmacy_prm to postboarding then write
to NewYorkMillimanShare*/

proc sql;
	create table post060.outclaims_w_prv (drop = claim_id PRM_Avoidable_YN) as
	select
		base.*
		,pass.*
	from M073_Out.outclaims_prm as base
	left join M020_Out.passarounds as pass
		on base.claimid eq pass.claim_id
	;
quit;

data post060.outpharmacy_prm (drop = PRM_Avoidable_YN);
	set M073_out.outpharmacy_prm;
run;

data NYMS.outclaims_prm;
	set post060.outclaims_w_prv;
run;

data NYMS.outpharmacy_prm;
	set post060.outpharmacy_prm;
run;

%put System Return Code = &syscc.;
