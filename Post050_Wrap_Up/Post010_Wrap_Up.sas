/*
### CODE OWNERS: Jason Altieri, Aaron Hoch

### OBJECTIVE:
	Take the metrics and stack them together.

### DEVELOPER NOTES:

*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

/* Libnames */
libname Post050 "&Post050.";


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*** SWEEP FOR METRIC TABLES ***/
%GetFilenamesFromDir(
					Directory=&path_postboarding_data_root.
					,Output=Files_to_Stack
					,Keepstrings=metrics
					,ExcludeStrings=metrics_key_value
					,subs=yes
					,types=files
					);

data parsed_filenames (drop=directory filename);
	set Files_to_stack;
	format
		path_directory $2048.
		name_file $256.
		;
	path_directory = directory;
	name_file = scan(
		scan(filename,1,"\","B")
		,1
		,"."
		);
	if index(filename,"\") gt 0 then path_directory = cats(
		path_directory
		,substr(
			filename
			,1
			,find(
				filename
				,"\"
				,"i"
				,-length(filename)
				)
			)
		);
run;

/*** DERIVE A CONCATENTATED LIBRARY ***/
proc sql noprint;
	select distinct
		cats("'",path_directory,"'")
	into :libs separated by ","
	from parsed_filenames
	;
quit;
%put libs = &libs.;

libname Source (&libs.);

proc sql noprint;
	select cats("Source",".",name_file)
	into :files_stack separated by " "
	from parsed_filenames
	;
quit;
%put files_stack = &files_stack.;

/*** STACK RESULTS ***/
data Post050.metrics_key_value;
	format &metrics_key_value_cgfrmt.;
	set &files_stack.;
	keep &metrics_key_value_cgflds.;
run;
%LabelDataSet(Post050.metrics_key_value)

%put System Return Code = &syscc.;
