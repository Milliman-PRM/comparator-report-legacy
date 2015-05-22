/*
### CODE OWNERS: Aaron Hoch, Kyle Baird

### OBJECTIVE:
	Move all of the Comparator Report files into one central location (assemble the datamart).

### DEVELOPER NOTES:
	<none>
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "%GetParentFolder(0)share01_postboarding_wrapup.sas" / source2;

libname post050 "&post050.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




proc sql noprint;
	select distinct
			name_table
		into :remaining_tables separated by " "				
		from metadata_target
		where upcase(name_table) ne "METRICS_KEY_VALUE"	/*This table is already in the Post050 library. So it does not need moved.*/
	;
quit;
%put remaining_tables = &remaining_tables.;

%sweep_for_sas_datasets()

proc sql noprint;
	select distinct
		quote(strip(path_directory))
	into :libs separated by ","
	from parsed_filenames
	;
quit;
%put libs = &libs.;

libname Source (&libs.) access=readOnly;

proc datasets NOLIST;
	copy 
		in= source 
		out= post050 memtype= data
		;
	select &remaining_tables.;
quit;

%put System Return Code = &syscc.;
