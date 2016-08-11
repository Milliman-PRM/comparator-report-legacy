/*
### CODE OWNERS: Jason Altieri, Anna Chen

### OBJECTIVE:
	Output the outclaims table with appended passaround fields. This is done after the datamart export because we do not
	provide this as part of the regular monthly datamart.

### DEVELOPER NOTES:
	<none>
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname M020_Out "&M020_Out." access=readonly;
libname M040_Out "&M040_Out." access=readonly;
libname post060 "&post060.";


proc sql;
	create table post060.outclaims_w_prv (drop = claim_id) as
	select
		base.*
		,pass.*
	from M040_Out.outclaims as base
	left join M020_Out.passarounds as pass
		on base.claimid eq pass.claim_id
	;
quit;


%put System Return Code = &syscc.;
