/*
### CODE OWNERS: Michael Menser 

### OBJECTIVE:
	Use the PRM outputs to create the Admission / Readmission report for NYP.

### DEVELOPER NOTES:
	This program creates a details table and then individual metrics.
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.PUDD_Methods\*.sas" / source2;

libname post008 "&post008." access = readonly;
libname post040 "&post040.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/
