/*
### CODE OWNERS: Jason Altieri

### OBJECTIVE:
	Take the metrics and stack them together.

### DEVELOPER NOTES:

*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M008_cde.func06_build_metadata_table.sas";
%include "&M073_Cde.pudd_methods\*.sas";

/* Libnames */
libname post008 "&post008." access=readonly;
libname post010 "&post010." access=readonly;
libname post015 "&post015." access=readonly;
libname post025 "&post025." access=readonly;
libname post040 "&post040." access=readonly;



/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/








%put System Return Code = &syscc.;
