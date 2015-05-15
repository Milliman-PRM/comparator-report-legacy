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

/*Create a table with the desceased statuses of the members (needed for the memcnt table)*/
proc sql;
	create table mem_desc_status as
	select
		"&name_client." as name_client
		,time_period
		,member_id
		,elig_status_1
		,'N' as deceased_yn /*TODO: Append with Decedent/End of Life information when available*/ 
		,'N' as deceased_hospital_yn
		,'N' as deceased_chemo_yn
		,0 as final_hospice_days
	from post008.Members
	;
quit;

/*Summarize the newly created table in order to generate the memcnt table*/
proc summary nway missing data=mem_desc_status;
	class name_client time_period elig_status_1 deceased_yn deceased_hospital_yn 
          deceased_chemo_yn final_hospice_days;
	output out = memcnt_to_export (drop = _TYPE_ rename=(_FREQ_=memcnt));
run;

/*Write the memcnt table out to the post008 library*/
data post008.memcnt;
	format &memcnt_cgfrmt.;
	set memcnt_to_export;
	keep &memcnt_cgflds.;
run;

%put return_code = &syscc.;
