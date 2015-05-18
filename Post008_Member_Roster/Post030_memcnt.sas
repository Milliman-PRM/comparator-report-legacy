/*
### CODE OWNERS: Michael Menser 

### OBJECTIVE:
	Create the memcnt table from the member roster.

### DEVELOPER NOTES:
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname post008 "&post008.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Find the number of members for each combination of key variables (the memcnt table)*/
proc sql;
	create table memcnt_to_export as
	select
		"&name_client." as name_client
		,time_period
		,elig_status_1
		,'N' as deceased_yn /*TODO: Append with Decedent/End of Life information when available*/ 
		,'N' as deceased_hospital_yn
		,'N' as deceased_chemo_yn
		,0 as final_hospice_days
		,count(*) as memcnt
	from post008.Members
	group by name_client, time_period, elig_status_1, deceased_yn, deceased_hospital_yn,
		       deceased_chemo_yn, final_hospice_days
	;
quit;

data post008.memcnt;
	format &memcnt_cgfrmt.;
	set memcnt_to_export;
	keep &memcnt_cgflds.;
run;

%LabelDataSet(post008.memcnt);

%put return_code = &syscc.;
