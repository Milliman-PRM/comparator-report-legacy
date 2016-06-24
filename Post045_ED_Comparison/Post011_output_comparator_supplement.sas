/*
### CODE OWNERS: Brandon Patterson

### OBJECTIVE:
	Output the data collected for a Caromont one-off report

### DEVELOPER NOTES:
	<none>
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;


%let path_file_output = &post045.comparator_supplement.xlsx;
%put path_file_output = &path_file_output.;

libname post010 "&post010." access=readonly;
libname post025 "&post025." access=readonly;
libname post045 "&post045." access=readonly;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/
proc export
	data = post010.qtrly_drug_summary
	outfile = "&path_file_output."
	dbms = xlsx
	label
	replace
	;
	sheet = "Drug Summary";
run;

proc export
	data = post025.heart_failure_by_mem
	outfile = "&path_file_output."
	dbms = xlsx
	label
	replace
	;
	sheet = "Heart Failure";
run;

proc export
	data = post045.ed_prev_by_mem
	outfile = "&path_file_output."
	dbms = xlsx
	label
	replace
	;
	sheet = "ED - PCP Treatable";
run;

%put System Return Code = &syscc.;
