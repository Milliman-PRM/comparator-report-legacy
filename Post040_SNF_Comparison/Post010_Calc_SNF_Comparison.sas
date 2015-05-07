/*
### CODE OWNERS: Michael Menser 

### OBJECTIVE:
	Calculate the ACO Member Skilled Nursing Facility Metrics.  
    (See S:/PHI/NYP/Attachment A Core PACT Reports by Milliman for Premier.xlsx)

### DEVELOPER NOTES:
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&M073_Cde.PUDD_Methods\*.sas" / source2;
/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/
