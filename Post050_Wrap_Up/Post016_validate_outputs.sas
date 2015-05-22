/*
### CODE OWNERS: Aaron Hoch, Kyle Baird, Shea Parkes

### OBJECTIVE:
	Validate the outputs against the given data mart to ensure we are supplying
	data that meets specifications.

### DEVELOPER NOTES:
	<none>
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M002_cde.supp01_validation_functions.sas";

libname post050 "&post050.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/



%ValidateAgainstTemplate(
	validate_libname=post050
	,validate_template=&name_datamart_target.
	)

%put System Return Code = &syscc.;
