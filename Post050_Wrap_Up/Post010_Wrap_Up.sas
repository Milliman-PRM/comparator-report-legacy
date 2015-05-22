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

%GetFilenamesFromDir(
					Directory=&path_postboarding_data_root.
					,Output=Files_to_Stack
					,Keepstrings=metrics
					,ExcludeStrings=metrics_key_value
					,subs=yes
					);

data parsed_filenames (drop=directory filename);
	set Files_to_stack;
	files=scan(scan(filename,2,"\"),1,".");
	libraries=cats(directory,"\",scan(filename,1,"\"));
run;

proc sql noprint;
	select cats("'",libraries,"'")
	into :libs separated by ","
	from parsed_filenames
	;
quit;


libname Source (&libs.);

proc sql noprint;
	select cats("Source",".",files)
	into :files_stack separated by " "
	from parsed_filenames
	;
quit;

data Post050.metrics_key_value;
	format &metrics_key_value_cgfrmt.;
	set &files_stack.;
run;

%put System Return Code = &syscc.;
