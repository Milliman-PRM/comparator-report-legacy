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




%sweep_for_sas_datasets()

proc sql;
	create table dsets as
	select
		*
	from parsed_filenames
	where upcase(name_file) in (
		select distinct
			upcase(name_table)
		from metadata_target
		)
		and upcase(path_directory) ne "%upcase(&post050.)" /*Ignore any files already in the proper output location*/
	;
quit;

proc sql noprint;
	select distinct
		quote(strip(path_directory))
	into :libs separated by ","
	from dsets
	;
quit;
%put libs = &libs.;

libname Source (&libs.) access=readOnly;

proc sql noprint;
	select distinct
		name_file
	into :remaining_tables separated by " "
	from dsets
	;
quit;
%put remaining_tables = &remaining_tables.;

proc datasets NOLIST;
	copy 
		in= source 
		out= post050 memtype= data
		;
	select &remaining_tables.;
quit;

%put System Return Code = &syscc.;
