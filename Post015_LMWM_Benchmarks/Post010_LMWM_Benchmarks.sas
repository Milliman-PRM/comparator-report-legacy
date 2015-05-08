/*
### CODE OWNERS: Aaron Hoch

### OBJECTIVE:
	Internalize the logic for generating Loosely and Well-Managed Benchmarks.

### DEVELOPER NOTES:

*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(0)supp010_shared_code.sas";
%include "&M008_cde.func06_build_metadata_table.sas";
%include "&M073_Cde.pudd_methods\*.sas";

/* Libnames */
libname post008 "&post008." access=readonly;
libname post010 "&post010." access=readonly;
libname post015 "&post015.";

%let assign_name_client = name_client = "&name_client.";
%put assign_name_client = &assign_name_client.;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/


